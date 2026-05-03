defmodule Foglet.TUI.Widgets.Modal.Form do
  @moduledoc """
  Stateful modal-overlay form container (D-07, D-09, D-13, D-14).

  Hosts a caller-declared list of typed input fields and handles
  Tab/Shift-Tab focus navigation, Enter-on-last submits, and Esc
  cancels. Coerces per-field values to their native Elixir types
  on submit. Renders caller-supplied inline errors beneath each
  field without dismissing.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg on render/2
    * D-14     — `init/1 + handle_event/2 + render/2` (no process)

  Body-only render: the modal chrome (border + centering) is provided by
  `Foglet.TUI.App.render_modal_overlay/2`. Do NOT wrap the output in a
  box/border here — that causes double-borders (Phase 01.1 RESEARCH Pitfall 4).

  ## Focus navigation (Phase 28 FORM-01 / FORM-02 — D-13, D-14, D-15)

  Focus moves between fields via four equivalent forward keys and four
  equivalent backward keys:

    * Forward (advance focus, last → 0 wrap):
        * `%{key: :tab}`
        * `%{key: :down}` — only on `:text | :integer | :textarea` fields
    * Backward (retreat focus, 0 → last wrap):
        * `%{key: :tab, shift: true}`  (raw Raxol shape)
        * `%{key: :shift_tab}`         (CLIHandler-translated shape)
        * `%{key: :backtab}`           (CLIHandler-translated terminal `ESC[Z`)
        * `%{key: :up}`   — only on `:text | :integer | :textarea` fields

  Key equivalence (D-15): `%{key: :backtab}` ≡ `%{key: :shift_tab}` ≡
  `%{key: :tab, shift: true}`. All three trigger the same backward-with-wrap
  retreat and produce identical `{state, nil}` results.

  Wrap direction (D-14):
    * Forward (Tab / Down on text-like) wraps `last → 0`.
    * Backward (Shift+Tab / `:backtab` / Up on text-like) wraps `0 → last`.

  Up/Down on `:enum` fields cycle the field value via the existing field
  dispatcher and do NOT change `focus_index` (D-13).

  ## Enum field cycling and screen-side preview (D-25 D-03 / Pitfall 5)

  `:enum` fields update their internal field state on every `:up`/`:down` event
  (they do NOT wait for submit). Screens that need a live side effect on cycling
  (e.g. `Foglet.TUI.Screens.Account.PrefsForm` applying instant theme preview)
  should call `Modal.Form.field_value(form, :field_name)` after every
  `handle_event/2` and compare to the previous value:

      {form2, _action} = Modal.Form.handle_event(event, form)
      new_theme = Modal.Form.field_value(form2, :theme_id)
      if new_theme != old_theme, do: apply_theme_preview(new_theme)

  This avoids adding a public `:on_field_change` callback option (D-19 spirit)
  and keeps the public API surface minimal. See `field_value/2` for the accessor.

  ## Submit-state lifecycle (FORM-05 consumer obligation)

  Consumers of `Modal.Form` MUST drive `set_submit_state/2` to a
  terminal state (`{:error, msg}` or `:idle`) when an async submit
  fails, OR persist the `Modal.Form` struct across renders so the
  `:submitting` lock state is preserved.

    * The internal `:idle → :submitting` transition is set by the
      Enter-on-last-field clause (search for "Clause 4: Enter" in this
      file). After that point, the form is locked and only the consumer
      can release it.
    * The lock guard (search for "Clause 0: Lock") swallows every
      subsequent event, including `:escape`, until `submit_state`
      leaves `:submitting`.
      A wedged form has no keyboard escape — the user must close the
      SSH session.
    * Failing to drive `set_submit_state/2` on async failure (or
      rebuilding the form fresh per render and discarding the prior
      `submit_state`) nullifies the FORM-05 lock and the FORM-05
      status-row guarantees, and on `:form`-typed modals will
      permanently wedge the user (BL-01).
    * Reference: Phase 28 BL-01 (oneliner / hide-oneliner modals) and
      BL-02 (Sysop SiteForm) for examples of both failure modes.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Input.{Checkbox, RadioGroup, TextInput}
  alias Raxol.UI.Components.Input.MultiLineInput

  @type field_type :: :text | :integer | :boolean | :enum | :textarea
  @type field_spec :: %{
          required(:name) => atom(),
          required(:type) => field_type(),
          required(:label) => String.t(),
          optional(any()) => any()
        }

  @type action :: :submitted | {:submitted, term()} | :cancelled | nil

  @typedoc """
  Submit-state machine (Phase 28 FORM-05 / D-01..D-05).

  Transitions:
    * `:idle` → `:submitting` — internal only, on Enter-on-last-field
    * `:submitting` → `:saved` — caller-driven via `set_submit_state/2`
    * `:submitting` → `{:error, term}` — caller-driven via `set_submit_state/2`
    * `:saved` → `:idle` — auto-reset on the next non-locked event (D-04)
    * `{:error, _}` → `:idle` — auto-reset on the next non-locked event (D-04)
  """
  @type submit_state :: :idle | :submitting | :saved | {:error, term()}

  defstruct [
    :title,
    :fields,
    :field_states,
    :focus_index,
    :errors,
    :on_submit,
    :on_cancel,
    show_footer: false,
    submit_state: :idle
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          fields: [field_spec()],
          field_states: [term()],
          focus_index: non_neg_integer(),
          errors: %{atom() => String.t()},
          on_submit: (map() -> any()),
          on_cancel: (-> any()),
          show_footer: boolean(),
          submit_state: submit_state()
        }

  @doc """
  Initialise the form state.

  Options:
    * `:title`       — heading string
    * `:fields`      — list of field spec maps (see `field_spec/0`)
    * `:on_submit`   — `(map() -> any())` called with typed payload on submit
    * `:on_cancel`   — `(-> any())` called on Esc
    * `:show_footer` — boolean, default `false` (Phase 28 D-06 / FORM-03).
      When `true`, `render/2` appends a `[Enter] Submit   [Esc] Cancel` row in
      `theme.dim.fg`. Tab-body consumers (Account Profile/Prefs, Sysop Site)
      should leave this default-off so the global command bar is the single
      advertiser of those keys; true overlay callers (centered modals) opt in.

  Raises `ArgumentError` if `:fields` is not a list, or is an empty list
  (Phase 28 BL-03 / IN-03). Passing a non-list value (e.g. `nil`, a map,
  or an atom) used to crash later in `Enum.map/2` with a confusing
  `Protocol.UndefinedError`; the cond below produces a friendly message
  describing the actual constraint.
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    fields = Keyword.fetch!(opts, :fields)

    cond do
      not is_list(fields) ->
        raise ArgumentError,
              "Modal.Form requires :fields to be a list; got #{inspect(fields)}"

      fields == [] ->
        raise ArgumentError,
              "Modal.Form requires at least one field; received an empty :fields list"

      true ->
        :ok
    end

    field_states = Enum.map(fields, &build_field_state/1)

    %__MODULE__{
      title: Keyword.get(opts, :title, ""),
      fields: fields,
      field_states: field_states,
      focus_index: 0,
      errors: %{},
      on_submit: Keyword.fetch!(opts, :on_submit),
      on_cancel: Keyword.fetch!(opts, :on_cancel),
      show_footer: Keyword.get(opts, :show_footer, false)
    }
  end

  @doc """
  Pure (event, state) -> {state, action | nil}.

  Public entry: applies the submit-state lock guard (Phase 28 D-02) and the
  auto-reset preamble (D-04) before dispatching to `do_handle_event/2`.

    * Lock (D-02): when `submit_state == :submitting`, EVERY event is swallowed
      and `{state, nil}` is returned. Consuming screens drive the transition
      out of `:submitting` via `set_submit_state/2` once async work completes.
    * Auto-reset (D-04): when `submit_state` is `:saved` or `{:error, _}`, the
      next non-locked event resets `submit_state` to `:idle` BEFORE the rest of
      the dispatch runs, so the form is editable again. The auto-reset never
      fires from the locked branch (the lock guard short-circuits first).
  """
  @spec handle_event(map(), t()) :: {t(), action()}

  # Clause 0: Lock — while :submitting, swallow all events (Phase 28 D-02).
  # Reserved for the internal :idle → :submitting transition only; consuming
  # screens transition out via set_submit_state/2 (D-03).
  def handle_event(_event, %__MODULE__{submit_state: :submitting} = state) do
    {state, nil}
  end

  # Public entry: auto-reset terminal states, then dispatch.
  def handle_event(event, %__MODULE__{} = state) do
    state
    |> maybe_auto_reset_submit_state()
    |> do_handle_event(event)
    |> normalize_focus_to_visible()
  end

  # FOG-349 :visible_when — if the focused field is hidden after an event
  # (e.g. user toggled chat off and the storage row vanished), hop the focus
  # to the nearest visible field so the cursor stays usable. Wrap to the first
  # visible field when no later visible field exists.
  defp normalize_focus_to_visible({%__MODULE__{} = state, action}) do
    vis = visible_indices(state)

    cond do
      vis == [] ->
        {state, action}

      state.focus_index in vis ->
        {state, action}

      true ->
        new_idx =
          Enum.find(vis, &(&1 > state.focus_index)) || List.last(vis) || 0

        {%{state | focus_index: new_idx}, action}
    end
  end

  # Auto-reset preamble (Phase 28 D-04) — collapses :saved and {:error, _}
  # back to :idle on the next non-locked event so the form is editable again.
  # The :submitting branch is already short-circuited by the lock guard above.
  defp maybe_auto_reset_submit_state(%__MODULE__{submit_state: :saved} = state),
    do: %{state | submit_state: :idle}

  defp maybe_auto_reset_submit_state(%__MODULE__{submit_state: {:error, _}} = state),
    do: %{state | submit_state: :idle}

  defp maybe_auto_reset_submit_state(%__MODULE__{} = state), do: state

  # Clause 1: Esc — cancel unconditionally (REQ-6)
  defp do_handle_event(%__MODULE__{on_cancel: cb} = state, %{key: :escape}) do
    _ = cb.()
    {state, :cancelled}
  end

  # Clause 2: Shift-Tab — retreat with wrap (REQ-4)
  # Shape %{key: :tab, shift: true} verified against
  # vendor/raxol/lib/raxol/ui/components/modal/events.ex:94
  defp do_handle_event(%__MODULE__{} = state, %{key: :tab, shift: true}) do
    {%{state | focus_index: prev_visible_index(state)}, nil}
  end

  # Clause 2b: Shift-Tab — Foglet/CLIHandler-translated shape (D-25 Pitfall 1)
  # CLIHandler emits %{key: :shift_tab} when the terminal sends back-tab (ESC[Z).
  # Keep this clause adjacent to Clause 2 so the pattern is visually obvious.
  defp do_handle_event(%__MODULE__{} = state, %{key: :shift_tab}) do
    {%{state | focus_index: prev_visible_index(state)}, nil}
  end

  # Clause 2c: Back-tab — terminal `ESC[Z` after CLIHandler translation (Phase 28 D-15).
  # Equivalent to %{key: :shift_tab} and %{key: :tab, shift: true}.
  defp do_handle_event(%__MODULE__{} = state, %{key: :backtab}) do
    {%{state | focus_index: prev_visible_index(state)}, nil}
  end

  # Clause 3: Tab — advance with wrap (REQ-4). Hidden fields (FOG-349
  # :visible_when) are skipped during traversal.
  defp do_handle_event(%__MODULE__{} = state, %{key: :tab}) do
    {%{state | focus_index: next_visible_index(state)}, nil}
  end

  # Clause 4: Enter — submit if last *visible* field, otherwise advance (REQ-5).
  # Phase 28 D-05: on submit, transitions :idle → :submitting and invokes
  # on_submit exactly once; subsequent Enter events are swallowed by the
  # lock guard (Clause 0) until the consuming screen calls set_submit_state/2.
  # By the time this clause runs, the lock guard has short-circuited any
  # :submitting state and the auto-reset preamble has collapsed :saved /
  # {:error, _} back to :idle, so submit_state here is always :idle.
  # FOG-349: "last field" tracks the last *visible* field; hidden fields are
  # excluded from both navigation and the submit payload.
  defp do_handle_event(%__MODULE__{} = state, %{key: :enter}) do
    case List.last(visible_indices(state)) do
      nil ->
        {state, nil}

      last_visible when state.focus_index == last_visible ->
        payload = collect_values(state)
        submit_result = state.on_submit.(payload)
        {%{state | submit_state: :submitting}, submitted_action(submit_result)}

      _ ->
        {%{state | focus_index: next_visible_index(state)}, nil}
    end
  end

  # Clause 4b: Down — focus advance on text-like fields, value cycle on :enum
  # (Phase 28 D-13, D-14). On :text/:integer/:textarea, advance focus_index with
  # wrap (last → 0); on :enum, fall through to dispatch_to_field/3 so the field
  # updates its internal index (existing enum cycling). On any other type
  # (e.g. :boolean) also fall through, preserving today's per-field semantics.
  defp do_handle_event(%__MODULE__{} = state, %{key: :down} = event) do
    case Enum.at(state.fields, state.focus_index) do
      %{type: type} when type in [:text, :integer, :textarea] ->
        {%{state | focus_index: next_visible_index(state)}, nil}

      _other ->
        dispatch_event_to_field(event, state)
    end
  end

  # Clause 4c: Up — focus retreat on text-like fields, value cycle on :enum
  # (Phase 28 D-13, D-14). Backward wrap is 0 → last.
  defp do_handle_event(%__MODULE__{} = state, %{key: :up} = event) do
    case Enum.at(state.fields, state.focus_index) do
      %{type: type} when type in [:text, :integer, :textarea] ->
        {%{state | focus_index: prev_visible_index(state)}, nil}

      _other ->
        dispatch_event_to_field(event, state)
    end
  end

  # Clause 5: dispatch to focused field
  defp do_handle_event(%__MODULE__{} = state, event) do
    dispatch_event_to_field(event, state)
  end

  # Internal helper extracted so the Up/Down clauses can reuse the
  # field-dispatch body without duplicating it (Phase 28 D-13).
  defp dispatch_event_to_field(event, %__MODULE__{} = state) do
    spec = Enum.at(state.fields, state.focus_index)
    field_state = Enum.at(state.field_states, state.focus_index)
    new_field_state = dispatch_to_field(spec, field_state, event)
    new_states = List.replace_at(state.field_states, state.focus_index, new_field_state)
    {%{state | field_states: new_states}, nil}
  end

  defp submitted_action(result) when result in [:ok, nil], do: :submitted
  defp submitted_action(result), do: {:submitted, result}

  @doc """
  Return the current typed value of a named field without submitting.

  Useful for screen-level side effects on enum cycling (D-25 D-03 / Pitfall 5).
  Screens that need a live preview (e.g. instant theme change on `:theme_id`
  cycling) should call `Modal.Form.field_value(form, :theme_id)` after every
  `handle_event/2` and diff against the previous value to trigger the preview.
  Reference consumer: `Foglet.TUI.Screens.Account.PrefsForm` (Plan 02).

  Returns `nil` when the field name is not present in the form.
  """
  @spec field_value(t(), atom()) :: term() | nil
  def field_value(%__MODULE__{fields: fields, field_states: states}, field_name)
      when is_atom(field_name) do
    case Enum.find_index(fields, &(&1.name == field_name)) do
      nil -> nil
      idx -> coerce(Enum.at(fields, idx), Enum.at(states, idx))
    end
  end

  @doc "Merge server-side validation errors into the form state (D-18)."
  @spec set_errors(t(), %{atom() => String.t()}) :: t()
  def set_errors(%__MODULE__{} = state, errors) when is_map(errors) do
    %{state | errors: errors}
  end

  @doc """
  Transition the form's `submit_state` to a caller-allowed terminal state
  (Phase 28 FORM-05 / D-03).

  Allowed values: `:idle`, `:saved`, `{:error, term()}`.

  Raises `ArgumentError` if called with `:submitting` — that transition is
  reserved for the internal Enter-on-last-field clause. Consuming screens
  call this setter once async work completes (success → `:saved`; failure →
  `{:error, msg}`); the very next non-locked user event auto-resets the form
  back to `:idle` so it is editable again (D-04).
  """
  @spec set_submit_state(t(), :idle | :saved | {:error, term()}) :: t()
  def set_submit_state(%__MODULE__{}, :submitting) do
    raise ArgumentError,
          "Modal.Form.set_submit_state/2 cannot be called with :submitting; " <>
            "the :submitting transition is reserved for the internal " <>
            "Enter-on-last-field clause (Phase 28 D-03)."
  end

  def set_submit_state(%__MODULE__{} = state, new) when new == :idle or new == :saved do
    %{state | submit_state: new}
  end

  def set_submit_state(%__MODULE__{} = state, {:error, _term} = new) do
    %{state | submit_state: new}
  end

  @doc """
  Replay a previously-captured `submit_state` onto a freshly-built form
  (Phase 28 D-17 rebuild-and-replay pattern).

  Unlike `set_submit_state/2`, this accepts the *full* lifecycle including
  `:submitting`. It is the documented escape hatch for consumers that
  rebuild the `Modal.Form` per render (e.g. `Foglet.TUI.Screens.Sysop.SiteForm`)
  and need to faithfully re-seed the new form with the lifecycle value
  persisted on the wrapper struct between renders.

  Use `set_submit_state/2` for normal terminal-state transitions; this
  function exists solely for the rebuild path. Callers MUST NOT use it to
  smuggle `:submitting` from outside the FORM-05 contract — the value
  passed in must have come from a prior `Modal.Form` instance's
  `submit_state` field.
  """
  @spec replay_submit_state(t(), submit_state()) :: t()
  def replay_submit_state(%__MODULE__{} = state, value)
      when value in [:idle, :submitting, :saved] do
    %{state | submit_state: value}
  end

  def replay_submit_state(%__MODULE__{} = state, {:error, _term} = value) do
    %{state | submit_state: value}
  end

  @doc """
  Render the form body as a bare `column` — no outer box/border (RESEARCH Pitfall 4).

  Options:
    * `:theme` — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{} = state, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    title_row = text(state.title, fg: theme.title.fg, style: [:bold])
    divider = text(String.duplicate("─", 40), fg: theme.border.fg)

    vis = MapSet.new(visible_indices(state))

    field_rows =
      state.fields
      |> Enum.with_index()
      |> Enum.filter(fn {_spec, idx} -> MapSet.member?(vis, idx) end)
      |> Enum.flat_map(fn {spec, idx} ->
        focused? = idx == state.focus_index
        field_state = Enum.at(state.field_states, idx)
        render_field(spec, field_state, focused?, state.errors, theme)
      end)

    base_error_rows =
      case Map.get(state.errors, :base) do
        nil -> []
        msg -> [text(msg, fg: theme.error.fg)]
      end

    # Phase 28 FORM-05 / D-08: status row reflects the submit_state machine.
    # Empty when :idle; one row of "Saving…", "Saved.", or "Error: <msg>"
    # otherwise. The Unicode ellipsis (U+2026) is intentional per CONTEXT D-08.
    status_rows = render_status_row(state.submit_state, theme)

    # Phase 28 FORM-03 / D-06: footer is opt-in via init(show_footer: true).
    # Default is `false` so tab-body consumers don't double-up against the
    # global command bar; overlay-style forms opt in explicitly.
    # Phase 28 D-09: when a status row is present, it REPLACES the footer.
    footer_rows =
      cond do
        status_rows != [] -> []
        state.show_footer -> [text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)]
        true -> []
      end

    column [] do
      [title_row, divider] ++ field_rows ++ base_error_rows ++ status_rows ++ footer_rows
    end
  end

  # Status row clauses (Phase 28 FORM-05 / D-08, D-09).
  defp render_status_row(:idle, _theme), do: []

  defp render_status_row(:submitting, %Theme{} = theme),
    do: [text("Saving…", fg: theme.dim.fg)]

  defp render_status_row(:saved, %Theme{} = theme),
    do: [text("Saved.", fg: status_saved_fg(theme))]

  defp render_status_row({:error, msg}, %Theme{} = theme),
    do: [text("Error: #{msg}", fg: theme.error.fg)]

  # Theme.success.fg is the canonical "saved" color, but defensively fall back
  # to theme.accent.fg if a future theme leaves :success blank — keeps Modal.Form
  # theme-agnostic and avoids a hard dependency on Theme schema details.
  defp status_saved_fg(%Theme{} = theme) do
    case theme do
      %Theme{success: %{fg: fg}} when not is_nil(fg) -> fg
      _ -> theme.accent.fg
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_field_state(%{type: :text} = spec) do
    TextInput.init(
      value: Map.get(spec, :value, ""),
      max_length: Map.get(spec, :max_length, 256),
      placeholder: Map.get(spec, :placeholder, "")
    )
  end

  defp build_field_state(%{type: :integer} = spec) do
    TextInput.init(
      value: Map.get(spec, :value, ""),
      max_length: Map.get(spec, :max_length, 256),
      placeholder: Map.get(spec, :placeholder, "")
    )
  end

  defp build_field_state(%{type: :boolean} = spec) do
    Map.get(spec, :value, false)
  end

  defp build_field_state(%{type: :enum} = spec) do
    values = enum_values(spec)

    case Map.get(spec, :value) do
      nil ->
        0

      val ->
        Enum.find_index(values, &(&1 == val)) || 0
    end
  end

  defp build_field_state(%{type: :textarea} = spec) do
    initial_value = Map.get(spec, :value, "")

    {:ok, mli_state} =
      MultiLineInput.init(%{
        value: initial_value,
        width: Map.get(spec, :width, 40),
        height: Map.get(spec, :rows, 3)
      })

    # Track raw_value separately — MultiLineInput.update/2 does not reliably
    # propagate newlines back into the :value field after further edits (vendor
    # limitation discovered during plan 01.1-02 TDD GREEN phase).
    %{mli_state: mli_state, raw_value: initial_value}
  end

  defp dispatch_to_field(%{type: type}, field_state, event) when type in [:text, :integer] do
    {new_ti, _action} = TextInput.handle_event(event, field_state)
    new_ti
  end

  defp dispatch_to_field(%{type: :boolean}, field_state, %{key: :char, char: " "}) do
    !field_state
  end

  defp dispatch_to_field(%{type: :boolean}, field_state, _event) do
    field_state
  end

  defp dispatch_to_field(%{type: :enum} = spec, field_state, %{key: :down}) do
    case length(enum_values(spec)) do
      0 -> field_state
      n -> max(0, min(field_state + 1, n - 1))
    end
  end

  defp dispatch_to_field(%{type: :enum}, field_state, %{key: :up}) do
    max(field_state - 1, 0)
  end

  defp dispatch_to_field(%{type: :enum}, field_state, _event) do
    field_state
  end

  defp dispatch_to_field(
         %{type: :textarea},
         %{mli_state: mli, raw_value: rv} = field_state,
         event
       ) do
    # Treat char: "\n" as an enter keypress so textarea accepts newlines from
    # String.codepoints/1 event streams (codepoint 10 is filtered by Compose.translate_key).
    msg =
      case event do
        %{key: :char, char: "\n"} -> {:enter}
        _ -> Compose.translate_key(event)
      end

    case msg do
      nil ->
        field_state

      _ ->
        new_mli =
          case MultiLineInput.update(msg, mli) do
            {:noreply, new_state, _cmds} -> new_state
            new_state -> new_state
          end

        # Maintain raw_value independently because MultiLineInput.value loses
        # newlines once more characters are typed after {:enter}.
        new_rv = apply_raw_edit(rv, event)

        %{field_state | mli_state: new_mli, raw_value: new_rv}
    end
  end

  defp collect_values(%__MODULE__{fields: fields, field_states: states} = state) do
    vis = MapSet.new(visible_indices(state))

    fields
    |> Enum.zip(states)
    |> Enum.with_index()
    |> Enum.filter(fn {_pair, idx} -> MapSet.member?(vis, idx) end)
    |> Map.new(fn {{spec, st}, _idx} -> {spec.name, coerce(spec, st)} end)
  end

  # FOG-349: full coerced values map for predicate evaluation. Unlike
  # collect_values/1 (the submit payload) this includes every field — hidden or
  # visible — so visible_when predicates can read sibling field values that may
  # themselves be hidden.
  defp current_values(%__MODULE__{fields: fields, field_states: states}) do
    fields
    |> Enum.zip(states)
    |> Map.new(fn {spec, st} -> {spec.name, coerce(spec, st)} end)
  end

  # FOG-349: indices of fields whose :visible_when predicate returns truthy.
  # Fields without :visible_when are always visible. Predicates receive the
  # current coerced values map (current_values/1).
  defp visible_indices(%__MODULE__{fields: fields} = state) do
    values = current_values(state)

    fields
    |> Enum.with_index()
    |> Enum.filter(fn {spec, _idx} -> field_visible?(spec, values) end)
    |> Enum.map(fn {_spec, idx} -> idx end)
  end

  defp field_visible?(spec, values) do
    case Map.get(spec, :visible_when) do
      nil -> true
      fun when is_function(fun, 1) -> !!fun.(values)
    end
  end

  defp next_visible_index(%__MODULE__{focus_index: cur} = state) do
    case visible_indices(state) do
      [] -> cur
      vis -> Enum.find(vis, &(&1 > cur)) || List.first(vis)
    end
  end

  defp prev_visible_index(%__MODULE__{focus_index: cur} = state) do
    case visible_indices(state) do
      [] -> cur
      vis -> vis |> Enum.reverse() |> Enum.find(&(&1 < cur)) || List.last(vis)
    end
  end

  # FOG-349: tuple-form `:enum` choice support. Choices may be either a flat
  # list of values (`[:red, :green]`, `["a", "b"]`) or `{label, value}` tuples
  # (`[{"Red", :red}, {"Green", :green}]`). Persisted/coerced values are always
  # the raw value (right-hand side); render uses the human label.
  defp enum_values(%{type: :enum} = spec) do
    Map.get(spec, :choices, [])
    |> Enum.map(fn
      {_label, value} -> value
      value -> value
    end)
  end

  defp enum_labels(%{type: :enum} = spec) do
    Map.get(spec, :choices, [])
    |> Enum.map(fn
      {label, _value} -> to_string(label)
      value -> to_string(value)
    end)
  end

  defp coerce(%{type: :text}, %TextInput{raxol_state: %{value: v}}), do: v || ""

  defp coerce(%{type: :integer}, %TextInput{raxol_state: %{value: v}}) do
    case Integer.parse(String.trim(v || "")) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp coerce(%{type: :boolean}, bool), do: !!bool

  defp coerce(%{type: :enum} = spec, idx) when is_integer(idx) do
    Enum.at(enum_values(spec), idx)
  end

  defp coerce(%{type: :textarea}, %{raw_value: rv}), do: rv

  defp render_field(spec, field_state, focused?, errors, theme) do
    label_fg = if focused?, do: theme.accent.fg, else: theme.primary.fg
    label_style = if focused?, do: [:bold], else: []

    marker = if Map.get(spec, :required, false), do: " *", else: ""
    label_row = text("#{spec.label}#{marker}:", fg: label_fg, style: label_style)
    widget_row = render_widget(spec, field_state, focused?, theme)

    # Phase 28 Plan 04 substrate add: optional :description renders as a dim
    # row beneath the widget when the field spec carries a non-empty
    # :description string. Used by Sysop SiteForm to preserve Schema description
    # copy through the Modal.Form migration. Other consumers may opt in by
    # adding :description to their field spec.
    description_rows =
      case Map.get(spec, :description) do
        nil -> []
        "" -> []
        desc when is_binary(desc) -> [text(desc, fg: theme.dim.fg)]
      end

    error_rows =
      case Map.get(errors, spec.name) do
        nil -> []
        msg -> [text(msg, fg: theme.error.fg)]
      end

    [label_row, widget_row] ++ description_rows ++ error_rows
  end

  defp render_widget(%{type: type}, field_state, focused?, theme)
       when type in [:text, :integer] do
    TextInput.render(field_state, focused: focused?, theme: theme)
  end

  defp render_widget(%{type: :boolean, label: label}, field_state, _focused?, theme) do
    Checkbox.render(label, checked?: field_state, theme: theme)
  end

  defp render_widget(%{type: :enum} = spec, field_state, _focused?, theme) do
    str_choices = enum_labels(spec)

    case Map.get(spec, :display, :radio) do
      :compact ->
        render_compact_enum(str_choices, field_state, theme)

      _radio ->
        RadioGroup.render(str_choices, field_state, theme: theme)
    end
  end

  defp render_widget(%{type: :textarea}, %{mli_state: mli}, focused?, theme) do
    Compose.render_input(mli, focused?, theme)
  end

  # Compact single-line enum picker (FOG-132).
  #
  # Renders the current selection as `‹ value › (i/n)` on one row instead of
  # one row per choice. Used for enum fields whose choice count would otherwise
  # overflow the modal body at 80x24 (timezone has 24 IANA zones). Cycling
  # still uses the unchanged :up/:down dispatcher.
  defp render_compact_enum([], _idx, %Theme{} = theme) do
    text("‹ — › (0/0)", fg: theme.dim.fg)
  end

  defp render_compact_enum(choices, idx, %Theme{} = theme) when is_list(choices) do
    n = length(choices)
    safe_idx = idx |> max(0) |> min(n - 1)
    value = Enum.at(choices, safe_idx)
    text("‹ #{value} › (#{safe_idx + 1}/#{n})", fg: theme.selected.fg, style: [:bold])
  end

  # ---------------------------------------------------------------------------
  # Raw value tracking for textarea (vendor limitation workaround)
  # ---------------------------------------------------------------------------

  # Apply key event to the raw_value string mirror. This bypasses
  # MultiLineInput's unreliable value/lines sync and gives us a clean string.
  defp apply_raw_edit(rv, %{key: :char, char: "\n"}), do: rv <> "\n"
  defp apply_raw_edit(rv, %{key: :char, char: c}), do: rv <> c
  defp apply_raw_edit(rv, %{key: :enter}), do: rv <> "\n"

  defp apply_raw_edit(rv, %{key: :backspace}), do: String.slice(rv, 0..-2//1)

  defp apply_raw_edit(rv, _event), do: rv
end

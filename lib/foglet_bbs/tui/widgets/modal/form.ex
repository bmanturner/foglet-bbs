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

  @type action :: :submitted | :cancelled | nil

  defstruct [
    :title,
    :fields,
    :field_states,
    :focus_index,
    :errors,
    :on_submit,
    :on_cancel
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          fields: [field_spec()],
          field_states: [term()],
          focus_index: non_neg_integer(),
          errors: %{atom() => String.t()},
          on_submit: (map() -> any()),
          on_cancel: (-> any())
        }

  @doc """
  Initialise the form state.

  Options:
    * `:title`     — heading string
    * `:fields`    — list of field spec maps (see `field_spec/0`)
    * `:on_submit` — `(map() -> any())` called with typed payload on submit
    * `:on_cancel` — `(-> any())` called on Esc
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    fields = Keyword.fetch!(opts, :fields)
    field_states = Enum.map(fields, &build_field_state/1)

    %__MODULE__{
      title: Keyword.get(opts, :title, ""),
      fields: fields,
      field_states: field_states,
      focus_index: 0,
      errors: %{},
      on_submit: Keyword.fetch!(opts, :on_submit),
      on_cancel: Keyword.fetch!(opts, :on_cancel)
    }
  end

  @doc "Pure (event, state) -> {state, action | nil}."
  @spec handle_event(map(), t()) :: {t(), action()}

  # Clause 1: Esc — cancel unconditionally (REQ-6)
  def handle_event(%{key: :escape}, %__MODULE__{on_cancel: cb} = state) do
    _ = cb.()
    {state, :cancelled}
  end

  # Clause 2: Shift-Tab — retreat with wrap (REQ-4)
  # Shape %{key: :tab, shift: true} verified against
  # vendor/raxol/lib/raxol/ui/components/modal/events.ex:94
  def handle_event(%{key: :tab, shift: true}, %__MODULE__{} = state) do
    n = length(state.fields)
    new_idx = rem(state.focus_index - 1 + n, n)
    {%{state | focus_index: new_idx}, nil}
  end

  # Clause 3: Tab — advance with wrap (REQ-4)
  def handle_event(%{key: :tab}, %__MODULE__{} = state) do
    n = length(state.fields)
    new_idx = rem(state.focus_index + 1, n)
    {%{state | focus_index: new_idx}, nil}
  end

  # Clause 4: Enter — submit if last field, otherwise advance (REQ-5)
  def handle_event(%{key: :enter}, %__MODULE__{} = state) do
    last_idx = length(state.fields) - 1

    if state.focus_index == last_idx do
      payload = collect_values(state)
      _ = state.on_submit.(payload)
      {state, :submitted}
    else
      n = length(state.fields)
      {%{state | focus_index: rem(state.focus_index + 1, n)}, nil}
    end
  end

  # Clause 5: dispatch to focused field
  def handle_event(event, %__MODULE__{} = state) do
    spec = Enum.at(state.fields, state.focus_index)
    field_state = Enum.at(state.field_states, state.focus_index)
    new_field_state = dispatch_to_field(spec, field_state, event)
    new_states = List.replace_at(state.field_states, state.focus_index, new_field_state)
    {%{state | field_states: new_states}, nil}
  end

  @doc "Merge server-side validation errors into the form state (D-18)."
  @spec set_errors(t(), %{atom() => String.t()}) :: t()
  def set_errors(%__MODULE__{} = state, errors) when is_map(errors) do
    %{state | errors: errors}
  end

  @doc """
  Render the form body as a bare `column` — no outer box/border (RESEARCH Pitfall 4).

  Options:
    * `:theme` — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{} = state, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    title_row = text(" #{state.title} ", fg: theme.title.fg, style: [:bold])
    divider = text(String.duplicate("─", 40), fg: theme.border.fg)
    hint = text("[Tab] Next  [Shift+Tab] Prev  [Enter] Submit  [Esc] Cancel", fg: theme.dim.fg)

    field_rows =
      state.fields
      |> Enum.with_index()
      |> Enum.flat_map(fn {spec, idx} ->
        focused? = idx == state.focus_index
        field_state = Enum.at(state.field_states, idx)
        render_field(spec, field_state, focused?, state.errors, theme)
      end)

    column [] do
      [title_row, divider] ++ field_rows ++ [hint]
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
    choices = Map.get(spec, :choices, [])

    case Map.get(spec, :value) do
      nil ->
        0

      val ->
        Enum.find_index(choices, &(&1 == val)) || 0
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

  defp dispatch_to_field(%{type: :enum, choices: choices}, field_state, %{key: :down}) do
    min(field_state + 1, length(choices) - 1)
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

  defp collect_values(%__MODULE__{fields: fields, field_states: states}) do
    fields
    |> Enum.zip(states)
    |> Map.new(fn {spec, st} -> {spec.name, coerce(spec, st)} end)
  end

  defp coerce(%{type: :text}, %TextInput{raxol_state: %{value: v}}), do: v

  defp coerce(%{type: :integer}, %TextInput{raxol_state: %{value: v}}) do
    case Integer.parse(String.trim(v || "")) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp coerce(%{type: :boolean}, bool), do: !!bool

  defp coerce(%{type: :enum, choices: choices}, idx) when is_integer(idx) do
    Enum.at(choices, idx)
  end

  defp coerce(%{type: :textarea}, %{raw_value: rv}), do: rv

  defp render_field(spec, field_state, focused?, errors, theme) do
    label_fg = if focused?, do: theme.accent.fg, else: theme.primary.fg
    label_style = if focused?, do: [:bold], else: []

    label_row = text("#{spec.label}:", fg: label_fg, style: label_style)
    widget_row = render_widget(spec, field_state, focused?, theme)

    error_rows =
      case Map.get(errors, spec.name) do
        nil -> []
        msg -> [text(msg, fg: theme.error.fg)]
      end

    [label_row, widget_row] ++ error_rows
  end

  defp render_widget(%{type: type}, field_state, _focused?, theme)
       when type in [:text, :integer] do
    TextInput.render(field_state, theme: theme)
  end

  defp render_widget(%{type: :boolean, label: label}, field_state, _focused?, theme) do
    Checkbox.render(label, checked?: field_state, theme: theme)
  end

  defp render_widget(%{type: :enum, choices: choices}, field_state, _focused?, theme) do
    str_choices = Enum.map(choices, &to_string/1)
    RadioGroup.render(str_choices, field_state, theme: theme)
  end

  defp render_widget(%{type: :textarea}, %{mli_state: mli}, focused?, theme) do
    Compose.render_input(mli, focused?, theme)
  end

  # ---------------------------------------------------------------------------
  # Raw value tracking for textarea (vendor limitation workaround)
  # ---------------------------------------------------------------------------

  # Apply key event to the raw_value string mirror. This bypasses
  # MultiLineInput's unreliable value/lines sync and gives us a clean string.
  defp apply_raw_edit(rv, %{key: :char, char: "\n"}), do: rv <> "\n"
  defp apply_raw_edit(rv, %{key: :char, char: c}), do: rv <> c
  defp apply_raw_edit(rv, %{key: :enter}), do: rv <> "\n"

  defp apply_raw_edit(rv, %{key: :backspace}) do
    case String.length(rv) do
      0 -> rv
      _ -> String.slice(rv, 0, String.length(rv) - 1)
    end
  end

  defp apply_raw_edit(rv, _event), do: rv
end

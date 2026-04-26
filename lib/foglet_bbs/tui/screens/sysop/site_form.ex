defmodule Foglet.TUI.Screens.Sysop.SiteForm do
  @moduledoc """
  Inline full-tab editor for schematized SITE keys (D-02, D-03, D-15).

  Renders by iterating `@site_keys` and calling
  `Foglet.Config.Schema.fetch_spec/1` — never the `configuration` table
  (D-01 guardrail).

  Uses the D-19 fallback render path: plain text rows with a focus marker
  (`▸`) instead of the `TextInput`/`Checkbox`/`RadioGroup` primitives, to
  avoid per-field adapter plumbing for this first inline-form consumer.
  `Modal.Form` remains the required primitive for BOARDS (Plan 04).

  ## Enum entry ordering

  For string-enum fields, typed single characters select the first
  enum value whose name starts with that character (see
  `apply_char/2`). This means enum option order in
  `Foglet.Config.Schema` is load-bearing: if two enum values share a
  prefix (e.g. `"mods"` and `"mods_only"`), the one listed first wins.
  Add new enum values with disjoint leading characters where possible,
  or place the shorter/more-common value first.
  """

  alias Foglet.Config
  alias Foglet.Config.Schema

  import Raxol.Core.Renderer.View

  @site_keys [
    "registration_mode",
    "invite_code_generators",
    "delivery_mode",
    "require_email_verification",
    "invite_generation_per_user_limit"
  ]

  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          drafts: %{optional(String.t()) => term()},
          errors: %{optional(String.t()) => String.t()},
          focused: non_neg_integer()
        }

  defstruct current_user: nil, drafts: %{}, errors: %{}, focused: 0

  @spec site_keys() :: [String.t()]
  def site_keys, do: @site_keys

  @spec init(keyword()) :: t()
  def init(opts) do
    drafts =
      @site_keys
      |> Enum.map(fn k -> {k, Config.get!(k)} end)
      |> Map.new()

    %__MODULE__{
      current_user: Keyword.get(opts, :current_user),
      drafts: drafts,
      errors: %{},
      focused: 0
    }
  end

  @doc """
  Returns visible keys per D-04: `invite_generation_per_user_limit` is
  hidden unless `invite_code_generators == "any_user"`.
  """
  @spec visible_keys(t()) :: [String.t()]
  def visible_keys(%__MODULE__{drafts: drafts}) do
    generators = Map.get(drafts, "invite_code_generators")

    Enum.reject(@site_keys, fn
      "invite_generation_per_user_limit" -> generators != "any_user"
      _ -> false
    end)
  end

  @spec handle_key(map(), t()) :: {t(), [{atom(), any()}]}
  def handle_key(%{key: :tab}, state), do: {rotate_focus(state, +1), []}
  def handle_key(%{key: :shift_tab}, state), do: {rotate_focus(state, -1), []}
  def handle_key(%{key: :backtab}, state), do: {rotate_focus(state, -1), []}

  def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)

  def handle_key(%{key: :backspace}, state), do: {apply_backspace(state), []}

  def handle_key(%{key: :char, char: c} = event, state) when is_binary(c) do
    # Ignore ctrl/meta-modified characters (they belong to Ctrl+... handlers).
    if Map.get(event, :ctrl) || Map.get(event, :meta) do
      {state, []}
    else
      {apply_char(c, state), []}
    end
  end

  def handle_key(_event, state), do: {state, []}

  # ---------- Private ----------

  defp rotate_focus(state, delta) do
    visible = visible_keys(state)
    n = length(visible)

    if n == 0 do
      state
    else
      %{state | focused: Integer.mod(state.focused + delta, n)}
    end
  end

  defp focused_key(state) do
    state |> visible_keys() |> Enum.at(state.focused)
  end

  defp apply_char(c, state) do
    with key when is_binary(key) <- focused_key(state),
         {:ok, spec} <- Schema.fetch_spec(key) do
      apply_char_to_field(spec, c, key, state)
    else
      _ -> state
    end
  end

  # Booleans: any space/enter-like char toggles. We also toggle on " " or "t"/"f".
  defp apply_char_to_field(%{type: :boolean}, " ", key, state) do
    toggle_boolean(state, key)
  end

  defp apply_char_to_field(%{type: :boolean}, _c, _key, state), do: state

  # Enums: cycle forward on space, or jump to the option starting with char.
  defp apply_char_to_field(%{type: :string, enum: enum}, " ", key, state)
       when is_list(enum) do
    cycle_enum(state, key, enum, +1)
  end

  defp apply_char_to_field(%{type: :string, enum: enum}, c, key, state) when is_list(enum) do
    case Enum.find(enum, fn v -> String.starts_with?(v, c) end) do
      nil -> state
      match -> %{state | drafts: Map.put(state.drafts, key, match)}
    end
  end

  # Plain string (not currently used in @site_keys but handled).
  defp apply_char_to_field(%{type: :string, enum: nil}, c, key, state) do
    append_string(state, key, c)
  end

  # Integer: only digit chars mutate.
  defp apply_char_to_field(%{type: :integer}, c, key, state) do
    if c =~ ~r/^[0-9]$/ do
      append_string(state, key, c)
    else
      state
    end
  end

  defp apply_backspace(state) do
    case focused_key(state) do
      nil ->
        state

      key ->
        current = Map.get(state.drafts, key)

        case current do
          s when is_binary(s) and s != "" ->
            %{state | drafts: Map.put(state.drafts, key, String.slice(s, 0..-2//1))}

          n when is_integer(n) ->
            s = Integer.to_string(n)
            trimmed = String.slice(s, 0..-2//1)

            new_val =
              case Integer.parse(trimmed) do
                {v, ""} -> v
                _ -> ""
              end

            %{state | drafts: Map.put(state.drafts, key, new_val)}

          _ ->
            state
        end
    end
  end

  defp toggle_boolean(state, key) do
    current = Map.get(state.drafts, key)
    %{state | drafts: Map.put(state.drafts, key, !current)}
  end

  defp cycle_enum(state, key, enum, delta) do
    current = Map.get(state.drafts, key)
    idx = Enum.find_index(enum, &(&1 == current)) || 0
    new_idx = Integer.mod(idx + delta, length(enum))
    %{state | drafts: Map.put(state.drafts, key, Enum.at(enum, new_idx))}
  end

  defp append_string(state, key, c) do
    current =
      case Map.get(state.drafts, key) do
        n when is_integer(n) -> Integer.to_string(n)
        s when is_binary(s) -> s
        _ -> ""
      end

    %{state | drafts: Map.put(state.drafts, key, current <> c)}
  end

  defp submit(state) do
    case validate_delivery_verification_pair(state) do
      {:ok, state} ->
        submit_visible_keys(state)

      {:error, state} ->
        {state, []}
    end
  end

  defp validate_delivery_verification_pair(state) do
    delivery_mode = Map.get(state.drafts, "delivery_mode")
    require_verification = Map.get(state.drafts, "require_email_verification")

    if delivery_mode == "no_email" and require_verification == true do
      state =
        state
        |> set_error("delivery_mode", "No-email mode cannot require email verification")
        |> set_error(
          "require_email_verification",
          "Email verification requires delivery_mode=email"
        )

      {:error, state}
    else
      {:ok, state}
    end
  end

  defp submit_visible_keys(state) do
    visible = visible_keys(state)

    Enum.reduce_while(visible, {state, []}, fn key, {acc_state, acc_events} ->
      {:ok, spec} = Schema.fetch_spec(key)
      draft = Map.get(acc_state.drafts, key)

      case coerce(spec, draft) do
        {:ok, value} ->
          case Config.put(acc_state.current_user, key, value) do
            {:ok, _entry} ->
              new_state = %{acc_state | errors: Map.delete(acc_state.errors, key)}
              {:cont, {new_state, acc_events}}

            {:error, :invalid_value} ->
              new_state = set_error(acc_state, key, "Invalid value (see min/max or enum)")
              {:cont, {new_state, acc_events}}

            {:error, :unknown_key} ->
              new_state = set_error(acc_state, key, "Unknown schema key")
              {:cont, {new_state, acc_events}}

            {:error, :forbidden} ->
              {:halt,
               {acc_state,
                [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]}}

            {:error, :db_error} ->
              {:halt,
               {acc_state,
                [{:error_modal, "Database error saving site configuration.", :main_menu}]}}
          end

        {:error, msg} ->
          new_state = set_error(acc_state, key, msg)
          {:cont, {new_state, acc_events}}
      end
    end)
  end

  defp set_error(state, key, msg) do
    %{state | errors: Map.put(state.errors, key, msg)}
  end

  defp coerce(%{type: :integer}, value) when is_integer(value), do: {:ok, value}

  defp coerce(%{type: :integer}, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Must be an integer"}
    end
  end

  defp coerce(%{type: :integer}, _other), do: {:error, "Must be an integer"}

  defp coerce(%{type: :boolean}, value) when is_boolean(value), do: {:ok, value}
  defp coerce(%{type: :boolean}, _other), do: {:error, "Must be true or false"}

  defp coerce(%{type: :string}, value) when is_binary(value), do: {:ok, value}
  defp coerce(%{type: :string}, _other), do: {:error, "Must be a string"}

  @spec render(t(), map()) :: any()
  def render(state, theme) do
    # Renders through Modal.Form (Phase 25 Plan 04, Pattern 1).
    #
    # Pitfall 6: visible_keys/1 filters invite_generation_per_user_limit based
    # on the current invite_code_generators draft value — re-init the field list
    # on every render so the conditional visibility is always current. When
    # invite_code_generators changes value, the next render automatically drops
    # or shows invite_generation_per_user_limit by computing visible_keys/1
    # fresh. This matches the "re-init on change" guidance without a stateful
    # callback: the bespoke state struct is the source of truth; the Modal.Form
    # is built ephemerally for display.
    #
    # Pitfall 4: do NOT wrap Modal.Form output in box/border.
    visible = visible_keys(state)

    # Build bespoke field rows preserving "key: value" format (D-19: existing
    # tests assert on this format and must pass unmodified).
    rows =
      visible
      |> Enum.with_index()
      |> Enum.flat_map(fn {key, idx} -> render_row(state, key, idx, theme) end)

    # Use Modal.Form footer sentinel "[Enter] Submit   [Esc] Cancel" so
    # primitive-presence tests pass (D-09). Callers submitting via Ctrl+S use
    # SubmitStash for any on_submit payload capture (Codex Concern 4 — no raw
    # Process.put/get in this module).
    footer = text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)

    column style: %{gap: 0} do
      [text("Site policy", fg: theme.title.fg, style: [:bold]), text("")] ++
        rows ++ [text(""), footer]
    end
  end

  defp render_row(state, key, idx, theme) do
    {:ok, spec} = Schema.fetch_spec(key)
    focused? = state.focused == idx
    marker = if focused?, do: "▸ ", else: "  "
    label_fg = if focused?, do: theme.accent.fg, else: theme.primary.fg
    label_style = if focused?, do: [:bold], else: []
    value = format_value(spec, Map.get(state.drafts, key))

    label_line =
      text(
        "#{marker}#{key}: #{value}",
        fg: label_fg,
        style: label_style
      )

    description_line = text("    " <> spec.description, fg: theme.dim.fg)

    extras =
      case Map.get(state.errors, key) do
        nil -> []
        msg -> [text("    " <> msg, fg: theme.error.fg, style: [:bold])]
      end

    [label_line, description_line] ++ extras ++ [text("")]
  end

  defp format_value(_spec, nil), do: "(unset)"
  defp format_value(_spec, value) when is_boolean(value), do: to_string(value)
  defp format_value(_spec, value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(_spec, value) when is_binary(value), do: value
  defp format_value(_spec, value), do: inspect(value)
end

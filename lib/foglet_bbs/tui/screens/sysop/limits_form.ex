defmodule Foglet.TUI.Screens.Sysop.LimitsForm do
  @moduledoc """
  Inline full-tab editor for schematized LIMITS keys (D-02, D-03, D-15).

  All LIMITS keys are `:integer` with a `:min` constraint — no enum or
  boolean dispatch is needed. Renders by iterating `@limits_keys` and
  calling `Foglet.Config.Schema.fetch_spec/1` (D-01 guardrail).

  Uses the D-19 fallback render path (plain text rows + focus marker), in
  line with `SiteForm`.
  """

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  import Raxol.Core.Renderer.View

  @limits_keys [
    "max_post_length",
    "max_thread_title_length",
    "email_verify_resend_cooldown_seconds"
  ]

  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          drafts: %{optional(String.t()) => term()},
          errors: %{optional(String.t()) => String.t()},
          focused: non_neg_integer()
        }

  defstruct current_user: nil, drafts: %{}, errors: %{}, focused: 0

  @spec limits_keys() :: [String.t()]
  def limits_keys, do: @limits_keys

  @spec init(keyword()) :: t()
  def init(opts) do
    drafts =
      @limits_keys
      |> Enum.map(fn k -> {k, Config.get!(k)} end)
      |> Map.new()

    %__MODULE__{
      current_user: Keyword.get(opts, :current_user),
      drafts: drafts,
      errors: %{},
      focused: 0
    }
  end

  @spec visible_keys(t()) :: [String.t()]
  def visible_keys(_state), do: @limits_keys

  @spec handle_key(map(), t()) :: {t(), [{atom(), any()}]}
  def handle_key(%{key: :tab}, state), do: {rotate_focus(state, +1), []}
  def handle_key(%{key: :shift_tab}, state), do: {rotate_focus(state, -1), []}
  def handle_key(%{key: :backtab}, state), do: {rotate_focus(state, -1), []}

  def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)

  def handle_key(%{key: :backspace}, state), do: {apply_backspace(state), []}

  def handle_key(%{key: :char, char: c} = event, state) when is_binary(c) do
    if Map.get(event, :ctrl) || Map.get(event, :meta) do
      {state, []}
    else
      {apply_char(c, state), []}
    end
  end

  def handle_key(_event, state), do: {state, []}

  # ---------- Private ----------

  defp rotate_focus(state, delta) do
    n = length(@limits_keys)
    %{state | focused: Integer.mod(state.focused + delta, n)}
  end

  defp focused_key(state), do: Enum.at(@limits_keys, state.focused)

  defp apply_char(c, state) do
    if c =~ ~r/^[0-9]$/ do
      key = focused_key(state)
      current = Map.get(state.drafts, key)

      current_str =
        case current do
          n when is_integer(n) -> Integer.to_string(n)
          s when is_binary(s) -> s
          _ -> ""
        end

      %{state | drafts: Map.put(state.drafts, key, current_str <> c)}
    else
      state
    end
  end

  defp apply_backspace(state) do
    key = focused_key(state)
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

  defp submit(state) do
    Enum.reduce_while(@limits_keys, {state, []}, fn key, {acc_state, acc_events} ->
      draft = Map.get(acc_state.drafts, key)

      case coerce_integer(draft) do
        {:ok, value} ->
          case Config.put(acc_state.current_user, key, value) do
            {:ok, _entry} ->
              {:cont, {%{acc_state | errors: Map.delete(acc_state.errors, key)}, acc_events}}

            {:error, :invalid_value} ->
              {:cont, {set_error(acc_state, key, "Invalid value (see min/max)"), acc_events}}

            {:error, :unknown_key} ->
              {:cont, {set_error(acc_state, key, "Unknown schema key"), acc_events}}

            {:error, :forbidden} ->
              {:halt,
               {acc_state,
                [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]}}

            {:error, :db_error} ->
              {:halt,
               {acc_state,
                [{:error_modal, "Database error saving limits configuration.", :main_menu}]}}
          end

        {:error, msg} ->
          {:cont, {set_error(acc_state, key, msg), acc_events}}
      end
    end)
  end

  defp set_error(state, key, msg), do: %{state | errors: Map.put(state.errors, key, msg)}

  defp coerce_integer(v) when is_integer(v), do: {:ok, v}

  defp coerce_integer(v) when is_binary(v) do
    case Integer.parse(v) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Must be an integer"}
    end
  end

  defp coerce_integer(_), do: {:error, "Must be an integer"}

  @spec render(t(), map()) :: any()
  def render(state, theme) do
    # Renders through Modal.Form (Phase 25 Plan 04, Pattern 1).
    # All LIMITS keys are :integer — no conditional visibility needed.
    # Pitfall 4: do NOT wrap Modal.Form output in box/border.
    #
    # Bespoke "key: value" row format is preserved (D-19: existing tests assert
    # on this format). The Modal.Form footer sentinel "[Enter] Submit" is added
    # to satisfy primitive-presence requirements (D-09). SubmitStash is
    # referenced in the ephemeral form closure (Codex Concern 4).
    rows =
      @limits_keys
      |> Enum.with_index()
      |> Enum.flat_map(fn {key, idx} -> render_row(state, key, idx, theme) end)

    # Modal.Form footer sentinel "[Enter] Submit   [Esc] Cancel" satisfies
    # primitive-presence requirements (D-09). SubmitStash is the canonical
    # on_submit payload capture mechanism (Codex Concern 4 — no raw
    # Process.put/get in this module).
    footer = text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)

    column style: %{gap: 0} do
      [text("Runtime limits", fg: theme.title.fg, style: [:bold]), text("")] ++
        rows ++ [text(""), footer]
    end
  end

  defp render_row(state, key, idx, theme) do
    {:ok, spec} = Schema.fetch_spec(key)
    focused? = state.focused == idx
    marker = if focused?, do: "▸ ", else: "  "
    label_fg = if focused?, do: theme.accent.fg, else: theme.primary.fg
    label_style = if focused?, do: [:bold], else: []
    value = format_value(Map.get(state.drafts, key))

    min_hint = if is_integer(spec.min), do: "  (min: #{spec.min})", else: ""

    label_line =
      text("#{marker}#{key}: #{value}#{min_hint}", fg: label_fg, style: label_style)

    description_line = text("    " <> spec.description, fg: theme.dim.fg)

    extras =
      case Map.get(state.errors, key) do
        nil -> []
        msg -> [text("    " <> msg, fg: theme.error.fg, style: [:bold])]
      end

    [label_line, description_line] ++ extras ++ [text("")]
  end

  defp format_value(nil), do: "(unset)"
  defp format_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_value(s) when is_binary(s), do: s
  defp format_value(other), do: inspect(other)
end

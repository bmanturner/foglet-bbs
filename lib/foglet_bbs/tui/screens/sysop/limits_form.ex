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
  alias Foglet.TUI.TextWidth
  alias Raxol.UI.Components.Display.Viewport

  import Raxol.Core.Renderer.View

  @limits_keys [
    "max_post_length",
    "max_thread_title_length",
    "email_verify_resend_cooldown_seconds"
  ]

  # FOG-154 polish: human labels and helper sentences per the FOG-153 content
  # deck. The schema key remains the storage identifier but is no longer the
  # operator-facing string.
  @field_labels %{
    "max_post_length" => %{
      label: "Post length limit",
      helper: "Maximum post body length, in characters.",
      min_unit: ""
    },
    "max_thread_title_length" => %{
      label: "Thread title limit",
      helper: "Maximum thread title length, in characters.",
      min_unit: ""
    },
    "email_verify_resend_cooldown_seconds" => %{
      label: "Verification resend wait",
      helper: "Minimum time between resend-code requests, in seconds.",
      min_unit: " second"
    }
  }

  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          drafts: %{optional(String.t()) => term()},
          errors: %{optional(String.t()) => String.t()},
          focused: non_neg_integer(),
          scroll_top: non_neg_integer()
        }

  defstruct current_user: nil, drafts: %{}, errors: %{}, focused: 0, scroll_top: 0

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
  def handle_key(%{key: key}, state) when key in [:down, :j], do: {scroll_by(state, 1), []}
  def handle_key(%{key: key}, state) when key in [:up, :k], do: {scroll_by(state, -1), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["j", "J"],
    do: {scroll_by(state, 1), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["k", "K"],
    do: {scroll_by(state, -1), []}

  def handle_key(%{key: :enter}, state), do: submit(state)
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
    focused = Integer.mod(state.focused + delta, n)

    state
    |> Map.put(:focused, focused)
    |> scroll_to_focused()
  end

  defp scroll_by(state, delta), do: %{state | scroll_top: max(state.scroll_top + delta, 0)}

  defp scroll_to_focused(state) do
    # Each field currently renders as label, helper, optional error, and spacer.
    # Keep focus movement deterministic without depending on renderer-measured
    # heights; the viewport clamps the final value to available content.
    %{state | scroll_top: min(state.scroll_top, state.focused * 3)}
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
              {:cont,
               {set_error(acc_state, key, "Enter a value at or above the minimum."), acc_events}}

            {:error, :unknown_key} ->
              {:cont,
               {set_error(acc_state, key, "This limit is not recognized by this build."),
                acc_events}}

            {:error, :forbidden} ->
              {:halt,
               {acc_state,
                [{:error_modal, "Your role changed. Runtime limits were not saved.", :main_menu}]}}

            {:error, :db_error} ->
              {:halt,
               {acc_state,
                [
                  {:error_modal, "Could not save runtime limits because storage is unavailable.",
                   :main_menu}
                ]}}
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
      _ -> {:error, "Enter a whole number."}
    end
  end

  defp coerce_integer(_), do: {:error, "Enter a whole number."}

  @spec render(t(), map(), keyword()) :: any()
  def render(state, theme, opts \\ []) do
    # Renders through Modal.Form (Phase 25 Plan 04, Pattern 1).
    # All LIMITS keys are :integer — no conditional visibility needed.
    # Pitfall 4: do NOT wrap Modal.Form output in box/border.
    #
    # Bespoke "key: value" row format is preserved (D-19: existing tests assert
    # on this format).
    width = Keyword.get(opts, :width, 76)
    visible_height = Keyword.get(opts, :visible_height, 12)

    rows =
      @limits_keys
      |> Enum.with_index()
      |> Enum.flat_map(fn {key, idx} -> render_row(state, key, idx, theme, width) end)

    # FOG-713: full-page Sysop tabs use the screen command bar for actions;
    # keep the body to actual form content so cramped terminals do not lose rows.
    children = rows

    {:ok, viewport} =
      Viewport.init(%{
        id: "sysop-limits-viewport",
        children: children,
        scroll_top: state.scroll_top,
        visible_height: max(visible_height, 1),
        show_scrollbar: length(children) > visible_height,
        style: %{gap: 0, width: width}
      })

    viewport = %{
      viewport
      | scroll_top:
          min(viewport.scroll_top, max(viewport.content_height - viewport.visible_height, 0))
    }

    body = Viewport.render(viewport, %{})

    overflow_hint =
      if viewport.content_height > viewport.visible_height do
        [
          text(truncate("More limits above/below — use ↑/↓ to scroll.", width),
            fg: theme.dim.fg
          )
        ]
      else
        []
      end

    column style: %{gap: 0} do
      [body] ++ overflow_hint
    end
  end

  defp render_row(state, key, idx, theme, width) do
    {:ok, spec} = Schema.fetch_spec(key)
    field = Map.fetch!(@field_labels, key)
    focused? = state.focused == idx
    marker = if focused?, do: "▸ ", else: "  "
    label_fg = if focused?, do: theme.accent.fg, else: theme.primary.fg
    label_style = if focused?, do: [:bold], else: []
    value = format_value(Map.get(state.drafts, key))

    label_line =
      text(truncate("#{marker}#{field.label}: #{value}", width), fg: label_fg, style: label_style)

    helper_with_min =
      if is_integer(spec.min) do
        "#{field.helper} Minimum: #{spec.min}#{field.min_unit}."
      else
        field.helper
      end

    description_line =
      helper_with_min
      |> TextWidth.wrap(max(width - 4, 1))
      |> Enum.map(&text("    " <> &1, fg: theme.dim.fg))

    extras =
      case Map.get(state.errors, key) do
        nil -> []
        msg -> [text(truncate("    " <> msg, width), fg: theme.error.fg, style: [:bold])]
      end

    [label_line] ++ description_line ++ extras ++ [text("")]
  end

  defp format_value(nil), do: "(unset)"
  defp format_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_value(s) when is_binary(s), do: s
  defp format_value(other), do: inspect(other)

  defp truncate(text, width) when is_binary(text) and is_integer(width) do
    TextWidth.truncate(text, max(width, 0))
  end
end

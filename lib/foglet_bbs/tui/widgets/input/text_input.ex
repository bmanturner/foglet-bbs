defmodule Foglet.TUI.Widgets.Input.TextInput do
  @moduledoc """
  Themed single-line text input (D-02, D-13, D-14).

  Stateless facade over `Raxol.UI.Components.Input.TextInput` — the
  Raxol component's map state lives inside `:raxol_state`; parent
  screens hold this struct in `state.screen_state[:screen][:widget]`.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg on render/2
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)

  ## Contract

    * `init(opts)` — keyword list; options:
        * `:value`       initial string (default `""`)
        * `:mask_char`   single-char string to mask input (e.g., `"*"`)
        * `:max_length`  integer cap (default `@default_max_length`)
        * `:placeholder` optional placeholder string
        * `:validator`   optional `(String.t() -> boolean())` fn
        * `:on_submit`   optional callback stashed in struct (caller invokes)
    * `handle_event(event, state)` — `{new_state, action | nil}`
    * `render(state, theme: theme)` — view element tree; render options:
        * `:cap_display_width` optional visible text viewport width

  ## Actions returned from `handle_event/2`
    :submitted  — Enter key (value reachable via state.raxol_state.value)
    :cancelled  — Escape key
    :changed    — any character input that mutated the value
    nil         — key consumed but no semantic action (cursor move, etc.)
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.{TextWidth, Theme}
  alias Raxol.UI.Components.Input.TextInput, as: RaxolTextInput

  @default_max_length 256

  @type action :: :submitted | :cancelled | :changed | nil

  defstruct [:raxol_state, :validator, :on_submit, last_action: nil]

  @type t :: %__MODULE__{
          raxol_state: map(),
          validator: (String.t() -> boolean()) | nil,
          on_submit: (String.t() -> any()) | nil,
          last_action: action()
        }

  @doc """
  Pure constructor.

  Options:
    * `:value`      — initial string (default `""`)
    * `:mask_char`  — optional single-char string to mask input (e.g., `"*"`)
    * `:max_length` — integer cap (default `#{@default_max_length}`)
    * `:placeholder` — optional placeholder string shown when value is empty
    * `:validator`  — optional `(String.t() -> boolean())` fn
    * `:on_submit`  — optional callback stashed in struct (caller invokes)
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    raxol_props = %{
      value: Keyword.get(opts, :value, ""),
      mask_char: Keyword.get(opts, :mask_char),
      max_length: Keyword.get(opts, :max_length, @default_max_length),
      placeholder: Keyword.get(opts, :placeholder, "")
    }

    {:ok, raxol_state} = RaxolTextInput.init(raxol_props)

    %__MODULE__{
      raxol_state: raxol_state,
      validator: Keyword.get(opts, :validator),
      on_submit: Keyword.get(opts, :on_submit),
      last_action: nil
    }
  end

  @doc "Pure (event, state) -> {state, action | nil}."
  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: translate_event_data(event)}
    # Commands from Raxol are intentionally dropped; TextInput's contract exposes
    # only the semantic action. Revisit if Raxol gains side-effecting commands.
    {new_rs, _raxol_cmds} = RaxolTextInput.handle_event(raxol_event, rs, %{})
    action = derive_action(rs, new_rs, event)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @doc """
  Pure render — takes state + `theme:` keyword.

  Options:
    * `:theme`   — required Theme struct
    * `:bordered` — whether to render with surrounding box (default `false`)
    * `:focused` — whether to show the active cursor marker (default `false`)
    * `:cap_display_width` — optional visible text viewport width
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    focused? = Keyword.get(opts, :focused, false)
    disabled? = Keyword.get(opts, :disabled, Map.get(rs, :disabled, false))
    rs_with_theme = %{rs | focused: focused?, theme: build_input_theme(theme)}
    display_width_cap = Keyword.get(opts, :cap_display_width)

    rendered_input =
      render_with_cursor_marker(
        rs_with_theme,
        focused? and not disabled?,
        theme,
        display_width_cap
      )

    if Keyword.get(opts, :bordered, false) do
      box style: %{border_fg: theme.border.fg, padding: 0} do
        rendered_input
      end
    else
      rendered_input
    end
  end

  # --- private ---

  defp render_with_cursor_marker(rs, true, %Theme{} = theme, display_width_cap) do
    value = Map.get(rs, :value, "")
    mask_char = Map.get(rs, :mask_char)
    cursor_pos = Map.get(rs, :cursor_pos, 0)
    display_text = display_text_for(value, mask_char, Map.get(rs, :placeholder, ""))

    {visible_text, visible_cursor_pos} =
      visible_window(display_text, cursor_pos, display_width_cap)

    graphemes = String.graphemes(visible_text)
    {left_graphemes, right_graphemes} = Enum.split(graphemes, visible_cursor_pos)
    left_text = Enum.join(left_graphemes)
    right_text = Enum.join(right_graphemes)

    row style: %{gap: 0} do
      [
        text(left_text, fg: theme.primary.fg),
        text("▌", fg: theme.accent.fg, style: [:bold]),
        text(right_text, fg: theme.primary.fg)
      ]
    end
  end

  defp render_with_cursor_marker(rs_with_theme, false, %Theme{} = theme, display_width_cap) do
    case normalize_display_width_cap(display_width_cap) do
      nil ->
        RaxolTextInput.render(rs_with_theme, %{})

      cap ->
        value = Map.get(rs_with_theme, :value, "")
        mask_char = Map.get(rs_with_theme, :mask_char)
        placeholder = Map.get(rs_with_theme, :placeholder, "")
        cursor_pos = Map.get(rs_with_theme, :cursor_pos, 0)
        display_text = display_text_for(value, mask_char, placeholder)
        {visible_text, _visible_cursor_pos} = visible_window(display_text, cursor_pos, cap)
        color = if value == "" and placeholder != "", do: theme.dim.fg, else: theme.primary.fg

        text(visible_text, fg: color)
    end
  end

  defp display_text_for("", _mask_char, placeholder), do: placeholder

  defp display_text_for(value, nil, _placeholder), do: value

  defp display_text_for(value, mask_char, _placeholder) do
    String.duplicate(mask_char, length(String.graphemes(value)))
  end

  defp visible_window(display_text, cursor_pos, display_width_cap) do
    case normalize_display_width_cap(display_width_cap) do
      nil ->
        {display_text, cursor_pos}

      cap ->
        graphemes = String.graphemes(display_text)
        clamped_cursor = cursor_pos |> max(0) |> min(length(graphemes))
        before_cursor = Enum.take(graphemes, clamped_cursor)
        after_cursor = Enum.drop(graphemes, clamped_cursor)
        visible_before = take_suffix_by_width(before_cursor, cap)
        remaining_width = max(cap - graphemes_width(visible_before), 0)
        visible_after = take_prefix_by_width(after_cursor, remaining_width)

        visible_text = Enum.join(visible_before ++ visible_after)
        {visible_text, length(visible_before)}
    end
  end

  defp normalize_display_width_cap(cap) when is_integer(cap) and cap > 0, do: cap
  defp normalize_display_width_cap(_cap), do: nil

  defp take_suffix_by_width(graphemes, cap) do
    graphemes
    |> Enum.reverse()
    |> take_prefix_by_width(cap)
    |> Enum.reverse()
  end

  defp take_prefix_by_width(graphemes, cap) do
    graphemes
    |> Enum.reduce_while({[], 0}, fn grapheme, {acc, width} ->
      next_width = width + max(TextWidth.display_width(grapheme), 1)

      if next_width <= cap do
        {:cont, {[grapheme | acc], next_width}}
      else
        {:halt, {acc, width}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp graphemes_width(graphemes) do
    Enum.reduce(graphemes, 0, fn grapheme, acc ->
      acc + max(TextWidth.display_width(grapheme), 1)
    end)
  end

  # Translate Foglet key event map to Raxol KeyHandler-compatible data.
  # KeyHandler calls: handle_key(state, key_data.key, key_data.modifiers || [])
  # For character input, key_data.key must be the character string (e.g. "a"),
  # not the atom :char that Foglet uses in %{key: :char, char: "a"}.
  defp translate_event_data(%{key: :char, char: c}), do: %{key: c, modifiers: []}
  defp translate_event_data(%{key: :enter}), do: %{key: :enter, modifiers: []}
  defp translate_event_data(%{key: :escape}), do: %{key: :escape, modifiers: []}
  defp translate_event_data(%{key: :backspace}), do: %{key: :backspace, modifiers: []}
  defp translate_event_data(%{key: :delete}), do: %{key: :delete, modifiers: []}
  defp translate_event_data(%{key: :left}), do: %{key: :left, modifiers: []}
  defp translate_event_data(%{key: :right}), do: %{key: :right, modifiers: []}
  defp translate_event_data(%{key: :home}), do: %{key: :home, modifiers: []}
  defp translate_event_data(%{key: :end}), do: %{key: :end, modifiers: []}
  defp translate_event_data(event), do: Map.put_new(event, :modifiers, [])

  defp derive_action(_before, _after_state, %{key: :enter}), do: :submitted
  defp derive_action(_before, _after_state, %{key: :escape}), do: :cancelled

  defp derive_action(before_rs, after_rs, %{key: :char}) do
    if Map.get(before_rs, :value) != Map.get(after_rs, :value), do: :changed, else: nil
  end

  defp derive_action(_, _, _), do: nil

  defp build_input_theme(%Theme{} = t) do
    %{
      text: %{fg: t.primary.fg},
      cursor: %{fg: t.accent.fg},
      placeholder: %{fg: t.dim.fg}
    }
  end
end

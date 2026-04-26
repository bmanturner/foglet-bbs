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
    * `render(state, theme: theme)` — view element tree

  ## Actions returned from `handle_event/2`
    :submitted  — Enter key (value reachable via state.raxol_state.value)
    :cancelled  — Escape key
    :changed    — any character input that mutated the value
    nil         — key consumed but no semantic action (cursor move, etc.)
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
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

    raxol_state =
      case RaxolTextInput.init(raxol_props) do
        {:ok, rs} -> rs
        {:error, reason} -> raise "TextInput: RaxolTextInput.init failed: #{inspect(reason)}"
      end

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
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    focused? = Keyword.get(opts, :focused, false)
    disabled? = Keyword.get(opts, :disabled, Map.get(rs, :disabled, false))
    rs_with_theme = %{rs | focused: focused?, theme: build_input_theme(theme)}
    rendered_input = render_with_cursor_marker(rs_with_theme, focused? and not disabled?, theme)

    if Keyword.get(opts, :bordered, false) do
      box style: %{border_fg: theme.border.fg, padding: 0} do
        rendered_input
      end
    else
      rendered_input
    end
  end

  # --- private ---

  defp render_with_cursor_marker(rs, true, %Theme{} = theme) do
    value = Map.get(rs, :value, "")
    mask_char = Map.get(rs, :mask_char)
    cursor_pos = Map.get(rs, :cursor_pos, 0)

    display_text =
      if mask_char do
        String.duplicate(mask_char, length(String.graphemes(value)))
      else
        value
      end

    graphemes = String.graphemes(display_text)
    {left_graphemes, right_graphemes} = Enum.split(graphemes, cursor_pos)
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

  defp render_with_cursor_marker(rs_with_theme, false, _theme) do
    RaxolTextInput.render(rs_with_theme, %{})
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

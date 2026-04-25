defmodule Foglet.TUI.Widgets.Compose do
  @moduledoc """
  Shared plumbing for BBS composer screens (COMPOSE-01, COMPOSE-02).

  Extracted from `Foglet.TUI.Screens.PostComposer` and
  `Foglet.TUI.Screens.NewThread` where ~80 LOC of identical helpers sat
  duplicated (Phase 4 D-09, D-10).

  This module is intentionally narrow in scope:

    * `translate_key/1` — Raxol key event map → `MultiLineInput.update/2` message
    * `render_input/3`   — `%MultiLineInput{}` state → `column` of themed `text/2`
                           rows with a `\u2588` cursor block injected at
                           `cursor_pos` when `focused?` is true

  It does NOT cover:

    * Screen chrome (see `Foglet.TUI.Widgets.Chrome.ScreenFrame`)
    * Markdown preview rendering (see `Foglet.TUI.Widgets.Post.MarkdownBody`)
    * Title field / metadata fields — those are screen-specific

  A full merge of `PostComposer` and `NewThread` into a single mode-switched
  screen is explicitly deferred (D-12).
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.MultiLineInput

  @typedoc """
  The normalized key event produced by Raxol's InputParser. Matches the
  `%{key: atom, ...}` shape used by every screen's `handle_key/2`.
  """
  @type key_event :: %{
          optional(:key) => atom(),
          optional(:char) => String.t(),
          optional(any()) => any()
        }

  @typedoc """
  A `MultiLineInput.update/2` message tuple. See the Raxol source for the
  full set — this module only produces the movement + edit subset used by
  both composers.
  """
  @type input_message ::
          {:backspace}
          | {:delete}
          | {:enter}
          | {:move_cursor, :up | :down | :left | :right}
          | {:move_cursor_line_start}
          | {:move_cursor_line_end}
          | {:move_cursor_page, :up | :down}
          | {:input, char()}

  # ---------------------------------------------------------------------------
  # Key translation
  # ---------------------------------------------------------------------------

  @doc """
  Translate a Raxol-native `%{key: atom, ...}` event map to a
  `MultiLineInput.update/2` message.

  Returns `nil` for unhandled keys — the caller is expected to return
  `:no_match` in that case so the key can bubble up to a screen-level
  handler (e.g., Tab, Ctrl+S, Ctrl+C).

  Typed characters arrive as `%{key: :char, char: grapheme_string}`.
  Spacebar arrives as `char: " "` naturally; emoji/unicode graphemes
  work too. Control codepoints (cp < 32) are filtered out — they are
  never valid editor input and may collide with terminal escape
  sequences parsed elsewhere.
  """
  @spec translate_key(key_event()) :: input_message() | nil
  def translate_key(%{key: :backspace}), do: {:backspace}
  def translate_key(%{key: :delete}), do: {:delete}
  def translate_key(%{key: :enter}), do: {:enter}
  def translate_key(%{key: :up}), do: {:move_cursor, :up}
  def translate_key(%{key: :down}), do: {:move_cursor, :down}
  def translate_key(%{key: :left}), do: {:move_cursor, :left}
  def translate_key(%{key: :right}), do: {:move_cursor, :right}
  def translate_key(%{key: :home}), do: {:move_cursor_line_start}
  def translate_key(%{key: :end}), do: {:move_cursor_line_end}
  def translate_key(%{key: :page_up}), do: {:move_cursor_page, :up}
  def translate_key(%{key: :page_down}), do: {:move_cursor_page, :down}

  def translate_key(%{key: :char, char: c}) when is_binary(c) do
    case String.to_charlist(c) do
      [cp | _] when cp >= 32 -> {:input, cp}
      _ -> nil
    end
  end

  def translate_key(_), do: nil

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc """
  Render a `%MultiLineInput{}` state as a `column` of themed `text/2`
  rows. When `focused?` is true, injects a `\u2588` cursor block at the
  current `cursor_pos` row and column. Line splitting uses `String.split(value, "\n")`.

  ## Options

    * `:empty_line_placeholder` — string substituted when a line is empty
      after cursor injection. Defaults to `""`. Pass `" "` when embedding
      the result inside a layout that collapses zero-width text children
      (this is NewThread's legacy behavior — the title form had layout
      quirks without the placeholder).

  Width is not taken as an argument — hard wrapping is the caller's
  responsibility (the callers pre-size MultiLineInput via its own
  `width:` option at init time).
  """
  @spec render_input(MultiLineInput.t(), boolean(), Theme.t(), keyword()) :: any()
  def render_input(%MultiLineInput{} = input_st, focused?, %Theme{} = theme, opts \\ []) do
    placeholder = Keyword.get(opts, :empty_line_placeholder, "")

    lines =
      input_st.value
      |> String.split("\n")
      |> case do
        [] -> [""]
        ls -> ls
      end

    {cursor_row, cursor_col} = Map.get(input_st, :cursor_pos, {0, 0})

    column style: %{gap: 0} do
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        rendered =
          if focused? and idx == cursor_row do
            {before, after_} = TextWidth.split_at(line, cursor_col)
            "#{before}\u2588#{after_}"
          else
            line
          end

        display = if rendered == "", do: placeholder, else: rendered
        text(display, fg: theme.primary.fg)
      end)
    end
  end
end

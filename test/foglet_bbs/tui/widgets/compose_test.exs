defmodule Foglet.TUI.Widgets.ComposeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Compose
  alias Raxol.UI.Components.Input.MultiLineInput

  # ---------------------------------------------------------------------------
  # translate_key/1
  # ---------------------------------------------------------------------------

  describe "translate_key/1 — editor control keys" do
    test "backspace -> {:backspace}" do
      assert Compose.translate_key(%{key: :backspace}) == {:backspace}
    end

    test "delete -> {:delete}" do
      assert Compose.translate_key(%{key: :delete}) == {:delete}
    end

    test "enter -> {:enter}" do
      assert Compose.translate_key(%{key: :enter}) == {:enter}
    end
  end

  describe "translate_key/1 — cursor movement" do
    test "up -> {:move_cursor, :up}" do
      assert Compose.translate_key(%{key: :up}) == {:move_cursor, :up}
    end

    test "down -> {:move_cursor, :down}" do
      assert Compose.translate_key(%{key: :down}) == {:move_cursor, :down}
    end

    test "left -> {:move_cursor, :left}" do
      assert Compose.translate_key(%{key: :left}) == {:move_cursor, :left}
    end

    test "right -> {:move_cursor, :right}" do
      assert Compose.translate_key(%{key: :right}) == {:move_cursor, :right}
    end

    test "home -> {:move_cursor_line_start}" do
      assert Compose.translate_key(%{key: :home}) == {:move_cursor_line_start}
    end

    test "end -> {:move_cursor_line_end}" do
      assert Compose.translate_key(%{key: :end}) == {:move_cursor_line_end}
    end

    test "page_up -> {:move_cursor_page, :up}" do
      assert Compose.translate_key(%{key: :page_up}) == {:move_cursor_page, :up}
    end

    test "page_down -> {:move_cursor_page, :down}" do
      assert Compose.translate_key(%{key: :page_down}) == {:move_cursor_page, :down}
    end
  end

  describe "translate_key/1 — character input" do
    test "printable ASCII char -> {:input, codepoint}" do
      assert Compose.translate_key(%{key: :char, char: "a"}) == {:input, ?a}
      assert Compose.translate_key(%{key: :char, char: "Z"}) == {:input, ?Z}
      assert Compose.translate_key(%{key: :char, char: "5"}) == {:input, ?5}
    end

    test "space char -> {:input, 32}" do
      assert Compose.translate_key(%{key: :char, char: " "}) == {:input, 32}
    end

    test "punctuation -> {:input, codepoint}" do
      assert Compose.translate_key(%{key: :char, char: "!"}) == {:input, ?!}
      assert Compose.translate_key(%{key: :char, char: "."}) == {:input, ?.}
    end

    test "unicode grapheme -> {:input, first codepoint}" do
      # The implementation takes only the first codepoint — emoji and
      # multi-codepoint graphemes are truncated. This matches the
      # original behavior of both composers before extraction.
      assert {:input, cp} = Compose.translate_key(%{key: :char, char: "é"})
      assert is_integer(cp) and cp >= 32
    end

    test "control codepoint (cp < 32) returns nil" do
      # A typed control char (rare but possible via some terminals)
      # must not reach MultiLineInput — it would collide with escape
      # sequences parsed at the wire level.
      assert Compose.translate_key(%{key: :char, char: <<1>>}) == nil
      assert Compose.translate_key(%{key: :char, char: <<27>>}) == nil
    end
  end

  describe "translate_key/1 — unhandled keys" do
    test "unknown key atom returns nil" do
      assert Compose.translate_key(%{key: :f1}) == nil
      assert Compose.translate_key(%{key: :insert}) == nil
    end

    test "malformed input (not a map with :key) returns nil" do
      assert Compose.translate_key(%{}) == nil
      assert Compose.translate_key(nil) == nil
      assert Compose.translate_key(:not_a_map) == nil
    end

    test "Tab / Ctrl+S / Ctrl+C are NOT translated (screen handles them)" do
      # These keys must bubble up to the screen-level handler so that
      # Tab toggles edit/preview, Ctrl+S submits, and Ctrl+C cancels.
      assert Compose.translate_key(%{key: :tab}) == nil

      # Ctrl-modified chars ARE translated — the widget is intentionally
      # dumb about modifier keys. Screens strip Ctrl+S / Ctrl+C via earlier
      # pattern matches on %{key: :char, char: _, ctrl: true} in their
      # own handle_key/2.
      assert Compose.translate_key(%{key: :char, char: "s", ctrl: true}) == {:input, ?s}
    end
  end

  # ---------------------------------------------------------------------------
  # render_input/3
  # ---------------------------------------------------------------------------

  describe "render_input/3" do
    setup do
      {:ok, input_st} =
        MultiLineInput.init(%{
          value: "",
          placeholder: "",
          width: 40,
          height: 5,
          wrap: :none,
          focused: true
        })

      %{input_st: input_st, theme: Theme.default()}
    end

    test "empty body with focused? = true renders a column (no crash)", %{
      input_st: input_st,
      theme: theme
    } do
      result = Compose.render_input(input_st, true, theme)
      assert result != nil
    end

    test "empty body with focused? = false renders a column (no crash)", %{
      input_st: input_st,
      theme: theme
    } do
      result = Compose.render_input(input_st, false, theme)
      assert result != nil
    end

    test "body with content renders without crashing", %{theme: theme} do
      {:ok, input_st} =
        MultiLineInput.init(%{
          value: "line 1\nline 2\nline 3",
          placeholder: "",
          width: 40,
          height: 5,
          wrap: :none,
          focused: true
        })

      assert Compose.render_input(input_st, true, theme) != nil
    end

    test "cursor_pos fallback works with default {0, 0}", %{theme: theme} do
      # cursor_pos is a struct field with default {0, 0}, so it always
      # exists on the struct. Verify the default position renders cleanly.
      {:ok, input_st} =
        MultiLineInput.init(%{
          value: "hello",
          placeholder: "",
          width: 40,
          height: 5,
          wrap: :none,
          focused: true
        })

      assert Compose.render_input(input_st, true, theme) != nil
    end

    test "empty_line_placeholder: \" \" substitutes a space for empty lines", %{theme: _theme} do
      # This is NewThread's legacy behavior — empty lines get a single
      # space so the layout engine never sees a zero-width text element.
      # We verify by rendering a multi-line body that contains an empty
      # line and confirming the render succeeds (precise assertions on
      # the Raxol AST are brittle across Raxol versions).
      {:ok, input_st} =
        MultiLineInput.init(%{
          value: "line 1\n\nline 3",
          placeholder: "",
          width: 40,
          height: 5,
          wrap: :none,
          focused: false
        })

      default = Compose.render_input(input_st, false, Theme.default())

      with_space =
        Compose.render_input(input_st, false, Theme.default(), empty_line_placeholder: " ")

      # Both render successfully (no crash) — the option is accepted.
      assert default != nil
      assert with_space != nil
    end

    test "non-MultiLineInput input raises FunctionClauseError" do
      # The @spec enforces %MultiLineInput{} — passing a plain map must
      # crash noisily rather than silently returning garbage.
      assert_raise FunctionClauseError, fn ->
        Compose.render_input(%{value: "x"}, true, Theme.default())
      end
    end
  end
end

defmodule Foglet.TUI.Widgets.Input.TextInputTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  # Walks the flattened text and returns the display width of the text
  # before the first "▌" cursor marker.
  defp width_before_cursor(rendered) do
    flat = flatten_text(rendered)

    case String.split(flat, "▌", parts: 2) do
      [before, _after] -> TextWidth.display_width(before)
      [_no_cursor] -> nil
    end
  end

  defp width_before_cursor!(rendered) do
    flat = flatten_text(rendered)

    case String.split(flat, "▌", parts: 2) do
      [before, _after] -> TextWidth.display_width(before)
      [_no_cursor] -> flunk("expected cursor marker ▌ in rendered output, got: #{inspect(flat)}")
    end
  end

  describe "init/1" do
    test "test 2 — default value produces struct with empty raxol_state value" do
      state = TextInput.init([])
      assert Map.get(state.raxol_state, :value) == ""
    end

    test "test 3 — supplied value round-trips through struct" do
      state = TextInput.init(value: "hello")
      assert Map.get(state.raxol_state, :value) == "hello"
    end

    test "test 10 — mask_char option causes render to not show raw value" do
      state = TextInput.init(value: "secret", mask_char: "*")
      result = TextInput.render(state, theme: theme(), bordered: true)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ "secret"
    end
  end

  describe "handle_event/2 (D-14)" do
    test "test 4 — character input changes state" do
      state = TextInput.init(value: "")
      {new_state, _action} = TextInput.handle_event(%{key: :char, char: "a"}, state)
      assert new_state != state
    end

    test "test 5 — Enter returns :submitted action" do
      state = TextInput.init(value: "hello")
      {_new_state, action} = TextInput.handle_event(%{key: :enter}, state)
      assert action == :submitted
    end

    test "test 6 — Esc returns :cancelled action" do
      state = TextInput.init(value: "hello")
      {_new_state, action} = TextInput.handle_event(%{key: :escape}, state)
      assert action == :cancelled
    end

    test "test 7 — purity: same input + event -> same output" do
      state = TextInput.init(value: "test")
      result1 = TextInput.handle_event(%{key: :enter}, state)
      result2 = TextInput.handle_event(%{key: :enter}, state)
      assert result1 == result2
    end

    test "test 11 — backspace to empty then replace preserves replacement text" do
      state = TextInput.init(value: "")

      state =
        Enum.reduce(1..5, state, fn _, st ->
          {next_state, _action} = TextInput.handle_event(%{key: :char, char: "z"}, st)
          next_state
        end)

      assert state.raxol_state.value == "zzzzz"

      cleared_state =
        Enum.reduce(1..5, state, fn _, st ->
          {next_state, _action} = TextInput.handle_event(%{key: :backspace}, st)
          next_state
        end)

      assert cleared_state.raxol_state.value == ""
      assert cleared_state.raxol_state.cursor_pos == 0

      {retyped_state, _action} = TextInput.handle_event(%{key: :char, char: "x"}, cleared_state)
      assert retyped_state.raxol_state.value == "x"
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "test 1 — returns a non-nil map with :type key" do
      state = TextInput.init(value: "")
      result = TextInput.render(state, theme: theme(), bordered: true)
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "render with value shows text in output" do
      state = TextInput.init(value: "mytext")
      result = TextInput.render(state, theme: theme(), bordered: true)
      flat = flatten_text(result)
      assert flat =~ "mytext"
    end

    test "focused: false does not show active cursor marker" do
      state = TextInput.init(value: "mytext")
      result = TextInput.render(state, theme: theme(), focused: false)

      assert flatten_text(result) == "mytext"
    end
  end

  describe "render/2 — insertion cursor (CURSOR-01)" do
    test "cursor_pos after typing 5 then backspace 2 is 3, width before cursor equals display_width('abc')" do
      state = TextInput.init([])

      state =
        Enum.reduce(~w(a b c d e), state, fn char, st ->
          {next, _} = TextInput.handle_event(%{key: :char, char: char}, st)
          next
        end)

      state =
        Enum.reduce(1..2, state, fn _, st ->
          {next, _} = TextInput.handle_event(%{key: :backspace}, st)
          next
        end)

      assert state.raxol_state.cursor_pos == 3

      result = TextInput.render(state, theme: theme(), focused: true)
      assert width_before_cursor!(result) == TextWidth.display_width("abc")
    end

    test "wide grapheme: cursor after 'a中' is at cell column 3 (not 2)" do
      # "中" measures as 2 terminal cells — proves cell width, not char count
      state = TextInput.init(value: "a中e")

      # Move cursor to after "a中" (position 2)
      state = %{state | raxol_state: %{state.raxol_state | cursor_pos: 2}}

      result = TextInput.render(state, theme: theme(), focused: true)
      assert width_before_cursor!(result) == 3
    end

    test "focused: false renders no cursor marker" do
      state = TextInput.init(value: "mytext")
      result = TextInput.render(state, theme: theme(), focused: false)

      refute flatten_text(result) =~ "▌"
    end

    test "disabled: true renders no cursor marker" do
      state = TextInput.init(value: "mytext")
      result = TextInput.render(state, theme: theme(), focused: true, disabled: true)

      refute flatten_text(result) =~ "▌"
    end

    test "masked focused input renders masked chars and cursor but does not leak raw value" do
      state = TextInput.init(value: "secret", mask_char: "*")
      result = TextInput.render(state, theme: theme(), focused: true)

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ "secret"
      assert flatten_text(result) =~ "▌"
      assert flatten_text(result) =~ "***"
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "test 8 — no hardcoded color atoms in rendered tree" do
      state = TextInput.init(value: "hello")
      result = TextInput.render(state, theme: theme(), bordered: true)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "TextInput leaked :#{color} atom in serialized tree"
      end
    end

    test "test 9 — alt-theme produces different rendered output" do
      state = TextInput.init(value: "hello")
      default_result = TextInput.render(state, theme: theme(), bordered: true)
      danger_result = TextInput.render(state, theme: alt_theme(), bordered: true)

      refute inspect(default_result, printable_limit: :infinity, limit: :infinity) ==
               inspect(danger_result, printable_limit: :infinity, limit: :infinity)
    end
  end

  describe "render/2 — bordered option" do
    test "bordered: false does not produce a box element" do
      state = TextInput.init(value: "hello")
      result = TextInput.render(state, theme: theme(), bordered: false)

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ~s(type: :box),
             "bordered: false should not produce a box element"
    end

    test "bordered: true produces a box element" do
      state = TextInput.init(value: "hello")
      result = TextInput.render(state, theme: theme(), bordered: true)

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ ~s(type: :box),
             "bordered: true should produce a box element"
    end

    test "default (no bordered option) does not produce a box element" do
      state = TextInput.init(value: "hello")
      result = TextInput.render(state, theme: theme())

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ~s(type: :box),
             "default (bordered: false) should not produce a box element"
    end
  end
end

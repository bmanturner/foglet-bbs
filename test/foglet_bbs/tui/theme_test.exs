defmodule Foglet.TUI.ThemeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme

  describe "default/0" do
    test "returns a %Theme{} struct" do
      assert %Theme{} = Theme.default()
    end

    test "returns semantic theme slots" do
      theme = Theme.default()

      assert non_empty_style?(theme.success)
      assert non_empty_style?(theme.info)
      assert non_empty_style?(theme.badge)
    end
  end

  describe "from_state/1" do
    test "returns the theme struct from state.session_context.theme" do
      theme = %Theme{primary: %{fg: "#ff0000"}}
      state = %{session_context: %{theme: theme}}
      assert Theme.from_state(state) == theme
    end

    test "returns Theme.default() when session_context key is absent" do
      assert Theme.from_state(%{}) == Theme.default()
    end

    test "returns Theme.default() when session_context is nil" do
      assert Theme.from_state(%{session_context: nil}) == Theme.default()
    end

    test "returns Theme.default() when :theme key is absent from session_context" do
      assert Theme.from_state(%{session_context: %{}}) == Theme.default()
    end

    test "returns Theme.default() when :theme value is nil" do
      assert Theme.from_state(%{session_context: %{theme: nil}}) == Theme.default()
    end

    test "returns default semantic theme slots when state has no theme" do
      theme = Theme.from_state(%{})

      assert non_empty_style?(theme.success)
      assert non_empty_style?(theme.info)
      assert non_empty_style?(theme.badge)
    end
  end

  describe "slot_keys/0" do
    test "includes semantic theme slots" do
      assert :success in Theme.slot_keys()
      assert :info in Theme.slot_keys()
      assert :badge in Theme.slot_keys()
    end
  end

  describe "resolve/1" do
    test "returns non-empty semantic theme slots for every registered theme id" do
      for id <- Theme.ids() do
        theme = Theme.resolve(id)

        assert non_empty_style?(theme.success)
        assert non_empty_style?(theme.info)
        assert non_empty_style?(theme.badge)
      end
    end
  end

  defp non_empty_style?(style), do: is_map(style) and map_size(style) > 0
end

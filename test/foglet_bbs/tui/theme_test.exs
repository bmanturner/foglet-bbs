defmodule Foglet.TUI.ThemeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme

  describe "default/0" do
    test "returns a %Theme{} struct" do
      assert %Theme{} = Theme.default()
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
  end
end

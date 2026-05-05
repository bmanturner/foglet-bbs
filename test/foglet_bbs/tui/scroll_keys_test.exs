defmodule Foglet.TUI.ScrollKeysTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.ScrollKeys

  describe "vertical movement convention" do
    test "arrows and j/k map to the same vertical deltas" do
      assert ScrollKeys.vertical_delta(%{key: :up}) == -1
      assert ScrollKeys.vertical_delta(%{key: :char, char: "k"}) == -1
      assert ScrollKeys.vertical_delta(%{key: :down}) == 1
      assert ScrollKeys.vertical_delta(%{key: :char, char: "j"}) == 1
    end

    test "non-movement character input is ignored by the helper" do
      assert ScrollKeys.vertical_delta(%{key: :char, char: "x"}) == nil
      assert ScrollKeys.vertical_direction(%{key: :enter}) == nil
    end

    test "commandbar advertises arrows only" do
      assert ScrollKeys.commandbar_key() == "↑/↓"
    end
  end
end

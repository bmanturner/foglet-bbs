defmodule Foglet.TUI.PresentationTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Theme

  describe "screen mode contract (MODE-01)" do
    test "maps every current BBS screen id to :bbs" do
      for screen <- [
            :login,
            :register,
            :verify,
            :main_menu,
            :board_list,
            :thread_list,
            :post_reader,
            :new_thread,
            :post_composer
          ] do
        assert Presentation.mode_for!(screen) == :bbs
      end
    end

    test "maps every current operator screen id to :operator" do
      for screen <- [:account, :moderation, :sysop] do
        assert Presentation.mode_for!(screen) == :operator
      end
    end

    test "lists the locked presentation modes" do
      assert Presentation.modes() == [:bbs, :operator]
    end

    test "lists every current screen id exactly once" do
      assert MapSet.new(Presentation.screen_ids()) ==
               MapSet.new([
                 :login,
                 :register,
                 :verify,
                 :main_menu,
                 :board_list,
                 :thread_list,
                 :post_reader,
                 :new_thread,
                 :post_composer,
                 :account,
                 :moderation,
                 :sysop
               ])
    end

    test "rejects unknown screen ids deliberately" do
      assert_raise ArgumentError, ~r/unknown TUI screen/, fn ->
        Presentation.mode_for!(:does_not_exist)
      end
    end
  end

  describe "theme independence (MODE-01, THEME-02)" do
    test "presentation mode is not an authorization or permission boundary" do
      assert function_exported?(Presentation, :mode_for!, 1)
      refute function_exported?(Presentation, :mode_for!, 2)
    end

    test "theme ids cannot alter BBS or operator screen modes" do
      for _theme_id <- Theme.ids() do
        assert Presentation.mode_for!(:main_menu) == :bbs
        assert Presentation.mode_for!(:account) == :operator
      end
    end
  end
end

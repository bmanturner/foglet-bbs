defmodule Foglet.TUI.Widgets.Chrome.BreadcrumbBarTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.BreadcrumbBar

  describe "parts_for/1" do
    test "returns central paths rooted at Foglet for BBS screens" do
      assert BreadcrumbBar.parts_for(%{current_screen: :login}) == ["Foglet", "Login"]
      assert BreadcrumbBar.parts_for(%{current_screen: :main_menu}) == ["Foglet", "Home"]
      assert BreadcrumbBar.parts_for(%{current_screen: :board_list}) == ["Foglet", "Boards"]

      assert BreadcrumbBar.parts_for(%{
               current_screen: :thread_list,
               current_board: %{name: "general"}
             }) == ["Foglet", "Boards", "general"]

      assert BreadcrumbBar.parts_for(%{
               current_screen: :post_reader,
               current_board: %{name: "general"},
               current_thread: %{title: "Unicode screenshots thread"}
             }) == ["Foglet", "general", "Unicode screenshots thread"]
    end

    test "returns central paths for compose and operator screens" do
      assert BreadcrumbBar.parts_for(%{
               current_screen: :new_thread,
               current_board: %{name: "general"}
             }) == ["Foglet", "general", "New Thread"]

      assert BreadcrumbBar.parts_for(%{
               current_screen: :post_composer,
               current_board: %{name: "general"},
               current_thread: %{title: "Unicode screenshots thread"}
             }) == ["Foglet", "general", "Reply"]

      assert BreadcrumbBar.parts_for(%{
               current_screen: :account,
               screen_state: %{account: %{active_tab: 1}}
             }) == ["Foglet", "Account", "Prefs"]

      assert BreadcrumbBar.parts_for(%{current_screen: :moderation}) == ["Foglet", "Moderation"]
      assert BreadcrumbBar.parts_for(%{current_screen: :sysop}) == ["Foglet", "Sysop"]
    end

    test "unknown or incomplete state remains non-empty and rooted at Foglet" do
      assert ["Foglet" | _] = BreadcrumbBar.parts_for(%{current_screen: :unknown})
      assert ["Foglet" | _] = BreadcrumbBar.parts_for(%{})
    end
  end

  describe "format/2" do
    test "uses Unicode and ASCII separators" do
      assert BreadcrumbBar.format(["Foglet", "Boards", "general"], []) ==
               "Foglet ▸ Boards ▸ general"

      assert BreadcrumbBar.format(["Foglet", "Boards", "general"], ascii?: true) ==
               "Foglet > Boards > general"
    end

    test "does not exceed supplied width" do
      formatted =
        BreadcrumbBar.format(["Foglet", "general", "Unicode screenshots thread"], width: 20)

      assert TextWidth.display_width(formatted) <= 20
    end
  end

  describe "render/3" do
    test "renders formatted breadcrumb with explicit theme" do
      texts =
        Theme.default()
        |> BreadcrumbBar.render(["Foglet", "Boards", "general"], width: 80)
        |> collect_text_values()

      assert texts == ["Foglet ▸ Boards ▸ general"]
    end
  end
end

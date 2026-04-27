defmodule Foglet.TUI.Widgets.Chrome.BreadcrumbBarTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.BreadcrumbBar

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

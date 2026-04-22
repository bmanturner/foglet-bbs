defmodule Foglet.TUI.Widgets.CatalogSmokeTest do
  @moduledoc """
  Cross-bucket smoke + theme-hygiene test (Phase 8, REQ-W-13).

  Renders one widget from each bucket through a common theme and
  asserts (a) every render returns non-nil and (b) the combined
  rendered tree contains no hardcoded color atom. Catches the
  regression where per-widget hygiene passes in isolation but a
  slot gets leaked during composition (e.g., a new widget added
  without a proper `build_*_theme/1` helper).
  """

  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers, only: [color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme

  alias Foglet.TUI.Widgets.Display.{Progress, Table, Tree}
  alias Foglet.TUI.Widgets.Input.{Button, Checkbox, Menu, RadioGroup, Tabs, TextInput}
  alias Foglet.TUI.Widgets.List.SmartList
  alias Foglet.TUI.Widgets.Progress.Spinner

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp render_catalog(t) do
    [
      Button.render("Save", role: :primary, theme: t),
      Checkbox.render("Agree", checked?: true, theme: t),
      RadioGroup.render(["A", "B"], 0, theme: t),
      TextInput.render(TextInput.init(value: "hello"), theme: t, bordered: true),
      Tabs.render(Tabs.init(tabs: ["Home", "Posts"]), theme: t),
      Menu.render(Menu.init(items: [%{label: "File", children: []}]), theme: t),
      Table.render(Table.init(columns: [%{key: :name, label: "Name"}], rows: [%{name: "x"}]),
        theme: t
      ),
      Tree.render(Tree.init(nodes: [%{id: :root, label: "R", children: []}]), theme: t),
      Progress.render(0.5, theme: t),
      Spinner.render(0, theme: t),
      SmartList.render(SmartList.init(options: [{"A", 1}]), theme: t)
    ]
  end

  describe "per-widget smoke renders (D-17, D-18)" do
    setup do
      {:ok, t: theme()}
    end

    test "Input.Button renders", %{t: t} do
      refute is_nil(Button.render("Save", role: :primary, theme: t))
    end

    test "Input.Checkbox renders", %{t: t} do
      refute is_nil(Checkbox.render("Agree", checked?: true, theme: t))
    end

    test "Input.RadioGroup renders", %{t: t} do
      refute is_nil(RadioGroup.render(["A", "B"], 0, theme: t))
    end

    test "Input.TextInput renders", %{t: t} do
      state = TextInput.init(value: "hello")
      refute is_nil(TextInput.render(state, theme: t, bordered: true))
    end

    test "Input.Tabs renders", %{t: t} do
      state = Tabs.init(tabs: ["Home", "Posts"])
      refute is_nil(Tabs.render(state, theme: t))
    end

    test "Input.Menu renders", %{t: t} do
      state = Menu.init(items: [%{label: "File", children: []}])
      refute is_nil(Menu.render(state, theme: t))
    end

    test "Display.Table renders", %{t: t} do
      state = Table.init(columns: [%{key: :name, label: "Name"}], rows: [%{name: "x"}])
      refute is_nil(Table.render(state, theme: t))
    end

    test "Display.Tree renders", %{t: t} do
      state = Tree.init(nodes: [%{id: :root, label: "R", children: []}])
      refute is_nil(Tree.render(state, theme: t))
    end

    test "Display.Progress renders", %{t: t} do
      refute is_nil(Progress.render(0.5, theme: t))
    end

    test "Progress.Spinner renders", %{t: t} do
      refute is_nil(Spinner.render(0, theme: t))
    end

    test "List.SmartList renders", %{t: t} do
      state = SmartList.init(options: [{"A", 1}])
      refute is_nil(SmartList.render(state, theme: t))
    end
  end

  describe "cross-bucket combined render (D-18, REQ-W-13)" do
    test "no hardcoded color atoms leak in the combined tree (IN-03)" do
      trees = render_catalog(theme())
      serialized = inspect(trees, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "combined catalog render leaked :#{color}: serialized tree contained the atom"
      end
    end

    test "alt-theme produces a different combined tree" do
      default_out =
        theme()
        |> render_catalog()
        |> inspect(printable_limit: :infinity, limit: :infinity)

      alt_out =
        alt_theme()
        |> render_catalog()
        |> inspect(printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out,
             "switching the theme must produce a different combined render"
    end
  end
end

defmodule Foglet.TUI.Widgets.Auth.AuthFormTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers, only: [color_atom_leaked?: 2, color_names: 0, flatten_text: 1]
  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Auth.AuthForm

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  describe "render/4 — smoke (D-18)" do
    test "renders a titled panel with supplied children" do
      tree =
        AuthForm.render(
          "Login",
          [text("Use your Foglet handle.")],
          theme(),
          width: 46,
          height: 9
        )

      assert tree.type == :panel
      assert tree.attrs.title == "Login"
      assert tree.attrs.width == 46
      assert tree.attrs.height == 9
      assert flatten_text(tree) =~ "Use your Foglet handle."
    end

    test "centered/4 returns the panel with vertical padding without changing it" do
      panel = AuthForm.render("Verify email", [text("Code")], theme())

      centered = AuthForm.centered(panel, %{terminal_size: {80, 24}}, theme(), 9)

      assert flatten_text(centered) =~ "Code"
    end
  end

  describe "render/4 — theme hygiene (D-18)" do
    test "no hardcoded terminal color atoms leak into the rendered tree" do
      serialized = inspect(AuthForm.render("Login", [text("Hello")], theme()))

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "auth form render leaked :#{color}: serialized tree contained the atom"
      end
    end

    test "active and inactive cards route border/title colors through theme slots" do
      default_tree = AuthForm.render("Login", [text("Hello")], theme(), active?: true)
      inactive_tree = AuthForm.render("Login", [text("Hello")], theme(), active?: false)
      danger_tree = AuthForm.render("Login", [text("Hello")], alt_theme(), active?: true)

      assert inspect(default_tree) != inspect(inactive_tree)
      assert inspect(default_tree) != inspect(danger_tree)
    end
  end
end

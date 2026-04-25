defmodule Foglet.TUI.Widgets.Display.BadgeTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [
      flatten_text: 1,
      color_atom_leaked?: 2,
      color_names: 0,
      assert_text_run: 3
    ]

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Badge

  @required_states [
    :required,
    :subscribed,
    :locked,
    :sticky,
    :pending,
    :healthy,
    :error,
    :neutral,
    :info
  ]

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      info: %{fg: "#badge-info"},
      success: %{fg: "#badge-success", style: [:bold]},
      warning: %{fg: "#badge-warning"},
      error: %{fg: "#badge-error", style: [:bold]},
      accent: %{fg: "#badge-accent", style: [:bold]}
    }
  end

  describe "render/2 states (D-01, D-06, D-07)" do
    test "renders every required state with recognizable compact text" do
      for state <- @required_states do
        tree = Badge.render(state, theme: theme())
        flat = flatten_text(tree)

        assert flat =~ Atom.to_string(state)
        assert TextWidth.display_width(flat) <= 16
      end
    end

    test "custom label can override built-in compact label" do
      tree = Badge.render(:healthy, label: "database healthy", theme: theme())

      assert flatten_text(tree) == "[database healthy]"
      assert TextWidth.display_width(flatten_text(tree)) > 16
    end
  end

  describe "render/2 theme routing (D-08)" do
    test "resolves state role through Presentation badge mappings and Theme slots" do
      mappings = Presentation.theme_mappings().badges
      role = :warning
      slot = Map.fetch!(mappings, role)
      t = distinctive_theme()

      tree = Badge.render(:required, theme: t)

      assert_text_run(tree, "required", fg: Map.fetch!(t, slot).fg)
    end

    test "unsupported caller role falls back through info badge mapping" do
      mappings = Presentation.theme_mappings().badges
      slot = Map.fetch!(mappings, :info)
      t = distinctive_theme()

      tree = Badge.render(:neutral, role: :unknown, theme: t)

      assert_text_run(tree, "neutral", fg: Map.fetch!(t, slot).fg)
    end

    test "alt-theme differential changes serialized output" do
      default_tree = Badge.render(:error, theme: theme())
      danger_tree = Badge.render(:error, theme: alt_theme())

      s1 = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(danger_tree, printable_limit: :infinity, limit: :infinity)

      assert s1 != s2, "Expected Badge to route through the active theme"
    end
  end

  describe "render/2 theme hygiene (D-21, D-23)" do
    test "no hardcoded color atoms appear in rendered output" do
      for state <- @required_states do
        tree = Badge.render(state, theme: theme())
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color),
                 "Badge #{inspect(state)} leaked :#{color} atom: #{serialized}"
        end
      end
    end
  end
end

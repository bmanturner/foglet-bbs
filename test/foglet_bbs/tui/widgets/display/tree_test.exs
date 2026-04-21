defmodule Foglet.TUI.Widgets.Display.TreeTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Tree

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  @root_with_child %{
    id: :root,
    label: "Root",
    children: [%{id: :child, label: "Child", children: []}]
  }

  @leaf_node %{id: :leaf, label: "Leaf", children: []}

  describe "init/1 — smoke (D-18)" do
    test "returns a Tree struct from valid options" do
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      assert %Tree{} = state
    end

    test "renders non-nil element" do
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      result = Tree.render(state, theme: theme())
      refute is_nil(result)
    end

    test "rendered tree contains node label text" do
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      result = Tree.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Root"
    end
  end

  describe "render/2 — theme slot routing (D-18)" do
    test "rendered tree contains primary.fg for non-selected node text" do
      t = theme()
      # Two sibling nodes: cursor starts at :a, so :b renders with primary.fg
      nodes = [
        %{id: :a, label: "Alpha", children: []},
        %{id: :b, label: "Beta", children: []}
      ]

      state = Tree.init(nodes: nodes)
      result = Tree.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.primary.fg
    end

    test "rendered tree contains selected.fg for the cursor node" do
      t = theme()
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      result = Tree.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.selected.fg
    end
  end

  describe "handle_event/2 (D-14)" do
    test "Right arrow on a parent with children returns :node_expanded" do
      state = Tree.init(nodes: [@root_with_child])
      {_new_state, action} = Tree.handle_event(%{key: :right}, state)
      assert action == :node_expanded
    end

    test "Left arrow on an expanded parent returns :node_collapsed" do
      state = Tree.init(nodes: [@root_with_child])
      {expanded_state, :node_expanded} = Tree.handle_event(%{key: :right}, state)
      {_new_state, action} = Tree.handle_event(%{key: :left}, expanded_state)
      assert action == :node_collapsed
    end

    test "Enter on a leaf node returns :node_activated" do
      # Navigate to the child leaf via expand then down
      state = Tree.init(nodes: [@root_with_child])
      {expanded_state, :node_expanded} = Tree.handle_event(%{key: :right}, state)
      {leaf_state, _} = Tree.handle_event(%{key: :down}, expanded_state)
      {_final, action} = Tree.handle_event(%{key: :enter}, leaf_state)
      assert action == :node_activated
    end

    test "WR-06 — Enter on a parent does NOT emit :node_activated" do
      # cursor starts on :root (a parent); pressing Enter without expanding
      # must not claim the parent was activated.
      state = Tree.init(nodes: [@root_with_child])
      {_final, action} = Tree.handle_event(%{key: :enter}, state)
      refute action == :node_activated
    end

    test "handle_event/2 returns a two-element tuple" do
      state = Tree.init(nodes: [@leaf_node])
      result = Tree.handle_event(%{key: :down}, state)
      assert {%Tree{}, _action} = result
    end

    test "purity: same state + event → same output" do
      state = Tree.init(nodes: [@root_with_child])
      result1 = Tree.handle_event(%{key: :right}, state)
      result2 = Tree.handle_event(%{key: :right}, state)
      assert result1 == result2
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "Pitfall 9 is documented in moduledoc" do
      # The module's documentation must cite Pitfall 9 (node shape requirement)
      assert {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Tree)
      assert moduledoc =~ "Pitfall 9"
    end

    test "no hardcoded color atoms appear in the rendered tree (IN-03)" do
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      tree = Tree.render(state, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Tree leaked :#{color} atom: #{serialized}"
      end
    end

    test "alt-theme differential: default vs danger produce different serialized output" do
      state = Tree.init(nodes: [@root_with_child])
      default_tree = Tree.render(state, theme: theme())
      danger_tree = Tree.render(state, theme: alt_theme())

      s1 = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(danger_tree, printable_limit: :infinity, limit: :infinity)

      assert s1 != s2, "Expected different rendering with different themes"
    end
  end
end

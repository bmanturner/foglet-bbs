defmodule Foglet.TUI.Widgets.Display.TreeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Tree

  # --- Local helpers (copied from list_row_test.exs pattern) ---

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

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
    test "rendered tree contains primary.fg for node text" do
      t = theme()
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      result = Tree.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.primary.fg)
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

    test "no hardcoded color atoms appear in the rendered tree" do
      state = Tree.init(nodes: [%{id: :root, label: "Root", children: []}])
      tree = Tree.render(state, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ":red", "Tree leaked :red atom: #{serialized}"
      refute serialized =~ ":green", "Tree leaked :green atom: #{serialized}"
      refute serialized =~ ":yellow", "Tree leaked :yellow atom: #{serialized}"
      refute serialized =~ ":cyan", "Tree leaked :cyan atom: #{serialized}"
      refute serialized =~ ":magenta", "Tree leaked :magenta atom: #{serialized}"
      refute serialized =~ ":blue", "Tree leaked :blue atom: #{serialized}"
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

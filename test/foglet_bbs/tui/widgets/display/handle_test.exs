defmodule Foglet.TUI.Widgets.Display.HandleTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Handle

  defp text_nodes(tree) do
    tree
    |> flatten_nodes()
    |> Enum.filter(&(Map.get(&1, :type) == :text))
  end

  defp flatten_nodes(node), do: do_flatten_nodes(node, [])

  defp do_flatten_nodes(nodes, acc) when is_list(nodes),
    do: Enum.flat_map(nodes, &do_flatten_nodes(&1, acc))

  defp do_flatten_nodes(%{} = node, _acc) do
    [node | do_flatten_nodes(Map.get(node, :children, []), [])]
  end

  defp do_flatten_nodes(_other, _acc), do: []

  test "renders a sanitized handle with the user's validated custom color" do
    node = Handle.render(%{handle: "alice", handle_color: "#ff8800"}, Theme.default())

    assert collect_text_values(node) == ["@alice"]
    assert [%{fg: "#ff8800"}] = text_nodes(node)
  end

  test "falls back to theme color when handle color is blank or invalid" do
    theme = Theme.default()

    blank = Handle.render(%{handle: "alice", handle_color: nil}, theme)
    invalid = Handle.render(%{handle: "bob", handle_color: "red"}, theme)

    assert [%{fg: blank_fg}] = text_nodes(blank)
    assert [%{fg: invalid_fg}] = text_nodes(invalid)
    assert blank_fg == theme.accent.fg
    assert invalid_fg == theme.accent.fg
  end

  test "does not recolor arbitrary mention text" do
    body = "hello @alice"
    node = Handle.render_plain(body, Theme.default())

    assert collect_text_values(node) == [body]
    assert [%{fg: fg}] = text_nodes(node)
    assert fg == Theme.default().primary.fg
  end
end

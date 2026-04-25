defmodule Foglet.TUI.Widgets.Chrome.KeyBarTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.KeyBar

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

  defp theme, do: Theme.default()

  describe "render/3 width contract" do
    test "ASCII hints stay within a 64-column keybar" do
      keys = [
        {"J/K", "Navigate"},
        {"Enter", "Select current item"},
        {"Q", "Back"}
      ]

      flat = KeyBar.render(theme(), keys, width: 64) |> flatten_text()

      assert flat =~ "[J/K] Navigate"
      assert TextWidth.display_width(flat) <= 64
    end

    test "Unicode hints stay within requested display widths" do
      keys = [
        {"漢字", "Board names"},
        {"E", "cafe\u0301 editor"},
        {"● ◆", "▸ ▾ ✓ × actions"},
        {"Q", "Back"}
      ]

      for width <- [64, 80] do
        flat = KeyBar.render(theme(), keys, width: width) |> flatten_text()

        assert flat =~ "[漢字]"
        assert flat =~ "cafe\u0301"
        assert TextWidth.display_width(flat) <= width
      end
    end
  end
end

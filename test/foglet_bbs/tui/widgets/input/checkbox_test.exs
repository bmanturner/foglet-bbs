defmodule Foglet.TUI.Widgets.Input.CheckboxTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Checkbox

  # --- flatten_text helpers (copied verbatim from list_row_test.exs:9-24) ---

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

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil Raxol element" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      refute is_nil(result)
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "alt-theme differential (placeholder — filled in task 2)" do
      default_tree = Checkbox.render("x", checked?: false, theme: theme())
      alt_tree = Checkbox.render("x", checked?: false, theme: alt_theme())

      default_out = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      alt_out = inspect(alt_tree, printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out
    end
  end
end

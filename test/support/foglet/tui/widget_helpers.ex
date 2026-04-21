defmodule Foglet.TUI.WidgetHelpers do
  @moduledoc """
  Shared helpers for TUI widget tests.

  `flatten_text/1` walks a Raxol render tree and concatenates every
  `:content` / `:text` leaf into one string, so tests can make simple
  substring assertions about rendered output regardless of tree shape.

  Extracted from the 11 test files that duplicated these helpers
  verbatim (see IN-02 in 08-REVIEW.md). Wire in by calling
  `import Foglet.TUI.WidgetHelpers` from a widget test file.
  """

  @doc """
  Flattens a Raxol render tree to a single string by concatenating the
  leaf `:content` / `:text` values in document order.
  """
  @spec flatten_text(any()) :: String.t()
  def flatten_text(tree),
    do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  # --- private ---

  defp collect_text(nil, acc), do: acc

  defp collect_text(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content),
    do: [content | acc]

  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content),
    do: [content | acc]

  defp maybe_add_content(_node, acc), do: acc
end

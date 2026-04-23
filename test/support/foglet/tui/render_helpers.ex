defmodule Foglet.TUI.RenderHelpers do
  @moduledoc """
  Shared helpers for screen-level render tests.

  `collect_text_values/1` walks a Raxol render tree and returns every
  `:text`-node `:content` string in depth-first (DFS) document order, so
  tests can assert both presence AND relative ordering of labels without
  depending on accumulator-reversal tricks.

  Previously duplicated across five test modules (Account, MainMenu,
  Moderation, Sysop, InvitesSurface) — see IN-06 in 00-REVIEW.md. Wire in
  by calling `import Foglet.TUI.RenderHelpers` from a screen test file.

  ## Ordering contract

  The returned list is in DFS (document) order. Children appear after
  their parent's own `:content` (when present) and before the parent's
  later siblings. This lets tests that verify tab-label ordering assert
  `positions == Enum.sort(positions)` against canonical D-10/D-11 sequences
  without the render code having to list children in reverse to compensate
  for a prepend-accumulator.
  """

  @doc """
  Walks a Raxol render tree (or list of render trees) and returns every
  `:text`-node `:content` string in DFS document order.
  """
  @spec collect_text_values(any()) :: [String.t()]
  def collect_text_values(tree), do: tree |> collect([]) |> :lists.reverse()

  # --- private DFS walker with prepend-accumulation (reversed at return) ---

  defp collect(node, acc) when is_map(node) do
    acc =
      case Map.get(node, :type) do
        :text ->
          content = Map.get(node, :content)
          if is_binary(content), do: [content | acc], else: acc

        _ ->
          acc
      end

    node
    |> Map.get(:children, [])
    |> collect(acc)
  end

  defp collect(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, text_acc -> collect(node, text_acc) end)
  end

  defp collect(_other, acc), do: acc
end

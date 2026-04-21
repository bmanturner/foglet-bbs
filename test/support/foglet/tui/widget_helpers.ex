defmodule Foglet.TUI.WidgetHelpers do
  @moduledoc """
  Shared helpers for TUI widget tests.

  `flatten_text/1` walks a Raxol render tree and concatenates every
  `:content` / `:text` leaf into one string, so tests can make simple
  substring assertions about rendered output regardless of tree shape.

  `color_atom_leaked?/2` does a word-boundary regex check for a leaked
  color atom in a serialized render tree — strictly matches the atom
  literal `:red` and not substrings like `:hovered_red` or `"red-30"`
  (see IN-03 in 08-REVIEW.md).

  Extracted from the 11 test files that duplicated these helpers
  verbatim (see IN-02 in 08-REVIEW.md). Wire in by calling
  `import Foglet.TUI.WidgetHelpers` from a widget test file.
  """

  @color_names ~w(red green cyan yellow blue magenta white black)

  @doc """
  Flattens a Raxol render tree to a single string by concatenating the
  leaf `:content` / `:text` values in document order.
  """
  @spec flatten_text(any()) :: String.t()
  def flatten_text(tree),
    do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  @doc """
  Returns the list of the eight core color names the hygiene tests scan
  for (`"red"`, `"green"`, etc.). Exposed so test modules can iterate
  without hard-coding the list themselves.
  """
  @spec color_names() :: [String.t()]
  def color_names, do: @color_names

  @doc """
  True when `serialized` contains the atom literal `:<color>` as a
  standalone token (not a substring of a larger identifier or a bare
  string). Uses a word-boundary regex to avoid false positives against
  legitimate slot names like `:hovered_red` or values like `"red-30"`.

  Example:

      iex> Foglet.TUI.WidgetHelpers.color_atom_leaked?(":red, fg: X", "red")
      true

      iex> Foglet.TUI.WidgetHelpers.color_atom_leaked?(":hovered_red", "red")
      false
  """
  @spec color_atom_leaked?(String.t(), String.t()) :: boolean()
  def color_atom_leaked?(serialized, color) when is_binary(serialized) do
    # (?<![\w-]) : no preceding word-char or hyphen (so "_red" and "-red" don't match)
    # :<color>   : the literal colon + color name
    # (?![\w-])  : no trailing word-char or hyphen
    Regex.match?(~r/(?<![\w-]):#{color}(?![\w-])/, serialized)
  end

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

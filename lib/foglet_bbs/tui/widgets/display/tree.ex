defmodule Foglet.TUI.Widgets.Display.Tree do
  @moduledoc """
  Themed hierarchical tree widget with expand/collapse + keyboard nav
  (D-02, D-13, D-14).

  Stateful facade over `Raxol.UI.Components.Display.Tree`.

  Rendering is handled directly by this wrapper using `visible_nodes/1`
  from the Raxol component to compute the visible node list, then emitting
  each node as a themed `text/2` row. This ensures all colors come from
  `Foglet.TUI.Theme` slots and no hardcoded color atoms leak (D-07/D-09).

  **Pitfall 9 (RESEARCH.md):** Tree nodes MUST be maps with keys
  `:id`, `:label`, `:children`, optional `:data`. Keyword-list or
  struct-based nodes will crash `visible_nodes/1` and `find_parent/2`
  pattern-matching inside Raxol.

  ## Node shape

      %{id: atom(), label: String.t(), children: [node()], data: any()}

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)

  ## Actions returned from `handle_event/2`

      :node_expanded  — a parent was expanded (children became visible)
      :node_collapsed — a parent was collapsed
      :node_activated — Enter on a leaf node
      nil             — navigation key, no semantic action
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Display.Tree, as: RaxolTree

  @default_indent_size 2

  @type tree_node :: %{
          required(:id) => atom(),
          required(:label) => String.t(),
          required(:children) => [tree_node()],
          optional(:data) => any()
        }

  @type action :: :node_expanded | :node_collapsed | :node_activated | nil

  defstruct [:raxol_state, last_action: nil]

  @type t :: %__MODULE__{raxol_state: map(), last_action: action()}

  @doc """
  Pure constructor.

  Options:
    * `:nodes`       — list of node maps (required; see Pitfall 9 note above)
    * `:id`          — optional id string (auto-generated if omitted)
    * `:indent_size` — integer (default `#{@default_indent_size}`)
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    nodes = Keyword.fetch!(opts, :nodes)
    id = Keyword.get(opts, :id, "tree-#{:erlang.unique_integer([:positive])}")
    indent = Keyword.get(opts, :indent_size, @default_indent_size)

    {:ok, raxol_state} =
      RaxolTree.init(id: id, nodes: nodes, indent_size: indent)

    %__MODULE__{raxol_state: raxol_state, last_action: nil}
  end

  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
    {new_rs, _cmds} = RaxolTree.handle_event(raxol_event, rs, %{})
    action = derive_action(rs, new_rs, event)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @doc """
  Renders the tree using themed DSL rows. Colors come from Foglet theme
  slots (D-07/D-09). Raxol's internal render is NOT called — we use
  `visible_nodes/1` to compute the visible set, then emit each as a
  `text/2` with theme-routed fg/bg.
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    indent = Map.get(rs, :indent_size, @default_indent_size)
    cursor = Map.get(rs, :cursor)
    visible = RaxolTree.visible_nodes(rs)

    rows =
      Enum.map(visible, fn {node, depth} ->
        indent_str = String.duplicate(" ", depth * indent)
        icon = node_icon(node, rs)
        label = "#{indent_str}#{icon} #{node.label}"

        if node.id == cursor do
          text(label, selected_attrs(theme))
        else
          text(label, fg: theme.primary.fg)
        end
      end)

    column style: %{gap: 0} do
      rows
    end
  end

  # --- private ---

  # IN-07: Only include :bg when the theme's :selected slot actually sets
  # one. Today's Foglet themes all do, but a future theme that omits :bg
  # would pass `bg: nil` to Raxol's text/2, and Raxol's rendering of
  # `nil` bg is unspecified. Build the attrs list conditionally so nil
  # is never emitted.
  defp selected_attrs(theme) do
    base = [fg: theme.selected.fg, style: Map.get(theme.selected, :style, [])]

    case Map.get(theme.selected, :bg) do
      nil -> base
      bg -> [{:bg, bg} | base]
    end
  end

  defp node_icon(%{children: []}, _rs), do: " "

  defp node_icon(%{id: id}, rs) do
    expanded = Map.get(rs, :expanded, MapSet.new())
    if MapSet.member?(expanded, id), do: "▼", else: "▶"
  end

  defp derive_action(before_rs, after_rs, %{key: key})
       when key in [:enter, :right, :left, :space] do
    before_size = MapSet.size(Map.get(before_rs, :expanded, MapSet.new()))
    after_size = MapSet.size(Map.get(after_rs, :expanded, MapSet.new()))

    cond do
      after_size > before_size -> :node_expanded
      after_size < before_size -> :node_collapsed
      key == :enter and leaf_under_cursor?(after_rs) -> :node_activated
      true -> nil
    end
  end

  defp derive_action(_, _, _), do: nil

  # WR-06: :node_activated is documented as "Enter on a leaf node". Raxol's
  # tree component may bind :enter to an already-expanded-parent as a no-op
  # (expansion state unchanged) — without inspecting the cursor node's
  # children we'd spuriously fire :node_activated for that parent. Return
  # true only when the cursor points at a node with no children.
  defp leaf_under_cursor?(rs) do
    cursor = Map.get(rs, :cursor)
    nodes = Map.get(rs, :nodes, [])

    case find_node(nodes, cursor) do
      %{children: []} -> true
      _ -> false
    end
  end

  defp find_node(_nodes, nil), do: nil

  defp find_node(nodes, id) when is_list(nodes) do
    Enum.find_value(nodes, fn
      %{id: ^id} = n ->
        n

      %{children: children} ->
        find_node(children, id)

      _ ->
        nil
    end)
  end
end

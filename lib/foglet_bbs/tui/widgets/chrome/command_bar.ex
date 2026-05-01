defmodule Foglet.TUI.Widgets.Chrome.CommandBar do
  @moduledoc """
  Grouped Chrome V2 command hint renderer for Foglet BBS.

  This is a passive display widget: it renders command affordances only and
  does not authorize, route, or execute actions. Implements the Phase 18
  command-bar contract while honoring the theme-routing decisions D-07, D-09,
  D-13, and stateless widget decision D-16.

  Command priority is a retention priority: lower numbers are kept first when
  the bar must drop hints to fit a narrow terminal. Use `0` for system escape
  hatches, `5` for the screen's primary action, `10` for routine navigation,
  and larger numbers for secondary hints that may disappear first.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @default_priority 50
  @group_gap "   "
  @command_gap "  "
  @key_gap " "
  @hidden_group_labels MapSet.new(["System"])

  @type command :: %{
          required(:key) => String.t(),
          required(:label) => String.t(),
          required(:priority) => integer(),
          optional(:destructive?) => boolean(),
          optional(:inactive?) => boolean()
        }

  @type group :: %{
          required(:label) => String.t(),
          required(:commands) => [command()]
        }

  @doc """
  Renders grouped commands within an optional display-width budget.
  """
  @spec render(Theme.t(), [map() | struct()], keyword()) :: any()
  def render(%Theme{} = theme, groups, opts \\ []) when is_list(groups) do
    width = Keyword.get(opts, :width)

    groups =
      groups
      |> normalize_groups()
      |> visible_groups(width)

    row style: %{gap: 0} do
      render_segments(theme, groups, width)
    end
  end

  @doc """
  Returns the plain grouped command text for embedding in enclosing chrome.
  """
  @spec render_text([map() | struct()], keyword()) :: String.t()
  def render_text(groups, opts \\ []) when is_list(groups) do
    width = Keyword.get(opts, :width)

    groups
    |> normalize_groups()
    |> visible_groups(width)
    |> groups_text()
  end

  @doc """
  Normalizes map or struct command groups into the Chrome V2 command shape.
  """
  @spec normalize_groups([map() | struct()]) :: [group()]
  def normalize_groups(groups) when is_list(groups) do
    groups
    |> Enum.map(&normalize_group/1)
    |> Enum.reject(&(&1.commands == []))
    |> Enum.sort_by(fn group -> {minimum_priority(group), group.label} end)
  end

  defp normalize_group(group) do
    group = to_map(group)

    commands =
      group
      |> Map.get(:commands, [])
      |> Enum.with_index()
      |> Enum.map(fn {command, index} -> normalize_command(command, index) end)
      |> Enum.sort_by(fn command -> {command.priority, command.order} end)

    %{
      label: group |> Map.get(:label, "") |> to_string(),
      commands: commands
    }
  end

  defp normalize_command(command, index) do
    command = to_map(command)

    %{
      key: command |> Map.get(:key, "") |> to_string(),
      label: command |> Map.get(:label, "") |> to_string(),
      priority: Map.get(command, :priority, @default_priority),
      order: index,
      destructive?: Map.get(command, :destructive?, false),
      inactive?: Map.get(command, :inactive?, false)
    }
  end

  defp to_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_map(map) when is_map(map), do: map

  defp visible_groups(groups, nil), do: groups

  defp visible_groups(groups, width) when is_integer(width) do
    cond do
      width <= 0 ->
        []

      rendered_width(groups) <= width ->
        groups

      true ->
        groups
        |> drop_candidates()
        |> Enum.reduce_while(groups, fn candidate, current ->
          reduced = drop_command(current, candidate)

          if rendered_width(reduced) <= width do
            {:halt, reduced}
          else
            {:cont, reduced}
          end
        end)
        |> fit_highest_priority(width)
    end
  end

  defp fit_highest_priority(groups, width) do
    if rendered_width(groups) <= width do
      groups
    else
      groups
      |> Enum.take(1)
      |> Enum.map(fn group ->
        %{group | commands: Enum.take(group.commands, 1)}
      end)
      |> truncate_single_command(width)
    end
  end

  defp truncate_single_command([], _width), do: []

  defp truncate_single_command([%{commands: []} = group], _width), do: [%{group | commands: []}]

  defp truncate_single_command([%{commands: [command | _]} = group], width) do
    fixed_width = TextWidth.display_width(group.label <> @command_gap <> command.key <> @key_gap)
    label_width = max(width - fixed_width, 0)
    command = %{command | label: TextWidth.truncate(command.label, label_width)}

    if label_width == 0 do
      []
    else
      [%{group | commands: [command]}]
    end
  end

  defp drop_candidates(groups) do
    groups
    |> Enum.flat_map(fn group ->
      Enum.map(group.commands, fn command ->
        %{group: group.label, key: command.key, order: command.order, priority: command.priority}
      end)
    end)
    |> Enum.sort_by(fn command -> {command.priority, command.order} end, :desc)
  end

  defp drop_command(groups, candidate) do
    groups
    |> Enum.map(fn group ->
      commands =
        Enum.reject(group.commands, fn command ->
          group.label == candidate.group and command.key == candidate.key and
            command.order == candidate.order
        end)

      %{group | commands: commands}
    end)
    |> Enum.reject(&(&1.commands == []))
  end

  defp rendered_width(groups), do: groups |> groups_text() |> TextWidth.display_width()

  defp groups_text(groups) do
    Enum.map_join(groups, @group_gap, fn group ->
      command_text =
        Enum.map_join(group.commands, @command_gap, fn command ->
          command.key <> @key_gap <> command.label
        end)

      case display_group_label(group.label) do
        "" -> command_text
        label -> label <> @command_gap <> command_text
      end
    end)
  end

  defp render_segments(theme, groups, width) do
    mappings = Presentation.theme_mappings().commands

    nodes =
      groups
      |> Enum.map(fn group ->
        render_group(theme, group, mappings)
      end)
      |> Enum.intersperse([text(@group_gap)])
      |> List.flatten()

    trim_to_width(nodes, width)
  end

  defp render_group(theme, group, mappings) do
    command_nodes = render_commands(theme, group.commands, mappings)

    case display_group_label(group.label) do
      "" ->
        command_nodes

      label ->
        [
          text(label, style_attrs(theme, mappings.group)),
          text(@command_gap)
          | command_nodes
        ]
    end
  end

  defp display_group_label(label) do
    label = to_string(label)

    if MapSet.member?(@hidden_group_labels, label) do
      ""
    else
      label
    end
  end

  defp render_commands(theme, commands, mappings) do
    commands
    |> Enum.flat_map(fn command ->
      [
        text(command.key, style_attrs(theme, command_slot(command, mappings))),
        text(@key_gap <> command.label, style_attrs(theme, label_slot(command, mappings)))
      ]
    end)
    |> insert_command_gaps()
  end

  defp insert_command_gaps([]), do: []

  defp insert_command_gaps(nodes) do
    nodes
    |> Enum.chunk_every(2)
    |> Enum.intersperse([text(@command_gap)])
    |> List.flatten()
  end

  defp trim_to_width(nodes, nil), do: nodes

  defp trim_to_width(nodes, width) do
    {fit, _remaining} =
      Enum.reduce_while(nodes, {[], width}, fn node, {acc, remaining} ->
        content = Map.get(node, :content, Map.get(node, :text, ""))
        node_width = TextWidth.display_width(content)

        cond do
          node_width <= remaining ->
            {:cont, {acc ++ [node], remaining - node_width}}

          remaining > 0 ->
            truncated = Map.put(node, :content, TextWidth.truncate(content, remaining))
            {:halt, {acc ++ [truncated], 0}}

          true ->
            {:halt, {acc, remaining}}
        end
      end)

    fit
  end

  defp command_slot(%{inactive?: true}, mappings), do: mappings.inactive
  defp command_slot(%{destructive?: true}, mappings), do: mappings.destructive
  defp command_slot(_command, mappings), do: mappings.key

  defp label_slot(%{inactive?: true}, mappings), do: mappings.inactive
  defp label_slot(_command, mappings), do: mappings.inactive

  defp style_attrs(theme, slot) do
    style = Map.fetch!(theme, slot)
    [fg: Map.get(style, :fg), bg: Map.get(style, :bg), style: Map.get(style, :style, [])]
  end

  defp minimum_priority(%{commands: commands}) do
    commands
    |> Enum.map(& &1.priority)
    |> Enum.min(fn -> @default_priority end)
  end
end

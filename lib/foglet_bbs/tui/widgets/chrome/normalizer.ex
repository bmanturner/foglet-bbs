defmodule Foglet.TUI.Widgets.Chrome.Normalizer do
  @moduledoc """
  Compatibility adapter from legacy flat key hints to Chrome V2 commands.

  The normalizer keeps old `{key, description}` callers on the grouped command
  contract without preserving a second footer renderer. It is display metadata
  only; command execution and authorization remain in screen handlers and
  domain contexts.
  """

  alias Foglet.TUI.Widgets.Chrome.CommandBar

  @system_group "System"
  @navigate_group "Navigate"
  @actions_group "Actions"
  @tabs_group "Tabs"
  @field_group "Field"
  @save_group "Save"
  @refresh_group "Refresh"

  @system_priority 0
  @navigation_priority 0
  @structured_priority 10
  @action_priority 30
  @optional_priority 50

  @doc """
  Converts legacy `{key, description}` pairs into grouped command data.
  """
  @spec commands([{term(), term()}]) :: [CommandBar.group()]
  def commands(keys) when is_list(keys) do
    keys
    |> Enum.map(fn {key, label} -> normalize_pair(key, label) end)
    |> Enum.group_by(& &1.group)
    |> Enum.map(fn {group, commands} ->
      %{
        label: group,
        commands:
          Enum.map(commands, fn command ->
            %{key: command.key, label: command.label, priority: command.priority}
          end)
      }
    end)
    |> CommandBar.normalize_groups()
  end

  @doc """
  Builds one explicit command group.
  """
  @spec command(term(), term(), term()) :: CommandBar.group()
  def command(group, key, label) do
    group = to_string(group)

    %{
      label: group,
      commands: [
        %{
          key: to_string(key),
          label: to_string(label),
          priority: default_priority_for_group(group, to_string(key), to_string(label))
        }
      ]
    }
  end

  defp normalize_pair(key, label) do
    key = to_string(key)
    label = to_string(label)
    group = classify_group(key, label)

    %{
      group: group,
      key: key,
      label: label,
      priority: default_priority_for_group(group, key, label)
    }
  end

  defp classify_group(key, label) do
    key_down = String.downcase(key)
    label_down = String.downcase(label)

    cond do
      label_down in ["back", "quit", "cancel"] ->
        @system_group

      key_down in ["s/enter", "save"] or label_down =~ "save" ->
        @save_group

      label_down =~ "refresh" ->
        @refresh_group

      key_down == "tab" or label_down =~ "field" ->
        @field_group

      key in ["←/→", "1-5", "1-6"] or label_down =~ "tab" ->
        @tabs_group

      navigation_key?(key_down) or navigation_label?(label_down) ->
        @navigate_group

      true ->
        @actions_group
    end
  end

  defp navigation_key?(key) do
    key in ["j/k", "↑/↓", "up/down", "enter", "return"]
  end

  defp navigation_label?(label) do
    Enum.any?(
      ["navigate", "move", "open", "select", "collapse", "expand"],
      &String.contains?(label, &1)
    )
  end

  defp default_priority_for_group(@system_group, _key, _label), do: @system_priority
  defp default_priority_for_group(@navigate_group, _key, _label), do: @navigation_priority
  defp default_priority_for_group(@tabs_group, _key, _label), do: @structured_priority
  defp default_priority_for_group(@field_group, _key, _label), do: @structured_priority
  defp default_priority_for_group(@save_group, _key, _label), do: @structured_priority
  defp default_priority_for_group(@refresh_group, _key, _label), do: @structured_priority

  defp default_priority_for_group(@actions_group, _key, label) do
    label = String.downcase(label)

    if String.contains?(label, "verbose") or String.contains?(label, "help") do
      @optional_priority
    else
      @action_priority
    end
  end

  defp default_priority_for_group(_group, _key, _label), do: @action_priority
end

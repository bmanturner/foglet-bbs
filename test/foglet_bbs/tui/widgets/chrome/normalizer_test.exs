defmodule Foglet.TUI.Widgets.Chrome.NormalizerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Widgets.Chrome.Normalizer

  describe "commands/1" do
    test "normalizes a simple back key into the System group" do
      assert [
               %{
                 label: "System",
                 commands: [%{key: "Q", label: "Back", priority: 0}]
               }
             ] = Normalizer.commands([{"Q", "Back"}])
    end

    test "groups common navigation, action, tab, field, save, and refresh hints" do
      groups =
        Normalizer.commands([
          {"j/k", "Move"},
          {"Enter", "Open"},
          {"Tab", "Next field"},
          {"←/→", "Switch tab"},
          {"S/Enter", "Save"},
          {"R", "Refresh"},
          {"F", "Filter"},
          {"?", "Verbose help"}
        ])

      assert group(groups, "Navigate") == [
               %{key: "j/k", label: "Move", priority: 0},
               %{key: "Enter", label: "Open", priority: 0}
             ]

      assert group(groups, "Tabs") == [%{key: "←/→", label: "Switch tab", priority: 10}]
      assert group(groups, "Field") == [%{key: "Tab", label: "Next field", priority: 10}]
      assert group(groups, "Save") == [%{key: "S/Enter", label: "Save", priority: 10}]
      assert group(groups, "Refresh") == [%{key: "R", label: "Refresh", priority: 10}]
      assert group(groups, "Actions") == [
               %{key: "F", label: "Filter", priority: 30},
               %{key: "?", label: "Verbose help", priority: 50}
             ]
    end
  end

  describe "command/3" do
    test "builds an explicit command group" do
      assert %{
               label: "Actions",
               commands: [%{key: "C", label: "Compose", priority: 30}]
             } = Normalizer.command("Actions", "C", "Compose")
    end
  end

  defp group(groups, label) do
    groups
    |> Enum.find(&(&1.label == label))
    |> Map.fetch!(:commands)
  end
end

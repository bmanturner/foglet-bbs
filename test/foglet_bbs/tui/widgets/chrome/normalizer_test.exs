defmodule Foglet.TUI.Widgets.Chrome.NormalizerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Widgets.Chrome.Normalizer

  @tui_root Path.expand("../../../../../lib/foglet_bbs/tui", __DIR__)
  @key_bar_path Path.join(@tui_root, "widgets/chrome/key_bar.ex")
  @screen_frame_path Path.join(@tui_root, "widgets/chrome/screen_frame.ex")
  @screen_paths Path.wildcard(Path.join(@tui_root, "screens/**/*.ex"))

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

  describe "legacy KeyBar compatibility path" do
    test "KeyBar.render production calls are confined to the compatibility module" do
      offenders =
        @tui_root
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.reject(&(&1 == @key_bar_path))
        |> Enum.filter(&(File.read!(&1) =~ "KeyBar.render"))

      assert offenders == []
    end

    test "ScreenFrame composes CommandBar and Normalizer instead of KeyBar" do
      source = File.read!(@screen_frame_path)

      assert source =~ "CommandBar"
      assert source =~ "Normalizer"
      refute source =~ "KeyBar"
    end

    test "KeyBar remains only as a CommandBar delegation adapter" do
      source = File.read!(@key_bar_path)

      assert source =~ "CommandBar.render(theme, Normalizer.commands(keys), opts)"
    end

    test "named screen files call ScreenFrame.render and never KeyBar.render" do
      for path <- @screen_paths do
        source = File.read!(path)

        refute source =~ "KeyBar.render"

        if source =~ "alias Foglet.TUI.Widgets.Chrome.ScreenFrame" do
          assert source =~ "ScreenFrame.render"
        end
      end
    end
  end

  defp group(groups, label) do
    groups
    |> Enum.find(&(&1.label == label))
    |> Map.fetch!(:commands)
    |> Enum.map(&Map.take(&1, [:key, :label, :priority]))
  end
end

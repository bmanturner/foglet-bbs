defmodule Foglet.TUI.Widgets.Chrome.CommandBarTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.CommandBar

  defp theme, do: Theme.default()

  defp command_groups do
    [
      %{
        label: "Actions",
        commands: [
          %{key: "C", label: "Compose", priority: 30},
          %{key: "D", label: "Delete", priority: 50, destructive?: true}
        ]
      },
      %{
        label: "System",
        commands: [
          %{key: "Q", label: "Back", priority: 0}
        ]
      },
      %{
        label: "Navigate",
        commands: [
          %{key: "j/k", label: "Move", priority: 10},
          %{key: "Enter", label: "Open", priority: 10}
        ]
      }
    ]
  end

  describe "render/3" do
    test "renders commands in stable priority order without group labels" do
      flat = CommandBar.render(theme(), command_groups(), width: 120) |> flatten_text()

      refute flat =~ "System"
      refute flat =~ "Actions"
      refute flat =~ "Navigate"
      assert flat =~ "Q Back"
      assert flat =~ "j/k Move"
      assert flat =~ "C Compose"
      assert flat =~ "D Delete"

      assert String.match?(
               flat,
               ~r/Q Back.*j\/k Move.*Enter Open.*C Compose.*D Delete/s
             )
    end

    test "hides the Actions group label but still renders its commands" do
      flat = CommandBar.render(theme(), command_groups(), width: 120) |> flatten_text()

      refute flat =~ "Actions"
      assert flat =~ "C Compose"
      assert flat =~ "D Delete"
    end

    test "drops lower priority commands first under constrained width" do
      flat = CommandBar.render(theme(), command_groups(), width: 44) |> flatten_text()

      assert flat =~ "Q Back"
      assert flat =~ "j/k Move"
      refute flat =~ "D Delete"
      assert TextWidth.display_width(flat) <= 44
    end

    test "retains hidden-label highest-priority command at cramped widths" do
      groups = [
        %{
          label: "Actions",
          commands: [%{key: "C", label: "ComposeLong", priority: 5}]
        }
      ]

      for width <- [5, 8, 10, 12] do
        text = CommandBar.render_text(groups, width: width)

        refute text =~ "Actions",
               "expected hidden Actions label not to render at width #{width}, got: #{inspect(text)}"

        assert String.starts_with?(text, "C "),
               "expected key C to be retained at width #{width}, got: #{inspect(text)}"

        assert TextWidth.display_width(text) <= width
      end
    end

    test "keeps hidden System group hidden under constrained width" do
      groups = [
        %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}
      ]

      text = CommandBar.render_text(groups, width: 6)

      refute text =~ "System"
      assert String.starts_with?(text, "Q ")
      assert TextWidth.display_width(text) <= 6
    end

    test "uses display width truncation for wide glyph labels" do
      groups = [
        %{
          label: "Navigate",
          commands: [
            %{key: "漢字", label: "cafe\u0301 board names", priority: 0},
            %{key: "● ◆", label: "▸ ▾ ✓ × actions", priority: 10}
          ]
        }
      ]

      flat = CommandBar.render(theme(), groups, width: 32) |> flatten_text()

      refute flat =~ "Navigate"
      assert flat =~ "漢字"
      assert TextWidth.display_width(flat) <= 32
    end
  end

  describe "normalize_groups/1" do
    test "accepts maps and defaults missing priorities" do
      groups =
        CommandBar.normalize_groups([
          %{label: "Refresh", commands: [%{key: "R", label: "Refresh"}]}
        ])

      assert [
               %{
                 label: "Refresh",
                 commands: [%{key: "R", label: "Refresh", priority: 50}]
               }
             ] = groups
    end
  end
end

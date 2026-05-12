defmodule Foglet.TUI.LayoutTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Layout

  describe "tier/1" do
    test "classifies shared terminal breakpoints" do
      assert Layout.tier({64, 22}) == :minimum
      assert Layout.tier({79, 24}) == :minimum
      assert Layout.tier({80, 24}) == :standard
      assert Layout.tier({119, 35}) == :standard
      assert Layout.tier({120, 36}) == :enhanced
      assert Layout.tier({131, 50}) == :enhanced
      assert Layout.tier({132, 43}) == :spacious
    end

    test "requires both width and height for enhanced and spacious tiers" do
      assert Layout.tier({120, 35}) == :standard
      assert Layout.tier({119, 36}) == :standard
      assert Layout.tier({132, 42}) == :enhanced
      assert Layout.tier({131, 43}) == :enhanced
    end
  end

  describe "shell primitives" do
    test "left-heavy split preserves the single-pane contract below enhanced" do
      list = %{type: :panel, attrs: %{id: :list}, children: []}
      detail = %{type: :panel, attrs: %{id: :detail}, children: []}

      assert Layout.left_heavy_split(list, detail, terminal_size: {80, 24}) == list
      assert Layout.left_heavy_split(list, detail, terminal_size: {119, 35}) == list
    end

    test "left-heavy split composes both panes at enhanced sizes" do
      list = %{type: :panel, attrs: %{id: :list}, children: []}
      detail = %{type: :panel, attrs: %{id: :detail}, children: []}

      shell = Layout.left_heavy_split(list, detail, terminal_size: {120, 36})

      assert shell.type == :split_pane
      assert shell.attrs.direction == :horizontal
      assert shell.attrs.ratio == {3, 2}
      assert shell.children == [list, detail]
    end

    test "spacious rail only appears at the spacious tier" do
      content = %{type: :panel, attrs: %{id: :content}, children: []}
      rail = %{type: :panel, attrs: %{id: :rail}, children: []}

      assert Layout.spacious_rail(content, rail, terminal_size: {120, 36}) == content

      shell = Layout.spacious_rail(content, rail, terminal_size: {132, 50})
      assert shell.type == :split_pane
      assert shell.children == [content, rail]
    end
  end

  describe "commands_for/2" do
    test "filters focus and mode scoped commands without mutating unscoped commands" do
      groups = [
        %{
          label: "Actions",
          commands: [
            %{key: "Enter", label: "Open", priority: 5, focus: :list},
            %{key: "e", label: "Edit", priority: 5, focus: :detail},
            %{key: "Esc", label: "Back", priority: 0},
            %{key: "s", label: "Save", priority: 5, modes: [:edit]}
          ]
        }
      ]

      [%{commands: commands}] = Layout.commands_for(groups, focus: :list, mode: :browse)

      assert Enum.map(commands, & &1.key) == ["Enter", "Esc"]
    end
  end
end

defmodule Foglet.TUI.Widgets.Input.MenuTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Menu

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      border: %{fg: "#menu-border"},
      primary: %{fg: "#menu-primary"},
      selected: %{fg: "#menu-selected-fg", bg: "#menu-selected-bg"},
      unselected: %{fg: "#menu-unselected"},
      dim: %{fg: "#menu-dim"},
      accent: %{fg: "#menu-accent"}
    }
  end

  # A simple flat menu with an explicit :id for action testing
  defp leaf_menu_state do
    Menu.init(items: [%{id: :file_new, label: "New File", children: []}])
  end

  defp mixed_menu_state do
    Menu.init(
      items: [
        %{id: :boards, glyph: "●", label: "Boards", children: [], shortcut: "B"},
        %{id: :account, glyph: "◇", label: "Account", children: [], meta: "profile"},
        %{id: :disabled, glyph: "×", label: "Disabled", children: [], disabled: true}
      ]
    )
  end

  describe "normalize_items/1" do
    test "test 2 — fills :id when absent" do
      items = Menu.normalize_items([%{label: "File", children: []}])
      [item] = items
      assert Map.has_key?(item, :id)
      assert item.id != nil
    end

    test "test 3 — fills :disabled with false when absent" do
      items = Menu.normalize_items([%{label: "File", children: []}])
      [item] = items
      assert item.disabled == false
    end

    test "test 4 — fills :shortcut with nil when absent" do
      items = Menu.normalize_items([%{label: "File", children: []}])
      [item] = items
      assert item.shortcut == nil
    end

    test "fills visual row fields with nil when absent" do
      [item] = Menu.normalize_items([%{label: "File", children: []}])
      assert item.glyph == nil
      assert item.meta == nil
    end

    test "test 5 — preserves caller-supplied fields" do
      input = [
        %{
          id: :file,
          glyph: "●",
          label: "File",
          meta: "meta",
          children: [],
          disabled: true,
          shortcut: "Ctrl+F"
        }
      ]

      [item] = Menu.normalize_items(input)
      assert item.id == :file
      assert item.glyph == "●"
      assert item.label == "File"
      assert item.meta == "meta"
      assert item.disabled == true
      assert item.shortcut == "Ctrl+F"
    end

    test "test 6 — recurses into children" do
      input = [%{label: "A", children: [%{label: "B", children: []}]}]
      [outer] = Menu.normalize_items(input)
      assert Map.has_key?(outer, :id)
      [inner] = outer.children
      assert Map.has_key?(inner, :id)
    end

    test "WR-03 — auto-generated :id is deterministic across calls" do
      [a1] = Menu.normalize_items([%{label: "New", children: []}])
      [a2] = Menu.normalize_items([%{label: "New", children: []}])
      assert a1.id == a2.id
    end

    test "WR-03 — different labels produce different auto-ids" do
      [a, b] =
        Menu.normalize_items([
          %{label: "New", children: []},
          %{label: "Open", children: []}
        ])

      assert a.id != b.id
    end

    test "WR-03 — nested auto-ids include parent label path" do
      input = [%{label: "File", children: [%{label: "New", children: []}]}]
      [parent] = Menu.normalize_items(input)
      [child] = parent.children
      assert parent.id == "auto:0:File"
      assert child.id == "auto:0:File/0:New"
    end

    test "WR-03 — explicit :id wins over auto-derivation" do
      [item] = Menu.normalize_items([%{id: :explicit, label: "Any", children: []}])
      assert item.id == :explicit
    end

    test "WR-03 — item missing :label raises ArgumentError" do
      assert_raise ArgumentError, ~r/require :label/, fn ->
        Menu.normalize_items([%{children: []}])
      end
    end

    test "WR-03 — id-only item fails during normalization instead of render" do
      assert_raise ArgumentError, ~r/require :label/, fn ->
        Menu.normalize_items([%{id: :id_only, children: []}])
      end
    end

    test "WR-01 — sibling items with duplicate labels get distinct auto-ids" do
      [a, b] =
        Menu.normalize_items([
          %{label: "Open", children: []},
          %{label: "Open", children: []}
        ])

      assert a.id != b.id
      assert a.id == "auto:0:Open"
      assert b.id == "auto:1:Open"
    end

    test "WR-01 — duplicate labels under different parents stay distinct" do
      input = [
        %{
          label: "File",
          children: [%{label: "Delete", children: []}]
        },
        %{
          label: "Edit",
          children: [%{label: "Delete", children: []}]
        }
      ]

      [file, edit] = Menu.normalize_items(input)
      [file_delete] = file.children
      [edit_delete] = edit.children

      assert file_delete.id != edit_delete.id
      assert file_delete.id == "auto:0:File/0:Delete"
      assert edit_delete.id == "auto:1:Edit/0:Delete"
    end

    test "WR-01 — explicit :id on a duplicate-label sibling still wins" do
      [a, b] =
        Menu.normalize_items([
          %{label: "Open", children: []},
          %{id: :explicit_open, label: "Open", children: []}
        ])

      assert a.id == "auto:0:Open"
      assert b.id == :explicit_open
    end
  end

  describe "init/1" do
    test "smoke — init with items missing :id succeeds via normalize_items" do
      state = Menu.init(items: [%{label: "File", children: []}])
      refute is_nil(state)
      assert is_struct(state)
    end

    test "all items have :id after init" do
      state = Menu.init(items: [%{label: "Edit", children: []}, %{label: "View", children: []}])
      items = state.raxol_state.items
      assert Enum.all?(items, &Map.has_key?(&1, :id))
    end
  end

  describe "handle_event/2 (D-14)" do
    test "test 7 — Esc on top-level returns :cancelled" do
      state = leaf_menu_state()
      # open_path is [] at init, so Esc from top-level = :cancelled
      {_new_state, action} = Menu.handle_event(%{key: :escape}, state)
      assert action == :cancelled
    end

    test "test 8 — Enter on leaf returns {:menu_action, id}" do
      state = leaf_menu_state()
      {_new_state, action} = Menu.handle_event(%{key: :enter}, state)
      assert match?({:menu_action, _id}, action)
      {:menu_action, id} = action
      assert id == :file_new
    end

    test "test 9 — purity: same input + event -> same output" do
      state = leaf_menu_state()
      result1 = Menu.handle_event(%{key: :escape}, state)
      result2 = Menu.handle_event(%{key: :escape}, state)
      assert result1 == result2
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "selected, inactive, normal, shortcut, and border states use theme slots" do
      t = distinctive_theme()
      result = Menu.render(mixed_menu_state(), theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.border.fg
      assert serialized =~ t.selected.fg
      assert serialized =~ t.selected.bg
      assert serialized =~ t.unselected.fg
      assert serialized =~ t.dim.fg
      assert serialized =~ t.accent.fg
    end

    test "main menu row shape aligns glyph, label column, metadata, and shortcut" do
      t = distinctive_theme()
      tree = Menu.render(mixed_menu_state(), theme: t)

      assert flatten_text(tree) =~ "● Boards          B"
      assert flatten_text(tree) =~ "◇ Account         profile "
      assert_text_run(tree, "●", fg: t.accent.fg)

      assert_text_run(tree, "Boards          ",
        fg: t.selected.fg,
        bg: t.selected.bg,
        style: [:bold]
      )

      assert Enum.any?(
               Foglet.TUI.WidgetHelpers.text_runs(tree),
               &(Map.get(&1, :content) == "B" and Map.get(&1, :fg) == t.accent.fg and
                   Map.get(&1, :style) == [:bold])
             )

      assert_text_run(tree, "profile ", fg: t.dim.fg)
    end

    test "disabled menu rows use dim styling across glyph, label, and shortcut" do
      t = distinctive_theme()
      tree = Menu.render(mixed_menu_state(), theme: t)

      assert flatten_text(tree) =~ "× Disabled"
      assert_text_run(tree, "×", fg: t.dim.fg, style: [:dim])
      assert_text_run(tree, "Disabled        ", fg: t.dim.fg, style: [:dim])
    end

    test "render no longer emits empty sentinel color nodes" do
      tree = Menu.render(leaf_menu_state(), theme: distinctive_theme())

      refute Enum.any?(Foglet.TUI.WidgetHelpers.text_runs(tree), &(Map.get(&1, :content) == ""))
    end

    test "test 10 — no hardcoded color atoms in rendered tree" do
      state = leaf_menu_state()
      result = Menu.render(state, theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Menu leaked :#{color} atom in serialized tree"
      end
    end

    test "alt-theme produces different rendered output" do
      state = leaf_menu_state()
      default_result = Menu.render(state, theme: theme())
      danger_result = Menu.render(state, theme: alt_theme())

      refute inspect(default_result, printable_limit: :infinity, limit: :infinity) ==
               inspect(danger_result, printable_limit: :infinity, limit: :infinity)
    end

    test "smoke — rendered output contains item label" do
      state = leaf_menu_state()
      result = Menu.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "New File"
    end

    test "WR-01 — rendered output includes opened submenu children" do
      state =
        Menu.init(
          items: [
            %{
              id: :file,
              label: "File",
              children: [
                %{id: :new, label: "New", children: []}
              ]
            }
          ]
        )

      opened = %{state | raxol_state: %{state.raxol_state | open_path: [:file], cursor: :new}}
      result = Menu.render(opened, theme: theme())
      flat = flatten_text(result)

      assert flat =~ "File"
      assert flat =~ "New"
    end
  end
end

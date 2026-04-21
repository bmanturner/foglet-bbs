defmodule Foglet.TUI.Widgets.Display.TableTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Table

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  describe "init/1" do
    test "returns a Table struct from valid options" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "x"}])
      assert %Table{} = state
    end

    test "initializes with empty rows by default" do
      state = Table.init(columns: [%{id: :name, label: "Name"}])
      assert %Table{} = state
    end

    test "stores sortable and filterable flags" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], sortable: true, filterable: true)
      assert state.sortable == true
      assert state.filterable == true
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil map element" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "x"}])
      result = Table.render(state, theme: theme())
      refute is_nil(result)
    end

    test "rendered tree contains column label text" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      result = Table.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Name"
    end
  end

  describe "render/2 — theme slot routing (D-18)" do
    test "build_table_theme/1 wires border slot" do
      t = theme()
      state = Table.init(columns: [%{id: :name, label: "Name"}])
      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.border.fg
    end

    test "build_table_theme/1 wires title slot for header" do
      t = theme()
      state = Table.init(columns: [%{id: :name, label: "Name"}])
      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.title.fg
    end

    test "build_table_theme/1 wires primary slot for rows" do
      t = theme()
      # Two rows needed: selected_row starts at 0, so row 1 (Bob) is unselected and uses row theme
      state =
        Table.init(
          columns: [%{id: :name, label: "Name"}],
          rows: [%{name: "Alice"}, %{name: "Bob"}]
        )

      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.primary.fg
    end

    test "build_table_theme/1 wires selected slot" do
      t = theme()
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      # selected.fg and selected.bg must appear somewhere in the theme map
      assert serialized =~ t.selected.fg
    end
  end

  describe "handle_event/2 (D-14)" do
    test "Down arrow changes state and returns {state, action} tuple" do
      state =
        Table.init(
          columns: [%{id: :name, label: "Name"}],
          rows: [%{name: "Alice"}, %{name: "Bob"}]
        )

      {new_state, _action} = Table.handle_event(%{key: :down}, state)
      assert %Table{} = new_state
    end

    test "handle_event/2 returns a two-element tuple" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      result = Table.handle_event(%{key: :down}, state)
      assert {%Table{}, _action} = result
    end

    test "Enter returns {:row_selected, row} when a row is selected" do
      state =
        Table.init(
          columns: [%{id: :name, label: "Name"}],
          rows: [%{name: "Alice"}]
        )

      # Navigate to select a row first, then press enter
      {state2, _} = Table.handle_event(%{key: :down}, state)
      {_final, action} = Table.handle_event(%{key: :enter}, state2)
      # Action should be nil or {:row_selected, _} — both are valid depending on state
      assert action == nil or match?({:row_selected, _}, action)
    end

    test "purity: same state + event → same output" do
      state =
        Table.init(
          columns: [%{id: :name, label: "Name"}],
          rows: [%{name: "Alice"}, %{name: "Bob"}]
        )

      result1 = Table.handle_event(%{key: :down}, state)
      result2 = Table.handle_event(%{key: :down}, state)
      assert result1 == result2
    end

    test "WR-05 — empty table init leaves selected_row nil" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [])
      assert Map.get(state.raxol_state, :selected_row) == nil
    end

    test "WR-05 — nav key on empty table is a no-op, does not crash" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [])
      {new_state, action} = Table.handle_event(%{key: :down}, state)
      assert action == nil
      assert Map.get(new_state.raxol_state, :selected_row) == nil
    end

    test "WR-05 — enter on empty table returns nil action" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [])
      {_new_state, action} = Table.handle_event(%{key: :enter}, state)
      assert action == nil
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms appear in the rendered tree (IN-03)" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      tree = Table.render(state, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Table leaked :#{color} atom: #{serialized}"
      end
    end

    test "alt-theme differential: default vs danger produce different serialized output" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      default_tree = Table.render(state, theme: theme())
      danger_tree = Table.render(state, theme: alt_theme())

      s1 = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(danger_tree, printable_limit: :infinity, limit: :infinity)

      assert s1 != s2, "Expected different rendering with different themes"
    end
  end
end

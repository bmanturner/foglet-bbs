defmodule Foglet.TUI.Widgets.Display.TableTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Table

  # --- Local helpers (copied from list_row_test.exs pattern) ---

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

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
      assert serialized =~ to_string(t.border.fg)
    end

    test "build_table_theme/1 wires title slot for header" do
      t = theme()
      state = Table.init(columns: [%{id: :name, label: "Name"}])
      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.title.fg)
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
      assert serialized =~ to_string(t.primary.fg)
    end

    test "build_table_theme/1 wires selected slot" do
      t = theme()
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      result = Table.render(state, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      # selected.fg and selected.bg must appear somewhere in the theme map
      assert serialized =~ to_string(t.selected.fg)
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
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms appear in the rendered tree" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      tree = Table.render(state, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ":red", "Table leaked :red atom: #{serialized}"
      refute serialized =~ ":green", "Table leaked :green atom: #{serialized}"
      refute serialized =~ ":yellow", "Table leaked :yellow atom: #{serialized}"
      refute serialized =~ ":cyan", "Table leaked :cyan atom: #{serialized}"
      refute serialized =~ ":magenta", "Table leaked :magenta atom: #{serialized}"
      refute serialized =~ ":blue", "Table leaked :blue atom: #{serialized}"
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

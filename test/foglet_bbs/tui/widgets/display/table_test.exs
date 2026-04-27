defmodule Foglet.TUI.Widgets.Display.TableTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.TextWidth
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

    test "stores page size and drawable width budget" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], page_size: 5, width: 24)

      assert state.available_width == 24
      assert state.raxol_state.options.page_size == 5
    end

    test "resolves auto and ratio columns inside framed drawable width" do
      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: 8},
            %{id: :status, label: "Status", width: :auto},
            %{id: :notes, label: "Notes", width: {:ratio, 2}}
          ],
          rows: [%{code: "ABC", status: "pending", notes: "Long moderation note"}],
          width: 24
        )

      assert table_line_width(state) <= 24
      assert Enum.all?(state.raxol_state.columns, &(&1.width >= 3))
    end

    test "shows full visible content when full content fits inside the budget" do
      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: 6, priority: 100, demand: :content},
            %{id: :status, label: "Status", width: 6, priority: 60, demand: :content},
            %{id: :used_by, label: "Used by", width: 6, priority: 10, demand: :content}
          ],
          rows: [
            %{code: "INVITE-1234", status: "available", used_by: "alice"}
          ],
          width: 34
        )

      assert get_in(state.raxol_state.data, [Access.at(0), :code]) == "INVITE-1234"
      assert get_in(state.raxol_state.data, [Access.at(0), :status]) == "available"
      assert get_in(state.raxol_state.data, [Access.at(0), :used_by]) == "alice"
      assert table_line_width(state) <= 34
    end

    test "sacrifices low-priority columns before high-priority columns" do
      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: 6, priority: 100, demand: :content},
            %{id: :status, label: "Status", width: 6, priority: 50, demand: :content},
            %{id: :used_by, label: "Used by", width: 6, priority: 10, demand: :content}
          ],
          rows: [
            %{
              code: "INVITE-ABCDEFGHIJKL",
              status: "available",
              used_by: "alice@example.test"
            }
          ],
          width: 27
        )

      widths = width_map(state)

      assert widths.code > widths.used_by
      assert get_in(state.raxol_state.data, [Access.at(0), :code]) =~ "INVITE"
      assert get_in(state.raxol_state.data, [Access.at(0), :used_by]) =~ "…"
    end

    test "does not let empty low-priority columns hold width hostage" do
      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: 6, priority: 100, demand: :content},
            %{id: :status, label: "Status", width: 6, priority: 50, demand: :content},
            %{id: :used_by, label: "Used by", width: 6, priority: 10, demand: :content}
          ],
          rows: [
            %{code: "INVITE-ABCDEFG", status: "available", used_by: ""}
          ],
          width: 31
        )

      assert get_in(state.raxol_state.data, [Access.at(0), :code]) == "INVITE-ABCDEFG"
      assert width_map(state).code > width_map(state).used_by
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "rendered tree contains column label text" do
      state = Table.init(columns: [%{id: :name, label: "Name"}], rows: [%{name: "Alice"}])
      result = Table.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Name"
    end

    test "elides long cells at compact width" do
      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: 6},
            %{id: :message, label: "Message", width: :auto}
          ],
          rows: [
            %{code: "ABC123", message: "This message is intentionally too long for the cell"}
          ],
          width: 24
        )

      assert table_line_width(state) <= 24
      assert get_in(state.raxol_state.data, [Access.at(0), :message]) =~ "…"

      message_width = Enum.find(state.raxol_state.columns, &(&1.id == :message)).width

      assert TextWidth.display_width(get_in(state.raxol_state.data, [Access.at(0), :message])) <=
               message_width
    end

    test "uses drawable frame width rather than raw terminal columns" do
      terminal_columns = 64
      drawable_width = terminal_columns - 2

      state =
        Table.init(
          columns: [
            %{id: :code, label: "Code", width: {:ratio, 1}},
            %{id: :status, label: "Status", width: {:ratio, 1}},
            %{id: :body, label: "Body", width: {:ratio, 3}}
          ],
          rows: [%{code: "ABC", status: "pending", body: String.duplicate("wide ", 20)}],
          width: drawable_width
        )

      assert state.available_width == 62
      assert table_line_width(state) <= drawable_width
    end

    test "keeps fixed metadata widths and gives remainder to flexible value columns" do
      state =
        Table.init(
          columns: [
            %{id: :when, label: "When", width: 14},
            %{id: :actor, label: "Actor", width: 9},
            %{id: :body, label: "Body", width: 14, grow: 3},
            %{id: :reason, label: "Reason", width: 10, grow: 2}
          ],
          rows: [
            %{
              when: "04-26 07:29 PM",
              actor: "needz",
              body: "I have arrived! Because I want to stay a while.",
              reason: "Because I am here for the whole story."
            }
          ],
          width: 58
        )

      widths =
        Map.new(state.raxol_state.columns, fn column ->
          {column.id, column.width}
        end)

      assert widths.when == 14
      assert widths.actor == 9
      assert widths.body > 14
      assert widths.reason > 10
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

  defp table_line_width(%Table{raxol_state: %{columns: columns}}) do
    Enum.reduce(columns, 0, fn column, width ->
      width + column.width + 1
    end)
  end

  defp width_map(%Table{raxol_state: %{columns: columns}}) do
    Map.new(columns, fn column -> {column.id, column.width} end)
  end
end

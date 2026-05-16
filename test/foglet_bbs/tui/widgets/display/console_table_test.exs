defmodule Foglet.TUI.Widgets.Display.ConsoleTableTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [color_atom_leaked?: 2, color_names: 0, flatten_text: 1]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ConsoleTable

  setup do
    %{theme: Theme.default()}
  end

  describe "render/2 dense operator fixtures" do
    test "renders moderation log rows", %{theme: theme} do
      assert_table_text(
        moderation_log_rows(),
        [:timestamp, :moderator, :target, :reason],
        theme,
        [
          "hide_oneliner",
          "alice"
        ]
      )
    end

    test "renders moderation user and board rows", %{theme: theme} do
      assert_table_text(moderation_user_rows(), [:handle, :role, :status], theme, [
        "alice",
        "pending"
      ])

      assert_table_text(moderation_board_rows(), [:name, :slug, :category, :scope], theme, [
        "general",
        "mods_only"
      ])
    end

    test "renders SSH key, invite, sysop user, and sysop board rows", %{theme: theme} do
      assert_table_text(
        ssh_key_rows(),
        [:label, :fingerprint, :inserted_at, :last_used_at],
        theme,
        [
          "SHA256:abc"
        ]
      )

      assert_table_text(invite_rows(), [:code, :status, :issuer_id, :inserted_at], theme, [
        "INVITE1",
        "pending"
      ])

      assert_table_text(sysop_user_rows(), [:status, :handle, :email], theme, ["alice"])

      assert_table_text(sysop_board_rows(), [:category, :slug, :name, :posting], theme, [
        "general"
      ])
    end

    test "renders caller-provided empty state", %{theme: theme} do
      state = ConsoleTable.init(columns: columns([:handle]), rows: [], empty_state: "No rows.")

      assert state.empty_state == "No rows."
      assert ConsoleTable.render(state, theme: theme) |> flatten_text() == "No rows."
    end

    test "passes framed drawable width into Display.Table", %{theme: theme} do
      terminal_columns = 64
      drawable_width = terminal_columns - 2

      state =
        ConsoleTable.init(
          columns: columns([:code, :status, :inserted_at, :used_by]),
          rows: [
            %{
              code: "INVITE-CODE-LONG",
              status: "available",
              inserted_at: "2026-04-26 12:00",
              used_by: "not consumed"
            }
          ],
          width: drawable_width
        )

      flat = ConsoleTable.render(state, theme: theme) |> flatten_text()

      assert state.width == 62
      assert state.table.available_width == 62
      assert table_line_width(state) <= drawable_width
      assert flat =~ "Code"
      assert flat =~ "Status"
      assert flat =~ "Inserted at"
      assert flat =~ "Used by"
      assert flat =~ ~r/Code\s+Status\s+Inserted at\s+Used by/
    end

    test "keeps invite columns separated at compact width", %{theme: theme} do
      state =
        ConsoleTable.init(
          columns: [
            %{key: :code, label: "Code", width: 8, priority: 100, demand: :content},
            %{key: :status, label: "Status", width: 8, priority: 60, demand: :content},
            %{key: :inserted_at, label: "Created", width: 10, priority: 40, demand: :content},
            %{key: :used_by, label: "Used by", width: 7, priority: 10, demand: :content}
          ],
          rows: [
            %{
              code: "INVITE1",
              status: "available",
              inserted_at: "2026-04-26 12:00",
              used_by: ""
            }
          ],
          width: 52
        )

      flat = ConsoleTable.render(state, theme: theme) |> flatten_text()

      assert table_line_width(state) <= 52
      assert flat =~ ~r/Code\s+Status\s+Created\s+Used by/
      assert flat =~ "INVITE1"
    end

    test "shows full invite codes when visible values fit and low-value columns are empty",
         %{theme: theme} do
      state =
        ConsoleTable.init(
          columns: [
            %{key: :code, label: "Code", width: 8, priority: 100, demand: :content},
            %{key: :status, label: "Status", width: 8, priority: 60, demand: :content},
            %{key: :created, label: "Created", width: 10, priority: 40, demand: :content},
            %{key: :used_by, label: "Used by", width: 7, priority: 10, demand: :content}
          ],
          rows: [
            %{
              code: "A2TGJQGYMI74JITZAA",
              status: "available",
              created: "2026-04-26",
              used_by: ""
            }
          ],
          width: 52
        )

      flat = ConsoleTable.render(state, theme: theme) |> flatten_text()

      assert flat =~ "A2TGJQGYMI74JITZAA"
      assert width_map(state).code > width_map(state).used_by
      assert table_line_width(state) <= 52
    end

    test "prioritizes code over used-by when not all invite content fits", %{theme: theme} do
      state =
        ConsoleTable.init(
          columns: [
            %{key: :code, label: "Code", width: 8, priority: 100, demand: :content},
            %{key: :status, label: "Status", width: 8, priority: 60, demand: :content},
            %{key: :created, label: "Created", width: 10, priority: 40, demand: :content},
            %{key: :used_by, label: "Used by", width: 7, priority: 10, demand: :content}
          ],
          rows: [
            %{
              code: "A2TGJQGYMI74JITZAA",
              status: "available",
              created: "2026-04-26",
              used_by: "very-long-handle@example.test"
            }
          ],
          width: 42
        )

      flat = ConsoleTable.render(state, theme: theme) |> flatten_text()

      assert width_map(state).code > width_map(state).used_by
      assert flat =~ "A2TGJQ"
      assert flat =~ "…"
    end

    test "exposes more visible content when surplus width exists", %{theme: theme} do
      columns = [
        %{key: :when, label: "When", width: 14},
        %{key: :actor, label: "Actor", width: 9},
        %{key: :body, label: "Body", width: 14, grow: 3},
        %{key: :reason, label: "Reason", width: 10, grow: 2}
      ]

      rows = [
        %{
          when: "04-26 07:29 PM",
          actor: "needz",
          body: "I have arrived! Because I want to stay a while.",
          reason: "Because I am here for the whole story."
        }
      ]

      narrow =
        ConsoleTable.init(
          columns: columns,
          rows: rows,
          width: 41
        )

      wide =
        ConsoleTable.init(
          columns: columns,
          rows: rows,
          width: 64
        )

      narrow_flat = ConsoleTable.render(narrow, theme: theme) |> flatten_text()
      wide_flat = ConsoleTable.render(wide, theme: theme) |> flatten_text()

      refute narrow_flat =~ "I have arrived! Be"
      assert wide_flat =~ "I have arrived! Be"
      assert wide_flat =~ "Because I a"
    end
  end

  describe "handle_event/2" do
    test "returns selected row action for enter on first row" do
      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: moderation_user_rows(),
          selectable: true
        )

      {new_state, {:row_selected, row}} = ConsoleTable.handle_event(%{key: :enter}, state)

      assert row.handle == "alice"
      assert new_state.last_action == {:row_selected, row}
    end

    test "does not emit row selection when selectable is false" do
      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: moderation_user_rows(),
          selectable: false
        )

      {new_state, action} = ConsoleTable.handle_event(%{key: :enter}, state)

      assert action == nil
      assert new_state.last_action == nil
    end
  end

  describe "state ownership helpers" do
    test "selected_index/2 and selected_row/1 hide nested table state" do
      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: moderation_user_rows(),
          selectable: true
        )

      assert ConsoleTable.selected_index(state, 0) == 0
      assert ConsoleTable.selected_row(state).handle == "alice"

      empty = ConsoleTable.init(columns: columns([:handle]), rows: [])

      assert ConsoleTable.selected_index(empty, 0) == 0
      assert ConsoleTable.selected_row(empty) == nil
    end

    test "put_selected_index/2 keeps cursor mutation inside widget API" do
      rows = [
        %{handle: "alice", status: "active"},
        %{handle: "bob", status: "pending"}
      ]

      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: rows,
          selectable: true
        )
        |> ConsoleTable.put_selected_index(1)

      assert ConsoleTable.selected_index(state) == 1
      assert ConsoleTable.selected_row(state).handle == "bob"
    end

    test "with_width/2 preserves selection and behavior options" do
      rows = [
        %{handle: "alice", status: "active"},
        %{handle: "bob", status: "pending"}
      ]

      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: rows,
          sortable: true,
          filterable: true,
          selectable: true,
          page_size: 7,
          width: 80
        )
        |> ConsoleTable.put_selected_index(1)

      resized = ConsoleTable.with_width(state, 42)

      assert resized.width == 42
      assert resized.sortable == true
      assert resized.filterable == true
      assert resized.selectable == true
      assert resized.page_size == 7
      assert ConsoleTable.selected_index(resized) == 1
      assert ConsoleTable.selected_row(resized).handle == "bob"
    end

    test "render/2 is idempotent for the same state and input", %{theme: theme} do
      state =
        ConsoleTable.init(
          columns: columns([:handle, :status]),
          rows: moderation_user_rows(),
          selectable: true
        )

      assert ConsoleTable.render(state, theme: theme) ==
               ConsoleTable.render(state, theme: theme)
    end
  end

  describe "theme hygiene" do
    test "does not leak hardcoded terminal color atoms", %{theme: theme} do
      tree =
        moderation_log_rows()
        |> table_state([:timestamp, :moderator, :target, :reason])
        |> ConsoleTable.render(theme: theme)

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "leaked :#{color} atom"
      end
    end
  end

  defp assert_table_text(rows, keys, theme, expected_values) do
    flat =
      rows
      |> table_state(keys)
      |> ConsoleTable.render(theme: theme)
      |> flatten_text()

    for key <- keys do
      assert flat =~ humanize(key)
    end

    for value <- expected_values do
      assert flat =~ value
    end
  end

  defp table_state(rows, keys) do
    ConsoleTable.init(
      columns: columns(keys),
      rows: rows,
      empty_state: "No rows.",
      sortable: true,
      filterable: true,
      selectable: true
    )
  end

  defp columns(keys) do
    Enum.map(keys, &%{key: &1, label: humanize(&1)})
  end

  defp humanize(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp table_line_width(%ConsoleTable{table: %{raxol_state: %{columns: columns}}}) do
    Enum.reduce(columns, 0, fn column, width ->
      width + column.width + 1
    end)
  end

  defp width_map(%ConsoleTable{table: %{raxol_state: %{columns: columns}}}) do
    Map.new(columns, fn column -> {column.id, column.width} end)
  end

  defp moderation_log_rows do
    [
      %{
        timestamp: "2026-04-25 12:00",
        moderator: "alice",
        target: "thread/12",
        reason: "hide_oneliner"
      }
    ]
  end

  defp moderation_user_rows do
    [
      %{handle: "alice", role: "moderator", status: "pending"}
    ]
  end

  defp moderation_board_rows do
    [
      %{name: "General", slug: "general", category: "Main", scope: "mods_only"}
    ]
  end

  defp ssh_key_rows do
    [
      %{
        label: "laptop",
        fingerprint: "SHA256:abc",
        inserted_at: "2026-04-20",
        last_used_at: "never"
      }
    ]
  end

  defp invite_rows do
    [
      %{code: "INVITE1", status: "pending", issuer_id: "42", inserted_at: "2026-04-20"}
    ]
  end

  defp sysop_user_rows do
    [
      %{status: "active", handle: "alice", email: "alice@example.test"}
    ]
  end

  defp sysop_board_rows do
    [
      %{category: "Main", slug: "general", name: "General", posting: "open"}
    ]
  end
end

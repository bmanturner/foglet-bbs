defmodule Foglet.TUI.Screens.Moderation.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Moderation` (D-04, D-10, MODR-01).

  The app stores this struct at `state.screen_state[:moderation]`.

  Tabs (D-10, locked order):
      ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

  The state holds bounded, scope-aware read rows populated by the TUI app.
  Phase 4 appends the shared INVITES tab when runtime invite policy permits
  moderators to generate codes.

  Per-tab ConsoleTable structs (D-04, D-14, Pitfall 7, Pitfall 9):
    - `log_table`: read-only audit event table (selectable: false)
    - `users_table`: read-only user listing (selectable: false)
    - `boards_table`: read-only board listing (selectable: false)

  Per-tab KvGrid summary lists drive the scope/status header above each table.
  """

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.Input.Tabs

  @base_tabs ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]
  @invites_tab "INVITES"

  @type summary_entry :: %{
          required(:label) => String.t(),
          required(:value) => String.t(),
          optional(:state) => :error | :info
        }

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          tab_labels: [String.t()],
          invites: InvitesState.t(),
          scopes: list(),
          queue: list(),
          mod_log: list(),
          users: list(),
          boards: list(),
          loading?: boolean(),
          error: term(),
          log_table: ConsoleTable.t(),
          users_table: ConsoleTable.t(),
          boards_table: ConsoleTable.t(),
          log_summary: [summary_entry()],
          users_summary: [summary_entry()],
          boards_summary: [summary_entry()]
        }

  defstruct [
    :tabs,
    active_tab: 0,
    tab_labels: @base_tabs,
    invites: nil,
    scopes: [],
    queue: [],
    mod_log: [],
    users: [],
    boards: [],
    loading?: false,
    error: nil,
    log_table: nil,
    users_table: nil,
    boards_table: nil,
    log_summary: [],
    users_summary: [],
    boards_summary: []
  ]

  @doc """
  Builds the ConsoleTable for the LOG tab. Always `selectable: false` (Pitfall 7 — read-only).
  """
  @spec build_log_table([map()]) :: ConsoleTable.t()
  def build_log_table(rows) do
    items =
      Enum.map(rows, fn row ->
        mod_handle = row |> Map.get(:mod) |> field(:handle, "unknown")
        metadata = Map.get(row, :metadata) || %{}

        body = Map.get(metadata, "body") || Map.get(metadata, :body) || ""
        reason = field(row, :reason, "")

        when_label =
          case Map.get(row, :inserted_at) do
            %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
            _ -> ""
          end

        action_label =
          row |> Map.get(:kind) |> to_string()

        %{
          when: when_label,
          actor: truncate(mod_handle, 8),
          action: truncate(action_label, 8),
          body: truncate(body, 13),
          reason: truncate(reason, 9)
        }
      end)

    ConsoleTable.init(
      columns: [
        %{key: :when, label: "When", width: 10},
        %{key: :actor, label: "Actor", width: 9},
        %{key: :action, label: "Action", width: 9},
        %{key: :body, label: "Body", width: 14},
        %{key: :reason, label: "Reason", width: 10}
      ],
      rows: items,
      selectable: false,
      empty_state: "No moderation events in scope."
    )
  end

  @doc """
  Builds the ConsoleTable for the USERS tab. Read-only — no selection-driven domain action.
  """
  @spec build_users_table([map()]) :: ConsoleTable.t()
  def build_users_table(rows) do
    items =
      Enum.map(rows, fn user ->
        %{
          handle: truncate(field(user, :handle, "unknown"), 15),
          role: truncate(to_string(field(user, :role, "user")), 7),
          status: truncate(to_string(field(user, :status, "active")), 11)
        }
      end)

    ConsoleTable.init(
      columns: [
        %{key: :handle, label: "Handle", width: 16},
        %{key: :role, label: "Role", width: 8},
        %{key: :status, label: "Status", width: 12}
      ],
      rows: items,
      selectable: false,
      empty_state: "No active users in scope."
    )
  end

  @doc """
  Builds the ConsoleTable for the BOARDS tab. Read-only — no selection-driven domain action.
  """
  @spec build_boards_table([map()]) :: ConsoleTable.t()
  def build_boards_table(rows) do
    items =
      Enum.map(rows, fn board ->
        %{
          name: truncate(field(board, :name, "unknown"), 17),
          category: truncate(field(board, :category_name, ""), 13),
          state: truncate(to_string(Map.get(board, :state, "active")), 11)
        }
      end)

    ConsoleTable.init(
      columns: [
        %{key: :name, label: "Board", width: 18},
        %{key: :category, label: "Category", width: 14},
        %{key: :state, label: "State", width: 12}
      ],
      rows: items,
      selectable: false,
      empty_state: "No boards in scope."
    )
  end

  @doc """
  Builds the KvGrid summary entries for the LOG tab.
  """
  @spec build_log_summary(list(), term(), list()) :: [summary_entry()]
  def build_log_summary(scopes, error, mod_log) do
    scope_label = format_scopes(scopes)
    count = length(mod_log)

    # Status entry uses :state for badge rendering (required by LOG primitive test)
    status_entry =
      if error do
        %{label: "Status", value: to_string(error), state: :error}
      else
        %{label: "Status", value: "Read-only", state: :info}
      end

    [
      %{label: "Scope", value: scope_label},
      %{label: "Type", value: "hide_oneliner audit log"},
      %{label: "Events", value: Integer.to_string(count)},
      status_entry
    ]
  end

  @doc """
  Builds the KvGrid summary entries for the USERS tab.
  """
  @spec build_users_summary(list(), term()) :: [summary_entry()]
  def build_users_summary(users, error) do
    scope_label = "site"
    active_count = Enum.count(users, fn u -> Map.get(u, :status) in [:active, "active"] end)
    pending = length(users) - active_count

    # Status entry uses :state for badge rendering (required by USERS primitive test)
    status_entry =
      if error do
        %{label: "Status", value: to_string(error), state: :error}
      else
        %{label: "Status", value: "Read-only", state: :info}
      end

    [
      %{label: "Scope", value: scope_label},
      %{label: "Active", value: Integer.to_string(active_count)},
      %{label: "Pending review", value: Integer.to_string(pending)},
      status_entry
    ]
  end

  @doc """
  Builds the KvGrid summary entries for the BOARDS tab.
  """
  @spec build_boards_summary(list(), list(), term()) :: [summary_entry()]
  def build_boards_summary(scopes, boards, error) do
    scope_label = format_scopes(scopes)
    count = length(boards)

    status_value = if error, do: to_string(error), else: "Read-only"

    [
      %{label: "Scope", value: scope_label},
      %{label: "Context", value: "hide_oneliner scope: #{scope_label}"},
      %{label: "Boards", value: Integer.to_string(count)},
      %{label: "Status", value: status_value}
    ]
  end

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    invites? = Keyword.get(opts, :invites_visible?, false)
    active = Keyword.get(opts, :active, 0)
    labels = tab_labels(invites?)
    active = min(active, length(labels) - 1)

    mod_log = Keyword.get(opts, :mod_log, [])
    users = Keyword.get(opts, :users, [])
    boards = Keyword.get(opts, :boards, [])
    scopes = Keyword.get(opts, :scopes, [])
    error = Keyword.get(opts, :error)

    %__MODULE__{
      tabs: Tabs.init(tabs: labels, active: active),
      active_tab: active,
      tab_labels: labels,
      invites: InvitesSurface.default_state(),
      scopes: scopes,
      queue: Keyword.get(opts, :queue, []),
      mod_log: mod_log,
      users: users,
      boards: boards,
      loading?: Keyword.get(opts, :loading?, false),
      error: error,
      log_table: build_log_table(mod_log),
      users_table: build_users_table(users),
      boards_table: build_boards_table(boards),
      log_summary: build_log_summary(scopes, error, mod_log),
      users_summary: build_users_summary(users, error),
      boards_summary: build_boards_summary(scopes, boards, error)
    }
  end

  @spec tab_labels() :: [String.t()]
  def tab_labels, do: @base_tabs

  @spec tab_labels(boolean()) :: [String.t()]
  def tab_labels(true), do: @base_tabs ++ [@invites_tab]
  def tab_labels(false), do: @base_tabs

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_scopes([]), do: "none"
  defp format_scopes(scopes), do: Enum.map_join(scopes, ", ", &format_scope/1)

  defp format_scope(:site), do: "site"
  defp format_scope({:board, board_id}), do: "board:#{board_id}"
  defp format_scope(scope), do: to_string(scope)

  defp field(nil, _key, default), do: default

  defp field(map, key, default) when is_map(map) do
    case Map.get(map, key, default) do
      nil -> default
      value -> to_string(value)
    end
  end

  defp truncate(value, limit) do
    value = to_string(value)

    if String.length(value) > limit do
      String.slice(value, 0, max(limit - 1, 0)) <> "…"
    else
      value
    end
  end
end

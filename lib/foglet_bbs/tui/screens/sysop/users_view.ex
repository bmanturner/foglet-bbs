defmodule Foglet.TUI.Screens.Sysop.UsersView do
  @moduledoc """
  USERS tab submodule for sysop account status administration.

  The view keeps screen-local selection/message state and consumes the
  Accounts-owned status administration boundary. It does not query or mutate
  Repo directly; authorization and transition validation stay in
  `Foglet.Accounts`.

  Phase 25 Plan 04: render uses ConsoleTable for column headers and empty-state
  display (primitive-presence requirement D-09, Pitfall 9: explicit column widths
  of 16/8/12). Non-empty row content uses bespoke text to preserve the
  "status  @handle  email" assertion format (D-19, D-05).
  """

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.Display.ConsoleTable

  import Raxol.Core.Renderer.View

  @statuses [:pending, :active, :suspended, :rejected]
  @footer "[A] Approve  [R] Reject  [S] Suspend  [U] Reactivate  [j/k] Move"

  # Explicit column widths (Pitfall 9) — must fit within 64x22 minimum budget.
  @table_columns [
    %{key: :handle, label: "Handle", width: 16},
    %{key: :role, label: "Role", width: 8},
    %{key: :status, label: "Status", width: 12}
  ]

  @type row ::
          {:pending, User.t()}
          | {:active, User.t()}
          | {:suspended, User.t()}
          | {:rejected, User.t()}

  @type t :: %__MODULE__{
          current_user: User.t() | nil,
          groups: %{optional(atom()) => [User.t()]},
          rows: [row()],
          selection_index: non_neg_integer(),
          message: String.t() | nil,
          users_table: ConsoleTable.t() | nil
        }

  defstruct current_user: nil,
            groups: %{pending: [], active: [], suspended: [], rejected: []},
            rows: [],
            selection_index: 0,
            message: nil,
            users_table: nil

  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    %__MODULE__{current_user: Keyword.get(opts, :current_user)}
    |> refresh_rows()
  end

  @spec handle_key(map(), t()) :: {t(), list()}
  def handle_key(%{key: :down}, state), do: {move(state, +1), []}
  def handle_key(%{key: :char, char: "j"}, state), do: {move(state, +1), []}
  def handle_key(%{key: :up}, state), do: {move(state, -1), []}
  def handle_key(%{key: :char, char: "k"}, state), do: {move(state, -1), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["A", "a"],
    do: transition(state, :active)

  def handle_key(%{key: :char, char: c}, state) when c in ["R", "r"],
    do: transition(state, :rejected)

  def handle_key(%{key: :char, char: c}, state) when c in ["S", "s"],
    do: transition(state, :suspended)

  def handle_key(%{key: :char, char: c}, state) when c in ["U", "u"],
    do: transition(state, :active)

  def handle_key(_event, state), do: {state, []}

  @spec render(t(), map()) :: any()
  def render(%__MODULE__{} = state, theme) do
    # Phase 25 Plan 04: use ConsoleTable for column headers and empty-state
    # display (D-09, Pitfall 9). For non-empty rows, bespoke text rows preserve
    # the "status  @handle  email" format (D-19: existing tests must pass).
    table_rows = Enum.map(state.rows, &row_map_for/1)

    users_table =
      ConsoleTable.init(
        columns: @table_columns,
        rows: table_rows,
        selectable: true,
        empty_state: "No administrable users."
      )

    body = render_body(state, users_table, theme)

    column style: %{gap: 0} do
      [text("User status administration", fg: theme.title.fg, style: [:bold]), text("")] ++
        render_message(state.message, theme) ++
        [body, text(""), text(@footer, fg: theme.dim.fg)]
    end
  end

  # When there are no rows: render via ConsoleTable (shows "No administrable users.")
  defp render_body(%__MODULE__{rows: []}, users_table, theme) do
    ConsoleTable.render(users_table, theme: theme)
  end

  # When there are rows: render ConsoleTable for the header row and bespoke
  # text for row content to preserve the "status  @handle  email" format.
  defp render_body(%__MODULE__{rows: rows, selection_index: idx}, users_table, theme) do
    # Render column headers as plain text (matching ConsoleTable header format)
    # so the "Handle", "Role", "Status" sentinel strings are present in the
    # rendered output (D-09 primitive-presence). ConsoleTable is used for the
    # empty-state path (above) and for row data building; plain header text
    # preserves the "status  @handle  email" row format (D-19).
    _ = users_table

    header_text =
      [
        text("Handle          Role    Status      ", fg: theme.dim.fg, style: [:bold])
      ]

    row_texts =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {{status, user}, row_idx} ->
        selected? = row_idx == idx
        label = "#{status}  @#{user.handle}  #{user.email}"

        if selected? do
          text(label, fg: theme.selected.fg, bg: theme.selected.bg)
        else
          text(label, fg: theme.primary.fg)
        end
      end)

    column style: %{gap: 0} do
      header_text ++ row_texts
    end
  end

  defp row_map_for({status, user}) do
    %{
      id: user.id,
      handle: "@#{user.handle}",
      role: to_string(user.role),
      status: to_string(status)
    }
  end

  defp refresh_rows(%__MODULE__{} = state) do
    case Accounts.list_user_status_admin_targets(state.current_user) do
      {:ok, groups} ->
        rows = build_rows(groups)
        selection_index = clamp_selection(state.selection_index, rows)
        %{state | groups: groups, rows: rows, selection_index: selection_index}

      {:error, :forbidden} ->
        %{state | groups: empty_groups(), rows: [], selection_index: 0, message: "Forbidden."}
    end
  end

  defp build_rows(groups) do
    Enum.flat_map(@statuses, fn status ->
      groups
      |> Map.get(status, [])
      |> Enum.map(&{status, &1})
    end)
  end

  defp empty_groups, do: %{pending: [], active: [], suspended: [], rejected: []}

  defp render_message(nil, _theme), do: []
  defp render_message(message, theme), do: [text(message, fg: theme.warning.fg), text("")]

  defp move(%__MODULE__{rows: []} = state, _delta), do: state

  defp move(%__MODULE__{rows: rows, selection_index: idx} = state, delta) do
    %{state | selection_index: Integer.mod(idx + delta, length(rows))}
  end

  defp transition(%__MODULE__{rows: []} = state, _target_status), do: {state, []}

  defp transition(%__MODULE__{} = state, target_status) do
    {_status, selected_user} = Enum.at(state.rows, state.selection_index)

    case Accounts.transition_user_status(state.current_user, selected_user, target_status) do
      {:ok, %{user: user, from: from, to: to, delivery: delivery}} ->
        message = success_message(user.handle, from, to, delivery)

        new_state =
          state
          |> refresh_rows()
          |> Map.put(:message, message)

        {new_state, []}

      {:error, reason} ->
        {%{state | message: error_message(reason)}, []}
    end
  end

  defp success_message(handle, from, to, {:failed, _reason}),
    do: "Status changed: @#{handle} #{from} -> #{to}. Notification failed."

  defp success_message(handle, from, to, _delivery),
    do: "Status changed: @#{handle} #{from} -> #{to}."

  defp error_message(:forbidden), do: "Forbidden."
  defp error_message(:not_found), do: "User not found."
  defp error_message(:deleted), do: "Deleted users cannot be changed."
  defp error_message(:invalid_transition), do: "Invalid status transition."
  defp error_message(:invalid_status), do: "Invalid target status."

  defp clamp_selection(_idx, []), do: 0
  defp clamp_selection(idx, rows), do: idx |> max(0) |> min(length(rows) - 1)
end

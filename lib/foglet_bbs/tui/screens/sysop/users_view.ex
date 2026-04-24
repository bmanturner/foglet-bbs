defmodule Foglet.TUI.Screens.Sysop.UsersView do
  @moduledoc """
  USERS tab submodule for sysop account status administration.

  The view keeps screen-local selection/message state and consumes the
  Accounts-owned status administration boundary. It does not query or mutate
  Repo directly; authorization and transition validation stay in
  `Foglet.Accounts`.
  """

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}

  import Raxol.Core.Renderer.View

  @statuses [:pending, :active, :suspended, :rejected]
  @footer "[A] Approve  [R] Reject  [S] Suspend  [U] Reactivate  [j/k] Move"

  @type row :: {:pending, User.t()} | {:active, User.t()} | {:suspended, User.t()} | {:rejected, User.t()}

  @type t :: %__MODULE__{
          current_user: User.t() | nil,
          groups: %{optional(atom()) => [User.t()]},
          rows: [row()],
          selection_index: non_neg_integer(),
          message: String.t() | nil
        }

  defstruct current_user: nil,
            groups: %{pending: [], active: [], suspended: [], rejected: []},
            rows: [],
            selection_index: 0,
            message: nil

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
  def handle_key(%{key: :char, char: c}, state) when c in ["A", "a"], do: transition(state, :active)
  def handle_key(%{key: :char, char: c}, state) when c in ["R", "r"], do: transition(state, :rejected)
  def handle_key(%{key: :char, char: c}, state) when c in ["S", "s"], do: transition(state, :suspended)
  def handle_key(%{key: :char, char: c}, state) when c in ["U", "u"], do: transition(state, :active)
  def handle_key(_event, state), do: {state, []}

  @spec render(t(), map()) :: any()
  def render(%__MODULE__{} = state, theme) do
    column style: %{gap: 0} do
      [text("User status administration", fg: theme.title.fg, style: [:bold]), text("")] ++
        render_message(state.message, theme) ++
        [render_rows(state, theme), text(""), text(@footer, fg: theme.dim.fg)]
    end
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

  defp render_rows(%__MODULE__{rows: []}, theme) do
    column style: %{gap: 0} do
      [text("No administrable users.", fg: theme.warning.fg)]
    end
  end

  defp render_rows(%__MODULE__{rows: rows, selection_index: idx}, theme) do
    SelectionList.render(rows, idx, fn {row, _idx, selected?} ->
      render_row(row, selected?, theme)
    end)
  end

  defp render_row({status, user}, selected?, theme) do
    ListRow.render("#{status}  @#{user.handle}  #{user.email}", selected?, theme)
  end

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

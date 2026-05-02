defmodule Foglet.TUI.Screens.Shared.InvitesActions do
  @moduledoc """
  Shared live actions for the INVITES surface.

  This module delegates all invite listing and mutation behavior to
  `Foglet.Accounts`; authorization remains inside the Accounts boundary.
  """

  alias Ecto.Changeset
  alias Foglet.Accounts.{Invites, User}
  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Widgets.Display.ConsoleTable

  @type action_result :: {:ok, InvitesState.t()} | :no_match

  @spec load(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def load(%User{} = actor, %InvitesState{} = state) do
    actor
    |> Invites.list_invites()
    |> handle_list_result(state)
  end

  @spec refresh(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def refresh(%User{} = actor, %InvitesState{} = state), do: load(actor, state)

  @spec generate(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def generate(%User{} = actor, %InvitesState{} = state) do
    case Invites.create_invite(actor) do
      {:ok, invite} ->
        state = InvitesState.with_last_generated(state, invite.code)

        actor
        |> Invites.list_invites()
        |> handle_list_result(state)

      {:error, reason} ->
        {:ok, InvitesState.with_error(state, error_message(reason))}
    end
  end

  @spec revoke_selected(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def revoke_selected(%User{} = actor, %InvitesState{} = state) do
    case InvitesState.selected_item(state) do
      %{code: code} when is_binary(code) ->
        revoke_code(actor, code, state)

      _missing ->
        {:ok, InvitesState.with_error(state, "Select an invite first.")}
    end
  end

  @doc """
  Advances the selection by one row, clamped to the last item.
  Updates both `selected_index` and the ConsoleTable widget cursor.
  """
  @spec select_next(InvitesState.t()) :: InvitesState.t()
  def select_next(%InvitesState{items: items, selected_index: idx} = state) do
    max_idx = max(length(items || []) - 1, 0)
    new_idx = min(idx + 1, max_idx)
    table = state.table || InvitesState.build_table(items || [])
    {new_table, _action} = ConsoleTable.handle_event(%{key: :down}, table)
    %{state | selected_index: new_idx, table: new_table}
  end

  @doc """
  Moves the selection back one row, clamped to the first item.
  Updates both `selected_index` and the ConsoleTable widget cursor.
  """
  @spec select_prev(InvitesState.t()) :: InvitesState.t()
  def select_prev(%InvitesState{items: items, selected_index: idx} = state) do
    new_idx = max(idx - 1, 0)
    table = state.table || InvitesState.build_table(items || [])
    {new_table, _action} = ConsoleTable.handle_event(%{key: :up}, table)
    %{state | selected_index: new_idx, table: new_table}
  end

  @spec handle_key(term(), User.t(), InvitesState.t()) :: action_result()
  def handle_key(key, %User{} = actor, %InvitesState{} = state) when key in ["g", "G"] do
    generate(actor, state)
  end

  def handle_key(key, %User{} = actor, %InvitesState{} = state) when key in ["r", "R"] do
    refresh(actor, state)
  end

  def handle_key(key, %User{} = actor, %InvitesState{} = state) when key in ["d", "D"] do
    revoke_selected(actor, state)
  end

  def handle_key(:down, %User{}, %InvitesState{} = state) do
    {:ok, select_next(state)}
  end

  def handle_key(:up, %User{}, %InvitesState{} = state) do
    {:ok, select_prev(state)}
  end

  def handle_key(_key, %User{}, %InvitesState{}), do: :no_match

  defp revoke_code(actor, code, state) do
    case Invites.revoke_invite(actor, code) do
      {:ok, _invite} ->
        actor
        |> Invites.list_invites()
        |> handle_list_result(state)

      {:error, reason} ->
        {:ok, InvitesState.with_error(state, error_message(reason))}
    end
  end

  defp handle_list_result({:ok, items}, state), do: {:ok, InvitesState.loaded(state, items)}

  defp handle_list_result({:error, reason}, state),
    do: {:ok, InvitesState.with_error(state, error_message(reason))}

  defp error_message(:forbidden), do: "You are not allowed to manage invites."

  defp error_message(:limit_reached),
    do: "Invite limit reached. Revoke an unused invite or ask the sysop."

  defp error_message(:not_found),
    do: "That invite is no longer here. Refresh the list."

  defp error_message(:unavailable),
    do: "That invite has already been used or revoked."

  defp error_message(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> case do
      "" -> "Invite was not saved."
      message -> message
    end
  end
end

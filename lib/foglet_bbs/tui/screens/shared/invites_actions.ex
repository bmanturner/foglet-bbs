defmodule Foglet.TUI.Screens.Shared.InvitesActions do
  @moduledoc """
  Shared live actions for the INVITES surface.

  This module delegates all invite listing and mutation behavior to
  `Foglet.Accounts`; authorization remains inside the Accounts boundary.
  """

  alias Ecto.Changeset
  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.TUI.Screens.Shared.InvitesState

  @type action_result :: {:ok, InvitesState.t()} | :no_match

  @spec load(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def load(%User{} = actor, %InvitesState{} = state) do
    actor
    |> Accounts.list_invites()
    |> handle_list_result(state)
  end

  @spec refresh(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def refresh(%User{} = actor, %InvitesState{} = state), do: load(actor, state)

  @spec generate(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def generate(%User{} = actor, %InvitesState{} = state) do
    case Accounts.create_invite(actor) do
      {:ok, invite} ->
        state = InvitesState.with_last_generated(state, invite.code)

        actor
        |> Accounts.list_invites()
        |> handle_list_result(state)

      {:error, reason} ->
        {:ok, InvitesState.with_error(state, error_message(reason))}
    end
  end

  @spec select_next(InvitesState.t()) :: InvitesState.t()
  def select_next(%InvitesState{} = state), do: InvitesState.select_next(state)

  @spec select_prev(InvitesState.t()) :: InvitesState.t()
  def select_prev(%InvitesState{} = state), do: InvitesState.select_prev(state)

  @spec revoke_selected(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
  def revoke_selected(%User{} = actor, %InvitesState{items: items} = state) when is_list(items) do
    case Enum.at(items, state.selected_index) do
      %{code: code} when is_binary(code) ->
        revoke_code(actor, code, state)

      _missing ->
        {:ok, InvitesState.with_error(state, "No invite is selected.")}
    end
  end

  def revoke_selected(%User{}, %InvitesState{} = state) do
    {:ok, InvitesState.with_error(state, "No invite is selected.")}
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

  def handle_key(:down, %User{}, %InvitesState{} = state), do: {:ok, select_next(state)}
  def handle_key(:up, %User{}, %InvitesState{} = state), do: {:ok, select_prev(state)}
  def handle_key(_key, %User{}, %InvitesState{}), do: :no_match

  defp revoke_code(actor, code, state) do
    case Accounts.revoke_invite(actor, code) do
      {:ok, _invite} ->
        actor
        |> Accounts.list_invites()
        |> handle_list_result(state)

      {:error, reason} ->
        {:ok, InvitesState.with_error(state, error_message(reason))}
    end
  end

  defp handle_list_result({:ok, items}, state), do: {:ok, InvitesState.loaded(state, items)}

  defp handle_list_result({:error, reason}, state),
    do: {:ok, InvitesState.with_error(state, error_message(reason))}

  defp error_message(:forbidden), do: "You are not allowed to manage invites."
  defp error_message(:limit_reached), do: "Invite generation limit reached."
  defp error_message(:not_found), do: "That invite could not be found."
  defp error_message(:unavailable), do: "That invite is already consumed or revoked."

  defp error_message(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> case do
      "" -> "Invite could not be saved."
      message -> message
    end
  end
end

defmodule Foglet.PostingPolicy do
  @moduledoc """
  Shared posting policy checks for thread and post creation.

  The policy is intentionally pure over already-loaded records. Contexts own
  loading persisted users and boards before calling this helper so callers
  cannot spoof active account state or board policy.
  """

  alias Foglet.Accounts.User
  alias Foglet.Authorization
  alias Foglet.Boards.Board

  @doc """
  Returns true when an active, non-deleted user may post on the board.
  """
  @spec can_post?(User.t() | nil, Board.t() | nil) :: boolean()
  def can_post?(%User{status: :active, deleted_at: nil, role: role}, %Board{
        postable_by: postable_by
      }) do
    role_allowed?(role, postable_by)
  end

  def can_post?(_user, _board), do: false

  @doc """
  Returns true when the actor may reply to a locked thread on the board.
  """
  @spec can_bypass_thread_lock?(User.t() | nil, Ecto.UUID.t()) :: boolean()
  def can_bypass_thread_lock?(%User{} = user, board_id) do
    scopes = Authorization.scopes_for(user, :lock_thread)

    :site in scopes or {:board, board_id} in scopes
  end

  def can_bypass_thread_lock?(_user, _board_id), do: false

  defp role_allowed?(role, :members) when role in [:user, :mod, :sysop], do: true
  defp role_allowed?(role, :mods_only) when role in [:mod, :sysop], do: true
  defp role_allowed?(:sysop, :sysop_only), do: true
  defp role_allowed?(_role, _postable_by), do: false
end

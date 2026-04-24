defmodule Foglet.PostingPolicy do
  @moduledoc """
  Shared posting policy checks for thread and post creation.

  The policy is intentionally pure over already-loaded records. Contexts own
  loading persisted users and boards before calling this helper so callers
  cannot spoof active account state or board policy.
  """

  alias Foglet.Accounts.User
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

  defp role_allowed?(role, :members) when role in [:user, :mod, :sysop], do: true
  defp role_allowed?(role, :mods_only) when role in [:mod, :sysop], do: true
  defp role_allowed?(:sysop, :sysop_only), do: true
  defp role_allowed?(_role, _postable_by), do: false
end

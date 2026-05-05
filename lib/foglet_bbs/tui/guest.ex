defmodule Foglet.TUI.Guest do
  @moduledoc """
  Central predicates and denial copy for first-class read-only Guest Mode.

  Guest browsing is explicit: a nil user on the login screen is not a guest
  until the session context carries `guest: true`.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Modal
  alias Foglet.TUI.SessionContext

  @doc "True only for intentional read-only guest browsing state."
  @spec guest?(map() | struct() | nil) :: boolean()
  def guest?(nil), do: false

  def guest?(%{session_context: session_context, current_user: nil}) when is_map(session_context),
    do: SessionContext.guest?(session_context)

  def guest?(%Context{} = context),
    do: is_nil(context.current_user) and SessionContext.guest?(context.session_context)

  def guest?(session_context) when is_map(session_context),
    do: SessionContext.guest?(session_context)

  def guest?(_other), do: false

  @doc "Returns true when the login menu should offer the Guest entry."
  @spec guest_mode_enabled?(map() | nil) :: boolean()
  def guest_mode_enabled?(session_context) when is_map(session_context),
    do: SessionContext.guest_mode_enabled?(session_context)

  def guest_mode_enabled?(_session_context), do: true

  @doc "Marks a session context as an intentional guest session."
  @spec enter(map()) :: %{
          required(:guest) => true,
          required(:user) => nil,
          required(:user_id) => nil,
          optional(any()) => any()
        }
  def enter(session_context) when is_map(session_context) do
    session_context
    |> Map.put(:guest, true)
    |> Map.put(:user, nil)
    |> Map.put(:user_id, nil)
  end

  @doc "Standard denial modal for guest attempts to mutate state or launch doors."
  @spec denial_modal(:chat | :compose | :door | :post | :account | atom()) :: Modal.t()
  def denial_modal(:door) do
    %Modal{type: :error, message: "Only registered users can play door games. Log in first."}
  end

  def denial_modal(:chat) do
    %Modal{
      type: :error,
      message: "Guests can read chat, but only registered users can send messages."
    }
  end

  def denial_modal(:account) do
    %Modal{type: :error, message: "Guest sessions do not have account settings. Log in first."}
  end

  def denial_modal(:board) do
    %Modal{type: :error, message: "That board is for registered users. Log in first."}
  end

  def denial_modal(_kind) do
    %Modal{type: :error, message: "Guests can browse, but only registered users can post."}
  end
end

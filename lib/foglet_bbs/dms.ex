defmodule Foglet.DMs do
  @moduledoc """
  Domain context for classic BBS Mail direct messages.

  DMs are durable two-party messages with recipient read state and per-user
  delete-from-my-view timestamps. They are private to participants in normal UI,
  but are not encrypted at rest; moderation/reporting and retention tooling can
  inspect rows according to site policy.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.DMs.Message
  alias Foglet.Notifications
  alias FogletBbs.Repo

  @preview_max 120

  @type user_ref :: User.t() | Ecto.UUID.t()

  @spec send_message(User.t(), User.t(), map()) ::
          {:ok, Message.t()} | {:error, :cannot_message_self | Ecto.Changeset.t()}
  def send_message(%User{id: same_id}, %User{id: same_id}, _attrs),
    do: {:error, :cannot_message_self}

  def send_message(%User{} = sender, %User{} = recipient, attrs) when is_map(attrs) do
    Repo.transact(fn ->
      with {:ok, message} <-
             %Message{sender_id: sender.id, recipient_id: recipient.id}
             |> Message.create_changeset(attrs)
             |> Repo.insert(),
           {:ok, _notification} <- create_dm_notification(message) do
        {:ok, Repo.preload(message, [:sender, :recipient])}
      end
    end)
  end

  @spec list_conversation(user_ref(), user_ref()) :: [Message.t()]
  def list_conversation(viewer, participant) do
    viewer_id = user_id!(viewer)
    participant_id = user_id!(participant)

    Message
    |> conversation_between(viewer_id, participant_id)
    |> visible_to(viewer_id)
    |> order_by([message], asc: message.inserted_at, asc: message.id)
    |> preload([:sender, :recipient])
    |> Repo.all()
  end

  @spec unread_count(user_ref()) :: non_neg_integer()
  def unread_count(user) do
    user_id = user_id!(user)

    Repo.aggregate(
      from(message in Message,
        where:
          message.recipient_id == ^user_id and is_nil(message.read_at) and
            is_nil(message.deleted_by_recipient_at)
      ),
      :count
    )
  end

  @spec conversation_unread_counts(user_ref()) :: %{Ecto.UUID.t() => non_neg_integer()}
  def conversation_unread_counts(user) do
    user_id = user_id!(user)

    from(message in Message,
      where:
        message.recipient_id == ^user_id and is_nil(message.read_at) and
          is_nil(message.deleted_by_recipient_at),
      group_by: message.sender_id,
      select: {message.sender_id, count(message.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec mark_conversation_read(user_ref(), user_ref()) :: {:ok, non_neg_integer()}
  def mark_conversation_read(viewer, participant) do
    viewer_id = user_id!(viewer)
    participant_id = user_id!(participant)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _rows} =
      Repo.update_all(
        from(message in Message,
          where:
            message.sender_id == ^participant_id and message.recipient_id == ^viewer_id and
              is_nil(message.read_at) and is_nil(message.deleted_by_recipient_at)
        ),
        set: [read_at: now, updated_at: now]
      )

    {:ok, count}
  end

  @spec delete_from_my_view(user_ref(), Message.t() | Ecto.UUID.t()) ::
          {:ok, Message.t()} | {:error, :not_found | :not_participant}
  def delete_from_my_view(viewer, %Message{id: message_id}),
    do: delete_from_my_view(viewer, message_id)

  def delete_from_my_view(viewer, message_id) when is_binary(message_id) do
    viewer_id = user_id!(viewer)

    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{} = message when message.sender_id == viewer_id ->
        soft_delete_for(message, :sender)

      %Message{} = message when message.recipient_id == viewer_id ->
        soft_delete_for(message, :recipient)

      %Message{} ->
        {:error, :not_participant}
    end
  end

  defp soft_delete_for(%Message{} = message, side) when side in [:sender, :recipient] do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    field = if side == :sender, do: :deleted_by_sender_at, else: :deleted_by_recipient_at

    message
    |> Ecto.Changeset.change([{field, now}, {:updated_at, now}])
    |> Repo.update()
  end

  defp create_dm_notification(%Message{} = message) do
    Notifications.create_notification(%{
      kind: :dm,
      user_id: message.recipient_id,
      actor_id: message.sender_id,
      payload: %{message_id: message.id, preview: preview(message.body)},
      dedupe_key: "dm:#{message.id}"
    })
  end

  defp preview(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, @preview_max)
  end

  defp conversation_between(query, left_id, right_id) do
    where(
      query,
      [message],
      (message.sender_id == ^left_id and message.recipient_id == ^right_id) or
        (message.sender_id == ^right_id and message.recipient_id == ^left_id)
    )
  end

  defp visible_to(query, viewer_id) do
    where(
      query,
      [message],
      (message.sender_id == ^viewer_id and is_nil(message.deleted_by_sender_at)) or
        (message.recipient_id == ^viewer_id and is_nil(message.deleted_by_recipient_at))
    )
  end

  defp user_id!(%User{id: user_id}), do: user_id
  defp user_id!(user_id) when is_binary(user_id), do: user_id
end

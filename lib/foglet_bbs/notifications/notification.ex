defmodule Foglet.Notifications.Notification do
  @moduledoc """
  Durable in-BBS notification row.

  `user_id` is the recipient. `actor_id` is optional for system-originated
  events. Payloads are stored as sanitized string-keyed maps so future emitters
  can jump directly to board/thread/post targets without re-parsing text.
  """

  use Foglet.Schema

  @type kind :: :mention | :reply | :dm | :mod_action | :thread_update
  @type t :: %__MODULE__{}

  @kinds [:mention, :reply, :dm, :mod_action, :thread_update]
  @summary_fields ["snippet", "preview", "reason"]
  @summary_max 280

  schema "notifications" do
    field :kind, Ecto.Enum, values: @kinds
    field :payload, :map
    field :read_at, :utc_datetime_usec
    field :dedupe_key, :string

    belongs_to :user, Foglet.Accounts.User
    belongs_to :actor, Foglet.Accounts.User

    timestamps(updated_at: false)
  end

  @doc "Builds a trusted insert/update changeset for notification rows."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:kind, :payload, :read_at, :dedupe_key])
    |> validate_required([:kind, :payload, :user_id])
    |> update_change(:dedupe_key, &normalize_dedupe_key/1)
    |> update_change(:payload, &normalize_payload/1)
    |> validate_payload()
    |> validate_length(:dedupe_key, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:actor_id)
    |> unique_constraint(:dedupe_key, name: :notifications_user_id_dedupe_key_idx)
  end

  defp validate_payload(%Ecto.Changeset{} = changeset) do
    kind = get_field(changeset, :kind)
    payload = get_field(changeset, :payload)

    if valid_payload?(kind, payload) do
      changeset
    else
      add_error(changeset, :payload, "is invalid")
    end
  end

  defp valid_payload?(kind, payload) when is_atom(kind) and is_map(payload) do
    case kind do
      kind when kind in [:mention, :reply] -> valid_post_payload?(payload)
      :dm -> valid_dm_payload?(payload)
      :mod_action -> valid_mod_action_payload?(payload)
      :thread_update -> valid_thread_update_payload?(payload)
      _ -> false
    end
  end

  defp valid_payload?(_, _), do: false

  defp valid_post_payload?(payload) do
    uuid_string?(payload["board_id"]) and
      uuid_string?(payload["thread_id"]) and
      uuid_string?(payload["post_id"]) and
      present_string?(payload["snippet"])
  end

  defp valid_dm_payload?(payload) do
    uuid_string?(payload["message_id"]) and present_string?(payload["preview"])
  end

  defp valid_mod_action_payload?(payload) do
    uuid_string?(payload["action_id"]) and
      present_string?(payload["action_kind"]) and
      present_string?(payload["reason"])
  end

  defp valid_thread_update_payload?(payload) do
    uuid_string?(payload["thread_id"]) and uuid_list?(payload["new_post_ids"])
  end

  defp normalize_payload(payload) when is_map(payload) do
    payload
    |> Enum.into(%{}, fn {key, value} ->
      {to_string(key), normalize_payload_value(to_string(key), value)}
    end)
  end

  defp normalize_payload(payload), do: payload

  defp normalize_payload_value(key, value) when key in @summary_fields and is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, @summary_max)
  end

  defp normalize_payload_value(_key, value) when is_list(value) do
    Enum.map(value, &normalize_nested_value/1)
  end

  defp normalize_payload_value(_key, value), do: normalize_nested_value(value)

  defp normalize_nested_value(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, nested} -> {to_string(key), normalize_nested_value(nested)} end)
  end

  defp normalize_nested_value(value) when is_list(value),
    do: Enum.map(value, &normalize_nested_value/1)

  defp normalize_nested_value(value), do: value

  defp normalize_dedupe_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_dedupe_key(value), do: value

  defp present_string?(value), do: is_binary(value) and value != ""

  defp uuid_list?(values) when is_list(values),
    do: values != [] and Enum.all?(values, &uuid_string?/1)

  defp uuid_list?(_values), do: false

  defp uuid_string?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid_string?(_value), do: false
end

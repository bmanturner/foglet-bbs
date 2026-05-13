defmodule Foglet.SSH.LastCaller do
  @moduledoc "Dual-purpose classic last-callers row and operator/security connection audit."
  use Foglet.Schema

  @interfaces [:ssh, :cli, :telnet]
  @outcomes [:accepted, :denied, :rate_limited, :over_global_limit, :auth_gate_denied, :failed]

  schema "last_callers" do
    field :interface, Ecto.Enum, values: @interfaces
    field :peer_ip, :string
    field :peer_port, :integer
    field :outcome, Ecto.Enum, values: @outcomes
    field :reason, :string
    field :policy_key, :string
    field :session_id, :string
    field :public_visible, :boolean, default: false
    field :occurred_at, :utc_datetime_usec
    field :disconnected_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(caller, attrs) do
    caller
    |> cast(attrs, [
      :interface,
      :peer_ip,
      :peer_port,
      :outcome,
      :reason,
      :policy_key,
      :session_id,
      :public_visible,
      :occurred_at,
      :disconnected_at,
      :metadata
    ])
    |> validate_required([:interface, :outcome, :occurred_at, :public_visible])
    |> validate_number(:peer_port, greater_than_or_equal_to: 0, less_than_or_equal_to: 65_535)
    |> validate_length(:reason, max: 240)
    |> validate_length(:policy_key, max: 120)
    |> validate_length(:session_id, max: 120)
    |> validate_peer_ip()
    |> reject_forbidden_metadata()
  end

  def put_user(changeset, nil), do: changeset
  def put_user(changeset, %{id: id}), do: put_change(changeset, :user_id, id)

  defp validate_peer_ip(changeset) do
    validate_change(changeset, :peer_ip, fn
      :peer_ip, nil ->
        []

      :peer_ip, peer_ip ->
        if Foglet.SSH.AccessRule.valid_address?(peer_ip) and not String.contains?(peer_ip, "/") do
          []
        else
          [peer_ip: "must be an IPv4 or IPv6 address"]
        end
    end)
  end

  defp reject_forbidden_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      keys = metadata |> Map.keys() |> Enum.map(&to_string/1)

      if Enum.any?(
           keys,
           &(&1 in ["password", "public_key", "token", "exception", "post_body", "chat_body"])
         ) do
        [metadata: "must not include auth material, content, tokens, or raw exception payloads"]
      else
        []
      end
    end)
  end
end

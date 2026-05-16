defmodule Foglet.SSH.AccessRule do
  @moduledoc "Durable operator-managed IP allow/deny rule."
  use Foglet.Schema
  import Bitwise, only: [<<<: 2, &&&: 2, bnot: 1]

  @modes [:allow, :deny]

  schema "ssh_access_rules" do
    field :mode, Ecto.Enum, values: @modes
    field :address, :string
    field :enabled, :boolean, default: true
    field :reason, :string
    field :comment, :string

    belongs_to :created_by, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:mode, :address, :enabled, :reason, :comment])
    |> validate_required([:mode, :address, :reason])
    |> validate_length(:reason, max: 240)
    |> validate_length(:comment, max: 1_000)
    |> validate_address()
  end

  def put_created_by(changeset, nil), do: changeset
  def put_created_by(changeset, %{id: id}), do: put_change(changeset, :created_by_id, id)

  def valid_address?(address) when is_binary(address), do: match?({:ok, _}, parse(address))
  def valid_address?(_), do: false

  def matches?(%__MODULE__{address: address}, ip), do: matches?(address, ip)

  def matches?(address, ip) when is_binary(address) do
    with {:ok, parsed} <- parse(address), {:ok, ip_tuple} <- normalize_ip(ip) do
      in_range?(parsed, ip_tuple)
    else
      _ -> false
    end
  end

  def parse(address) when is_binary(address) do
    case String.split(address, "/", parts: 2) do
      [ip] ->
        with {:ok, tuple} <- parse_ip(ip) do
          {:ok, {tuple, address_bit_size(tuple)}}
        end

      [ip, prefix] ->
        with {:ok, tuple} <- parse_ip(ip),
             {prefix_int, ""} <- Integer.parse(prefix),
             true <- prefix_int >= 0 and prefix_int <= address_bit_size(tuple) do
          {:ok, {tuple, prefix_int}}
        else
          _ -> :error
        end
    end
  end

  def parse(_), do: :error

  def normalize_ip(ip) when is_tuple(ip) and tuple_size(ip) in [4, 8], do: {:ok, ip}
  def normalize_ip(ip) when is_binary(ip), do: parse_ip(ip)
  def normalize_ip(_), do: :error

  def ip_to_string(ip) do
    with {:ok, tuple} <- normalize_ip(ip), charlist <- :inet.ntoa(tuple) do
      to_string(charlist)
    end
  end

  defp parse_ip(ip) do
    ip = String.to_charlist(ip)

    case :inet.parse_address(ip) do
      {:ok, tuple} when tuple_size(tuple) in [4, 8] -> {:ok, tuple}
      _ -> :error
    end
  end

  defp validate_address(changeset) do
    validate_change(changeset, :address, fn :address, address ->
      if valid_address?(address), do: [], else: [address: "must be an IPv4/IPv6 address or CIDR"]
    end)
  end

  defp address_bit_size(tuple) when tuple_size(tuple) == 4, do: 32
  defp address_bit_size(tuple) when tuple_size(tuple) == 8, do: 128

  defp in_range?({network, prefix}, ip) when tuple_size(network) == tuple_size(ip) do
    network_int = tuple_to_int(network)
    ip_int = tuple_to_int(ip)
    bits = address_bit_size(network)
    mask = if prefix == 0, do: 0, else: bnot((1 <<< (bits - prefix)) - 1) &&& (1 <<< bits) - 1
    (network_int &&& mask) == (ip_int &&& mask)
  end

  defp in_range?(_, _), do: false

  defp tuple_to_int(tuple) do
    shift = if tuple_size(tuple) == 4, do: 8, else: 16

    tuple
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> (acc <<< shift) + part end)
  end
end

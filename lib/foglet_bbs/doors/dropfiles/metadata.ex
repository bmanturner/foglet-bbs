defmodule Foglet.Doors.Dropfiles.Metadata do
  @moduledoc false

  alias Foglet.Accounts.User
  alias Foglet.Sessions.Session

  defstruct [
    :handle,
    :display_name,
    :location,
    :role,
    :user_id,
    :session_id,
    :terminal_cols,
    :terminal_rows,
    :security_level,
    :time_remaining_minutes,
    :node_number,
    :user_record_number,
    :sysop_first_name,
    :sysop_last_name,
    :sysop_name
  ]

  @type t :: %__MODULE__{}

  @type attrs :: %{
          required(:user) => User.t() | map(),
          required(:session) => Session.t() | map(),
          optional(:sysop_name) => String.t(),
          optional(:time_remaining_minutes) => pos_integer() | String.t(),
          optional(:node_number) => pos_integer() | String.t(),
          optional(atom()) => term()
        }

  @spec from_attrs(attrs()) :: t()
  def from_attrs(%{user: user, session: session} = attrs) do
    {cols, rows} = terminal_size(session)
    role = user_role(user, session)
    [sysop_first_name, sysop_last_name] = sysop_name_parts(Map.get(attrs, :sysop_name))

    %__MODULE__{
      handle: handle(user, session),
      display_name: display_name(user, session),
      location: location(user),
      role: role,
      user_id: user_identifier(user, session),
      session_id: session_identifier(session),
      terminal_cols: cols,
      terminal_rows: rows,
      security_level: security_level(role),
      time_remaining_minutes: time_remaining_minutes(attrs),
      node_number: node_number(attrs, session),
      user_record_number: user_record_number(user, session),
      sysop_first_name: sysop_first_name,
      sysop_last_name: sysop_last_name,
      sysop_name: Enum.join([sysop_first_name, sysop_last_name], " ") |> String.trim()
    }
  end

  defp terminal_size(%Session{terminal_size: {cols, rows}}), do: {cols, rows}
  defp terminal_size(%{terminal_size: {cols, rows}}), do: {cols, rows}
  defp terminal_size(_session), do: {80, 24}

  defp handle(%User{handle: handle}, _session) when is_binary(handle), do: handle
  defp handle(%{handle: handle}, _session) when is_binary(handle), do: handle
  defp handle(_user, %Session{handle: handle}) when is_binary(handle), do: handle
  defp handle(_user, %{handle: handle}) when is_binary(handle), do: handle
  defp handle(_user, _session), do: "guest"

  defp display_name(%User{real_name: real_name}, _session)
       when is_binary(real_name) and real_name != "",
       do: real_name

  defp display_name(%{real_name: real_name}, _session)
       when is_binary(real_name) and real_name != "",
       do: real_name

  defp display_name(user, session), do: user |> handle(session) |> guest_titlecase()

  defp location(%User{location: location}) when is_binary(location), do: location
  defp location(%{location: location}) when is_binary(location), do: location
  defp location(_user), do: ""

  defp user_role(%User{role: role}, _session) when not is_nil(role), do: to_string(role)
  defp user_role(%{role: role}, _session) when not is_nil(role), do: to_string(role)
  defp user_role(_user, %Session{role: role}) when not is_nil(role), do: to_string(role)
  defp user_role(_user, %{role: role}) when not is_nil(role), do: to_string(role)
  defp user_role(_user, _session), do: "user"

  defp user_identifier(%User{id: id}, _session) when is_binary(id), do: id
  defp user_identifier(%{id: id}, _session) when is_binary(id), do: id
  defp user_identifier(_user, %Session{user_id: id}) when is_binary(id), do: id
  defp user_identifier(_user, %{user_id: id}) when is_binary(id), do: id
  defp user_identifier(_user, _session), do: "guest"

  defp user_record_number(user, session) do
    user
    |> user_identifier(session)
    |> numeric_identifier()
  end

  defp numeric_identifier(value) when is_binary(value) do
    case Regex.run(~r/\d+$/, value) do
      [digits] -> positive_integer_string(digits, 0)
      nil -> "0"
    end
  end

  defp session_identifier(%{session_id: id}) when is_binary(id), do: id
  defp session_identifier(_session), do: ""

  defp security_level("sysop"), do: "100"
  defp security_level("mod"), do: "90"
  defp security_level(_role), do: "50"

  defp time_remaining_minutes(attrs) do
    attrs
    |> Map.get(:time_remaining_minutes, 1440)
    |> positive_integer_string(1440)
  end

  defp node_number(attrs, session) do
    value =
      Map.get(attrs, :node_number) || Map.get(session, :node_number) || Map.get(session, :node) ||
        1

    positive_integer_string(value, 1)
  end

  defp positive_integer_string(value, _default) when is_integer(value) and value > 0,
    do: Integer.to_string(value)

  defp positive_integer_string(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> Integer.to_string(int)
      _invalid -> Integer.to_string(default)
    end
  end

  defp positive_integer_string(_value, default), do: Integer.to_string(default)

  defp sysop_name_parts(name) when is_binary(name) do
    name
    |> String.split(" ", parts: 2)
    |> then(&(&1 ++ [""]))
    |> Enum.take(2)
  end

  defp sysop_name_parts(_name), do: ["Foglet", "Sysop"]

  defp guest_titlecase("guest"), do: "Guest"
  defp guest_titlecase(value), do: value
end

defmodule Foglet.TUI.Context do
  @moduledoc """
  Narrow runtime context handed to screens using the Phase 34 screen contract.

  `Foglet.TUI.App` owns broad runtime state. Screens receive this smaller
  value so reducers can read session, route, terminal, and domain override
  data without depending on App-owned screen storage.
  """

  alias Foglet.TUI.SessionContext

  @public_fields [
    :current_user,
    :session_context,
    :session_pid,
    :terminal_size,
    :route,
    :route_params,
    :domain
  ]

  @type route :: atom() | {atom(), map()}
  @type route_params :: map()

  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          session_context: SessionContext.t() | map(),
          session_pid: pid() | nil,
          terminal_size: {pos_integer(), pos_integer()},
          route: route(),
          route_params: route_params(),
          domain: map()
        }

  defstruct current_user: nil,
            session_context: %SessionContext{},
            session_pid: nil,
            terminal_size: {80, 24},
            route: :login,
            route_params: %{},
            domain: %{}

  @doc """
  Builds a screen context from keyword or map attributes.

  Only the public screen-facing fields are accepted. Missing values are filled
  with defaults. If `session_context` contains a `:domain` map, it becomes the
  default domain unless `:domain` is explicitly provided.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)
    unknown = Map.keys(attrs) -- @public_fields

    if unknown != [] do
      raise ArgumentError,
            "unknown Foglet.TUI.Context field(s): #{inspect(Enum.sort(unknown))}"
    end

    session_context = Map.get(attrs, :session_context, %SessionContext{})

    defaults = %{
      current_user: nil,
      session_context: session_context,
      session_pid: nil,
      terminal_size: {80, 24},
      route: :login,
      route_params: %{},
      domain: domain_from_session_context(session_context)
    }

    struct!(__MODULE__, Map.merge(defaults, attrs))
  end

  defp domain_from_session_context(session_context) when is_map(session_context) do
    case Map.get(session_context, :domain) do
      domain when is_map(domain) -> domain
      _ -> %{}
    end
  end

  defp domain_from_session_context(_session_context), do: %{}
end

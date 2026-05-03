defmodule Foglet.Doors.Manifest do
  @moduledoc """
  Validated door manifest for first-slice native/external/classic door registration.

  Manifests are configuration data, not durable database records in this slice.
  The `Foglet.Doors` context validates them before TUI/OTP launch code can list
  or run a door.
  """

  @type runtime :: :native_elixir | :external_pty | :classic_dropfile
  @type visibility :: :members | :mods_only | :sysop_only

  defstruct [
    :id,
    :slug,
    :display_name,
    :description,
    :runtime,
    :command,
    :module,
    :working_dir,
    :timeout_ms,
    :idle_timeout_ms,
    :visibility,
    :auth_scope,
    args: [],
    env: %{},
    env_allowlist: [],
    pty?: true
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          slug: String.t(),
          display_name: String.t(),
          description: String.t(),
          runtime: runtime(),
          command: String.t() | nil,
          module: module() | nil,
          args: [String.t()],
          working_dir: String.t() | nil,
          env: %{String.t() => String.t()},
          env_allowlist: [String.t()],
          timeout_ms: pos_integer(),
          idle_timeout_ms: pos_integer() | nil,
          visibility: visibility(),
          auth_scope: :site | {:board, Ecto.UUID.t()},
          pty?: boolean()
        }
end

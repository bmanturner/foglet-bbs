defmodule Foglet.Doors.Manifest do
  @moduledoc """
  Validated door manifest for first-slice native/external/classic door registration.

  Manifests are configuration data, not durable database records in this slice.
  The `Foglet.Doors` context validates them before TUI/OTP launch code can list
  or run a door.
  """

  defmodule Dropfile do
    @moduledoc """
    Normalized declaration for one classic BBS dropfile Foglet may generate.

    Filenames are fixed by Foglet from the format; manifests can declare the
    compatibility contract but cannot inject arbitrary paths or filenames.
    """

    @type format :: :chain_txt | :door_sys | :door32_sys | :dorinfo_def
    @type identity :: :handle
    @type transport :: :filesystem
    @type encoding :: :cp437 | :utf8
    @type cwd :: :door_working_dir | :session_working_dir
    @type expose_path :: :env | :none

    defstruct [
      :format,
      :filename,
      identity: :handle,
      transport: :filesystem,
      encoding: :cp437,
      cwd: :door_working_dir,
      expose_path: :env,
      raw_keys: []
    ]

    @type t :: %__MODULE__{
            format: format(),
            filename: String.t(),
            identity: identity(),
            transport: transport(),
            encoding: encoding(),
            cwd: cwd(),
            expose_path: expose_path(),
            raw_keys: [atom() | String.t()]
          }
  end

  @type runtime :: :native_elixir | :external_pty | :classic_dropfile
  @type visibility :: :members | :mods_only | :sysop_only
  @type sandbox_mode :: :none | :restricted_user_process_group
  @type process_tree :: :process_group

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
    dropfiles: [],
    dropfile_formats: [],
    env: %{},
    env_allowlist: [],
    pty?: true,
    sandbox: %Foglet.Doors.Sandbox{}
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
          dropfiles: [Dropfile.t()],
          dropfile_formats: [Dropfile.format()],
          working_dir: String.t() | nil,
          env: %{String.t() => String.t()},
          env_allowlist: [String.t()],
          timeout_ms: pos_integer(),
          idle_timeout_ms: pos_integer() | nil,
          visibility: visibility(),
          auth_scope: :site | {:board, Ecto.UUID.t()},
          pty?: boolean(),
          sandbox: Foglet.Doors.Sandbox.t()
        }
end

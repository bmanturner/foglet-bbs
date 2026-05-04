defmodule Foglet.Doors do
  @moduledoc """
  Domain boundary for Door Games registration contracts and launch metadata.

  First slice scope:

    * validates configured/seeded manifests for native, external PTY, and classic
      dropfile doors;
    * exposes actor-aware launch eligibility for callers such as TUI screens;
    * builds redacted audit records for launch/exit events;
    * generates classic dropfiles from Foglet user/session metadata.

  This module does not spawn external processes and does not write durable rows.
  Runtime ownership remains an OTP/SSH integration concern for later slices.
  """

  alias Foglet.Accounts.User
  alias Foglet.Doors.{AuditRecord, Manifest}
  alias Foglet.Sessions.Session

  @runtime_values [:native_elixir, :external_pty, :classic_dropfile]
  @visibility_values [:members, :mods_only, :sysop_only]
  @safe_status_keys [:exit_status, :reason, :signal, :timed_out, :crashed, :disconnected]
  @sensitive_env_names ~w[
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    DATABASE_URL
    ECTO_IPV6
    FOGLET_SECRET_KEY_BASE
    GITHUB_TOKEN
    HEX_API_KEY
    PAPERCLIP_API_KEY
    SECRET_KEY_BASE
  ]

  @default_manifest_attrs [
    %{
      id: "native-hello",
      slug: "native-hello",
      display_name: "Native Hello",
      description: "Tiny in-BEAM demo door that opens, says hello, and returns.",
      runtime: :native_elixir,
      module: Foglet.Doors.Demo.NativeHello,
      timeout_ms: 5_000,
      visibility: :members,
      auth_scope: :site
    }
  ]

  @external_echo_relative_path "doors/demo/external_echo.sh"

  @type manifest_attrs :: map()
  @type validation_error :: {atom(), String.t()}

  @doc """
  Returns first-slice configured door manifests.

  This branch has no persisted game catalog yet, so the visible user path is
  backed by two safe demo manifests: one native in-BEAM door and one allowlisted
  executable under `priv/doors/demo`.
  """
  @spec list_manifests() :: [Manifest.t()]
  def list_manifests do
    @default_manifest_attrs
    |> Kernel.++([external_echo_manifest_attrs()])
    |> Enum.map(&validate_manifest!/1)
  end

  @doc "Returns door manifests the actor may launch."
  @spec list_visible(User.t() | nil) :: [Manifest.t()]
  def list_visible(user) do
    list_manifests()
    |> Enum.filter(&launchable?(user, &1))
  end

  @doc "Looks up one visible door for an actor by id or slug."
  @spec get_visible(User.t() | nil, String.t()) :: {:ok, Manifest.t()} | {:error, :not_found}
  def get_visible(user, id_or_slug) when is_binary(id_or_slug) do
    case Enum.find(list_visible(user), &(&1.id == id_or_slug or &1.slug == id_or_slug)) do
      %Manifest{} = manifest -> {:ok, manifest}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Validate and normalize a door manifest.

  Accepts atom or string keys. This intentionally supports config/seeds without
  adding a database schema for the first slice.
  """
  @spec validate_manifest(manifest_attrs()) ::
          {:ok, Manifest.t()} | {:error, [validation_error()]}
  def validate_manifest(attrs) when is_map(attrs) do
    attrs = atomize_known_keys(attrs)

    manifest = %Manifest{
      id: Map.get(attrs, :id),
      slug: Map.get(attrs, :slug),
      display_name: Map.get(attrs, :display_name),
      description: Map.get(attrs, :description),
      runtime: Map.get(attrs, :runtime),
      command: Map.get(attrs, :command),
      module: Map.get(attrs, :module),
      args: Map.get(attrs, :args, []),
      working_dir: Map.get(attrs, :working_dir),
      env: Map.get(attrs, :env, %{}),
      env_allowlist: Map.get(attrs, :env_allowlist, []),
      timeout_ms: Map.get(attrs, :timeout_ms),
      idle_timeout_ms: Map.get(attrs, :idle_timeout_ms),
      visibility: Map.get(attrs, :visibility, :members),
      auth_scope: Map.get(attrs, :auth_scope, :site),
      pty?: Map.get(attrs, :pty?, true)
    }

    case validate(manifest) do
      [] -> {:ok, manifest}
      errors -> {:error, errors}
    end
  end

  defp validate_manifest!(attrs) do
    case validate_manifest(attrs) do
      {:ok, manifest} ->
        manifest

      {:error, errors} ->
        raise ArgumentError, "invalid built-in door manifest: #{inspect(errors)}"
    end
  end

  defp external_echo_manifest_attrs do
    demo_external_path = priv_path(@external_echo_relative_path)

    %{
      id: "external-echo",
      slug: "external-echo",
      display_name: "External Echo",
      description: "Tiny shell-script door used to verify external executable launch/return.",
      runtime: :external_pty,
      command: demo_external_path,
      working_dir: Path.dirname(demo_external_path),
      timeout_ms: 5_000,
      visibility: :members,
      auth_scope: :site
    }
  end

  defp priv_path(relative_path) do
    case :code.priv_dir(:foglet_bbs) do
      path when is_list(path) ->
        Path.join(List.to_string(path), relative_path)

      {:error, _reason} ->
        Path.expand(Path.join("priv", relative_path))
    end
  end

  @doc """
  Actor-aware launch gate for a validated manifest.

  TUI code may use this as advisory list filtering, but launch execution should
  call it again from the command/runtime boundary before side effects.
  """
  @spec launchable?(User.t() | nil, Manifest.t()) :: boolean()
  def launchable?(nil, _manifest), do: false
  def launchable?(%User{deleted_at: deleted_at}, _manifest) when not is_nil(deleted_at), do: false

  def launchable?(%User{status: status}, _manifest)
      when status in [:pending, :rejected, :suspended],
      do: false

  def launchable?(%User{role: :sysop}, %Manifest{}), do: true

  def launchable?(%User{role: :mod}, %Manifest{visibility: visibility}),
    do: visibility in [:members, :mods_only]

  def launchable?(%User{role: :user}, %Manifest{visibility: :members}), do: true
  def launchable?(_actor, _manifest), do: false

  @doc """
  Build a redacted launch/exit audit record.

  Required input keys:
    * `:manifest` — validated `Foglet.Doors.Manifest`
    * `:user` — `%Foglet.Accounts.User{}` or nil
    * `:session` — `%Foglet.Sessions.Session{}` or nil

  Optional keys are `:env`, `:status`, `:started_at`, and `:ended_at`.
  """
  @spec launch_audit(map()) :: AuditRecord.t()
  def launch_audit(%{manifest: %Manifest{} = manifest} = attrs) do
    user = Map.get(attrs, :user)
    session = Map.get(attrs, :session)
    env = Map.get(attrs, :env, %{})
    status = Map.get(attrs, :status, %{})

    %AuditRecord{
      door_id: manifest.id,
      user_id: user_id(user, session),
      handle: handle(user, session),
      started_at:
        Map.get(attrs, :started_at, DateTime.utc_now() |> DateTime.truncate(:microsecond)),
      ended_at: Map.get(attrs, :ended_at),
      terminal_size: terminal_size(session),
      runtime: manifest.runtime,
      env: redact_env(env, manifest.env_allowlist),
      status: Map.take(status, @safe_status_keys)
    }
  end

  @doc """
  Generate a classic BBS dropfile from Foglet user/session metadata.

  First-slice support implements `:chain_txt` only. The function boundary leaves
  room for `:door_sys` and `:dorinfo_def` without exposing persistence details to
  TUI/SSH callers.
  """
  @spec classic_dropfile(:chain_txt, %{
          required(:user) => User.t(),
          required(:session) => Session.t()
        }) ::
          {:ok, String.t()} | {:error, :unsupported_format}
  def classic_dropfile(:chain_txt, %{user: %User{} = user, session: %Session{} = session}) do
    {cols, rows} = session.terminal_size || {80, 24}

    text =
      [
        dropfile_handle(user, session),
        dropfile_display_name(user, session),
        to_string(cols),
        to_string(rows),
        user_role(user, session),
        user_identifier(user, session)
      ]
      |> Enum.join("\r\n")

    {:ok, text <> "\r\n"}
  end

  def classic_dropfile(_format, _attrs), do: {:error, :unsupported_format}

  defp validate(%Manifest{} = manifest) do
    []
    |> require_binary(:id, manifest.id)
    |> require_binary(:slug, manifest.slug)
    |> require_binary(:display_name, manifest.display_name)
    |> require_binary(:description, manifest.description)
    |> validate_runtime(manifest.runtime)
    |> validate_visibility(manifest.visibility)
    |> validate_absolute_path(:command, manifest.command, command_required?(manifest.runtime))
    |> validate_absolute_path(
      :working_dir,
      manifest.working_dir,
      manifest.runtime in [:external_pty, :classic_dropfile]
    )
    |> validate_string_list(:args, manifest.args)
    |> validate_env_allowlist(manifest.env_allowlist)
    |> validate_timeout(:timeout_ms, manifest.timeout_ms)
    |> validate_optional_timeout(:idle_timeout_ms, manifest.idle_timeout_ms)
    |> validate_auth_scope(manifest.auth_scope)
    |> Enum.reverse()
  end

  defp atomize_known_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
    end)
  rescue
    ArgumentError -> attrs
  end

  defp require_binary(errors, _field, value) when is_binary(value) and value != "", do: errors
  defp require_binary(errors, field, _value), do: [{field, "is required"} | errors]

  defp validate_runtime(errors, runtime) when runtime in @runtime_values, do: errors

  defp validate_runtime(errors, _runtime),
    do: [{:runtime, "must be native_elixir, external_pty, or classic_dropfile"} | errors]

  defp validate_visibility(errors, visibility) when visibility in @visibility_values, do: errors

  defp validate_visibility(errors, _visibility),
    do: [{:visibility, "must be members, mods_only, or sysop_only"} | errors]

  defp validate_absolute_path(errors, _field, nil, false), do: errors
  defp validate_absolute_path(errors, field, nil, true), do: [{field, "is required"} | errors]

  defp validate_absolute_path(errors, _field, value, _required)
       when is_binary(value) and binary_part(value, 0, 1) == "/",
       do: errors

  defp validate_absolute_path(errors, field, _value, _required),
    do: [{field, "must be an absolute path"} | errors]

  defp validate_string_list(errors, field, values) when is_list(values) do
    if Enum.all?(values, &is_binary/1),
      do: errors,
      else: [{field, "must contain strings only"} | errors]
  end

  defp validate_string_list(errors, field, _values), do: [{field, "must be a list"} | errors]

  defp validate_env_allowlist(errors, values) when is_list(values) do
    case Enum.find(values, &unsupported_env_name?/1) do
      nil -> validate_string_list(errors, :env_allowlist, values)
      value -> [{:env_allowlist, "contains unsupported variable #{value}"} | errors]
    end
  end

  defp validate_env_allowlist(errors, _values), do: [{:env_allowlist, "must be a list"} | errors]

  defp validate_timeout(errors, _field, value) when is_integer(value) and value > 0, do: errors

  defp validate_timeout(errors, field, _value),
    do: [{field, "must be a positive integer"} | errors]

  defp validate_optional_timeout(errors, _field, nil), do: errors
  defp validate_optional_timeout(errors, field, value), do: validate_timeout(errors, field, value)

  defp validate_auth_scope(errors, :site), do: errors
  defp validate_auth_scope(errors, {:board, board_id}) when is_binary(board_id), do: errors

  defp validate_auth_scope(errors, _scope),
    do: [{:auth_scope, "must be :site or {:board, board_id}"} | errors]

  defp command_required?(:native_elixir), do: false
  defp command_required?(_runtime), do: true

  defp unsupported_env_name?(value) when is_binary(value) do
    value in @sensitive_env_names or not Regex.match?(~r/\A[A-Z][A-Z0-9_]*\z/, value)
  end

  defp unsupported_env_name?(_value), do: true

  defp redact_env(env, allowlist) when is_map(env) do
    Map.new(env, fn {key, value} ->
      key = to_string(key)
      value = to_string(value)

      if key in allowlist and not unsupported_env_name?(key) do
        {key, value}
      else
        {key, "[REDACTED]"}
      end
    end)
  end

  defp user_id(%User{id: id}, _session), do: id
  defp user_id(_user, %Session{user_id: id}), do: id
  defp user_id(_user, _session), do: nil

  defp handle(%User{handle: handle}, _session), do: handle
  defp handle(_user, %Session{handle: handle}), do: handle
  defp handle(_user, _session), do: nil

  defp terminal_size(%Session{terminal_size: size}), do: size
  defp terminal_size(_session), do: nil

  defp dropfile_handle(%User{handle: handle}, _session) when is_binary(handle), do: handle
  defp dropfile_handle(_user, %Session{handle: handle}) when is_binary(handle), do: handle
  defp dropfile_handle(_user, _session), do: "guest"

  defp dropfile_display_name(%User{real_name: real_name}, _session) when is_binary(real_name),
    do: real_name

  defp dropfile_display_name(user, session),
    do: dropfile_handle(user, session) |> guest_titlecase()

  defp user_role(%User{role: role}, _session) when not is_nil(role), do: to_string(role)
  defp user_role(_user, %Session{role: role}) when not is_nil(role), do: to_string(role)
  defp user_role(_user, _session), do: "user"

  defp user_identifier(%User{id: id}, _session) when is_binary(id), do: id
  defp user_identifier(_user, %Session{user_id: id}) when is_binary(id), do: id
  defp user_identifier(_user, _session), do: "guest"

  defp guest_titlecase("guest"), do: "Guest"
  defp guest_titlecase(value), do: value
end

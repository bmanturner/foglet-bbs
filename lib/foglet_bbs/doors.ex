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
  alias Foglet.Doors.{AuditRecord, Dropfiles, Manifest}
  alias Foglet.Doors.Manifest.Dropfile
  alias Foglet.Doors.Sandbox
  alias Foglet.Sessions.Session

  @runtime_values [:native_elixir, :external_pty, :classic_dropfile]
  @visibility_values [:members, :mods_only, :sysop_only]
  @sandbox_modes [:none, :restricted_user_process_group]
  @process_tree_values [:process_group]
  @safe_status_keys [:exit_status, :reason, :signal, :timed_out, :crashed, :disconnected]
  @classic_dropfile_formats Dropfiles.formats()
  @dropfile_identity_values [:handle]
  @dropfile_transport_values [:filesystem]
  @dropfile_encoding_values [:cp437, :utf8]
  @dropfile_cwd_values [:door_working_dir, :session_working_dir]
  @dropfile_expose_path_values [:env, :none]
  @unsafe_dropfile_keys [:filename, :path, :relative_path, "filename", "path", "relative_path"]
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
  @demo_doors_env "FOGLET_ENABLE_DEMO_DOORS"
  @truthy_env_values ~w[1 true yes]
  @demo_timeout_ms 15 * 60 * 1_000
  @demo_idle_timeout_ms 5 * 60 * 1_000

  @default_manifest_attrs [
    %{
      id: "native-hello",
      slug: "native-hello",
      display_name: "Native Hello",
      description: "Tiny in-BEAM demo door that opens, says hello, and returns.",
      runtime: :native_elixir,
      module: Foglet.Doors.Demo.NativeHello,
      timeout_ms: @demo_timeout_ms,
      idle_timeout_ms: @demo_idle_timeout_ms,
      visibility: :members,
      auth_scope: :site
    }
  ]

  @external_echo_relative_path "doors/demo/external_echo.sh"
  @python_context_relative_path "doors/demo/python_context_demo.py"
  @classic_dropfile_relative_path "doors/demo/classic_dropfile_demo.py"

  @type manifest_attrs :: map()
  @type validation_error :: {atom(), String.t()}

  @doc """
  Returns configured door manifests available to the runtime catalog.

  This branch has no persisted game catalog yet. Built-in demo/test manifests
  are deployment/QA fixtures and are hidden unless `FOGLET_ENABLE_DEMO_DOORS`
  is set to a documented truthy value at runtime.
  """
  @spec list_manifests() :: [Manifest.t()]
  def list_manifests do
    if demo_doors_enabled?() do
      demo_manifest_attrs()
      |> Enum.map(&validate_manifest!/1)
    else
      []
    end
  end

  @doc "Returns true when the deployment env enables built-in demo/test doors."
  @spec demo_doors_enabled?() :: boolean()
  def demo_doors_enabled? do
    @demo_doors_env
    |> System.get_env()
    |> truthy_env_value?()
  end

  @doc "Returns door manifests the actor may launch."
  @spec list_visible(User.t() | nil) :: [Manifest.t()]
  def list_visible(user) do
    list_manifests()
    |> Enum.filter(&launchable?(user, &1))
  end

  @doc "Returns door manifests the actor may browse in the Door Games list."
  @spec list_browsable(User.t() | nil) :: [Manifest.t()]
  def list_browsable(nil) do
    list_manifests()
    |> Enum.filter(&(&1.visibility == :members))
  end

  def list_browsable(user), do: list_visible(user)

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

    dropfiles =
      normalize_dropfiles(Map.get(attrs, :dropfiles), Map.get(attrs, :dropfile_formats, []))

    manifest = %Manifest{
      id: Map.get(attrs, :id),
      slug: Map.get(attrs, :slug),
      display_name: Map.get(attrs, :display_name),
      description: Map.get(attrs, :description),
      runtime: Map.get(attrs, :runtime),
      command: Map.get(attrs, :command),
      module: Map.get(attrs, :module),
      args: Map.get(attrs, :args, []),
      dropfiles: dropfiles,
      dropfile_formats: dropfile_formats(dropfiles),
      working_dir: Map.get(attrs, :working_dir),
      env: Map.get(attrs, :env, %{}),
      env_allowlist: Map.get(attrs, :env_allowlist, []),
      timeout_ms: Map.get(attrs, :timeout_ms),
      idle_timeout_ms: Map.get(attrs, :idle_timeout_ms),
      visibility: Map.get(attrs, :visibility, :members),
      auth_scope: Map.get(attrs, :auth_scope, :site),
      pty?: Map.get(attrs, :pty?, true),
      sandbox: normalize_sandbox(Map.get(attrs, :sandbox, %{}))
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

  defp demo_manifest_attrs do
    @default_manifest_attrs ++
      [
        external_echo_manifest_attrs(),
        python_context_manifest_attrs(),
        classic_dropfile_manifest_attrs()
      ]
  end

  defp truthy_env_value?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @truthy_env_values))
  end

  defp truthy_env_value?(_value), do: false

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
      timeout_ms: @demo_timeout_ms,
      idle_timeout_ms: @demo_idle_timeout_ms,
      visibility: :members,
      auth_scope: :site
    }
  end

  defp python_context_manifest_attrs do
    demo_python_path = priv_path(@python_context_relative_path)

    %{
      id: "python-context-demo",
      slug: "python-context-demo",
      display_name: "Python Context Demo",
      description: "Small Python door that reads Foglet's safe context/env and returns.",
      runtime: :external_pty,
      command: demo_python_path,
      working_dir: Path.dirname(demo_python_path),
      timeout_ms: @demo_timeout_ms,
      idle_timeout_ms: @demo_idle_timeout_ms,
      visibility: :members,
      auth_scope: :site
    }
  end

  defp classic_dropfile_manifest_attrs do
    demo_classic_path = priv_path(@classic_dropfile_relative_path)

    %{
      id: "classic-dropfile-demo",
      slug: "classic-dropfile-demo",
      display_name: "Classic Dropfile Demo",
      description: "Python demo door that reads generated CHAIN.TXT, DOOR.SYS, and DORINFO.DEF.",
      runtime: :classic_dropfile,
      command: demo_classic_path,
      working_dir: Path.dirname(demo_classic_path),
      dropfile_formats: [:chain_txt, :door_sys, :dorinfo_def],
      timeout_ms: @demo_timeout_ms,
      idle_timeout_ms: @demo_idle_timeout_ms,
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
  Generate a classic BBS dropfile from safe Foglet user/session metadata.

  Compatibility wrapper around `Foglet.Doors.Dropfiles.render/2`.
  """
  @spec classic_dropfile(:chain_txt | :door_sys | :door32_sys | :dorinfo_def, %{
          required(:user) => User.t() | map(),
          required(:session) => Session.t() | map()
        }) ::
          {:ok, String.t()} | {:error, :unsupported_format}
  def classic_dropfile(format, attrs), do: Dropfiles.render(format, attrs)

  @doc "Returns the fixed filename Foglet writes for a supported classic dropfile format."
  @spec dropfile_filename(atom()) :: {:ok, String.t()} | {:error, :unsupported_format}
  def dropfile_filename(format), do: Dropfiles.filename(format)

  @doc "Writes requested classic dropfiles to a working directory using fixed safe filenames."
  @spec write_dropfiles(
          [atom()],
          %{required(:user) => User.t() | map(), required(:session) => Session.t() | map()},
          String.t()
        ) ::
          {:ok, %{atom() => String.t()}} | {:error, term()}
  def write_dropfiles(formats, attrs, working_dir),
    do: Dropfiles.write(formats, attrs, working_dir)

  @doc "Builds the safe external-door context map exposed to wrappers and examples."
  @spec adapter_context(Manifest.t(), map(), {pos_integer(), pos_integer()}) :: map()
  def adapter_context(%Manifest{} = manifest, session, {cols, rows}) do
    %{
      door_id: manifest.id,
      user_id: Map.get(session, :user_id),
      handle: Map.get(session, :handle),
      role: Map.get(session, :role),
      session_id: Map.get(session, :session_id),
      terminal_width: cols,
      terminal_height: rows
    }
  end

  @doc "Builds the minimal Foglet environment variables for external/classic adapters."
  @spec adapter_env(Manifest.t(), map(), {pos_integer(), pos_integer()}, String.t(), %{
          optional(atom()) => String.t()
        }) :: %{String.t() => String.t()}
  def adapter_env(
        %Manifest{} = manifest,
        session,
        {cols, rows},
        context_path,
        dropfile_paths \\ %{}
      ) do
    Map.merge(manifest.env, %{
      "FOGLET_DOOR_ID" => manifest.id,
      "FOGLET_USER_ID" => to_env(Map.get(session, :user_id)),
      "FOGLET_USERNAME" => to_env(Map.get(session, :handle)),
      "FOGLET_SESSION_ID" => to_env(Map.get(session, :session_id)),
      "FOGLET_TERMINAL_WIDTH" => Integer.to_string(cols),
      "FOGLET_TERMINAL_HEIGHT" => Integer.to_string(rows),
      "FOGLET_DOOR_CONTEXT" => context_path,
      "FOGLET_DROPFILES" => dropfile_paths |> Map.values() |> Enum.join(":")
    })
  end

  defp normalize_dropfiles(nil, formats), do: normalize_dropfiles_from_formats(formats)
  defp normalize_dropfiles([], formats), do: normalize_dropfiles_from_formats(formats)

  defp normalize_dropfiles(dropfiles, _formats) when is_list(dropfiles) do
    Enum.map(dropfiles, &normalize_dropfile/1)
  end

  defp normalize_dropfiles(dropfiles, _formats), do: dropfiles

  defp normalize_dropfiles_from_formats(formats) when is_list(formats) do
    Enum.map(formats, fn format -> normalize_dropfile(%{format: format}) end)
  end

  defp normalize_dropfiles_from_formats(formats), do: formats

  defp normalize_dropfile(%Dropfile{} = dropfile), do: dropfile

  defp normalize_dropfile(attrs) when is_map(attrs) do
    attrs = atomize_dropfile_keys(attrs)
    format = normalize_dropfile_atom(Map.get(attrs, :format))

    %Dropfile{
      format: format,
      filename: dropfile_name(format),
      identity: normalize_dropfile_atom(Map.get(attrs, :identity, :handle)),
      transport: normalize_dropfile_atom(Map.get(attrs, :transport, :filesystem)),
      encoding: normalize_dropfile_atom(Map.get(attrs, :encoding, :cp437)),
      cwd: normalize_dropfile_atom(Map.get(attrs, :cwd, :door_working_dir)),
      expose_path: normalize_dropfile_atom(Map.get(attrs, :expose_path, :env)),
      raw_keys: Map.keys(attrs)
    }
  end

  defp normalize_dropfile(format), do: normalize_dropfile(%{format: format})

  defp atomize_dropfile_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {key, value}
      when key in ["format", "identity", "transport", "encoding", "cwd", "expose_path"] ->
        {String.to_existing_atom(key), value}

      {key, value} ->
        {key, value}
    end)
  end

  defp normalize_dropfile_atom(value) when is_atom(value), do: value

  defp normalize_dropfile_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp normalize_dropfile_atom(value), do: value

  defp dropfile_name(format) do
    case Dropfiles.filename(format) do
      {:ok, name} -> name
      {:error, :unsupported_format} -> nil
    end
  end

  defp dropfile_formats(dropfiles) when is_list(dropfiles), do: Enum.map(dropfiles, & &1.format)
  defp dropfile_formats(_dropfiles), do: []

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
    |> validate_env(manifest.env)
    |> validate_dropfiles(manifest.runtime, manifest.dropfiles)
    |> validate_env_allowlist(manifest.env_allowlist)
    |> validate_timeout(:timeout_ms, manifest.timeout_ms)
    |> validate_optional_timeout(:idle_timeout_ms, manifest.idle_timeout_ms)
    |> validate_auth_scope(manifest.auth_scope)
    |> validate_sandbox(manifest.runtime, manifest.sandbox)
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

  defp validate_env(errors, env) when is_map(env) do
    case Enum.find(env, fn {key, value} ->
           unsupported_env_name?(to_string(key)) or not is_binary(value)
         end) do
      nil ->
        errors

      {key, value} when not is_binary(value) ->
        [{:env, "contains non-string value for #{key}"} | errors]

      {key, _value} ->
        [{:env, "contains unsupported variable #{key}"} | errors]
    end
  end

  defp validate_env(errors, _env), do: [{:env, "must be a map"} | errors]

  defp validate_dropfiles(errors, :classic_dropfile, []),
    do: [
      {:dropfiles, "classic_dropfile doors must declare at least one dropfile format"} | errors
    ]

  defp validate_dropfiles(errors, :classic_dropfile, dropfiles) when is_list(dropfiles) do
    Enum.reduce(dropfiles, errors, &validate_dropfile/2)
  end

  defp validate_dropfiles(errors, _runtime, []), do: errors

  defp validate_dropfiles(errors, _runtime, dropfiles) when is_list(dropfiles),
    do: Enum.reduce(dropfiles, errors, &validate_dropfile/2)

  defp validate_dropfiles(errors, _runtime, _dropfiles),
    do: [{:dropfiles, "must be a list"} | errors]

  defp validate_dropfile(%Dropfile{} = dropfile, errors) do
    errors
    |> validate_dropfile_raw_keys(dropfile.raw_keys)
    |> validate_dropfile_value(
      :dropfiles,
      dropfile.format,
      @classic_dropfile_formats,
      "contains unsupported format #{inspect(dropfile.format)}"
    )
    |> validate_dropfile_value(
      :dropfile_identity,
      dropfile.identity,
      @dropfile_identity_values,
      "must be handle"
    )
    |> validate_dropfile_value(
      :dropfile_transport,
      dropfile.transport,
      @dropfile_transport_values,
      "must be filesystem"
    )
    |> validate_dropfile_value(
      :dropfile_encoding,
      dropfile.encoding,
      @dropfile_encoding_values,
      "must be cp437 or utf8"
    )
    |> validate_dropfile_value(
      :dropfile_cwd,
      dropfile.cwd,
      @dropfile_cwd_values,
      "must be door_working_dir or session_working_dir"
    )
    |> validate_dropfile_value(
      :dropfile_expose_path,
      dropfile.expose_path,
      @dropfile_expose_path_values,
      "must be env or none"
    )
  end

  defp validate_dropfile(_dropfile, errors), do: [{:dropfiles, "must contain maps"} | errors]

  defp validate_dropfile_raw_keys(errors, keys) do
    if Enum.any?(keys, &(&1 in @unsafe_dropfile_keys)) do
      [{:dropfiles, "must not declare filenames or paths; Foglet uses fixed safe names"} | errors]
    else
      errors
    end
  end

  defp validate_dropfile_value(errors, field, value, allowed, message) do
    if value in allowed do
      errors
    else
      [{field, message} | errors]
    end
  end

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

  defp normalize_sandbox(%Sandbox{} = sandbox), do: sandbox

  defp normalize_sandbox(attrs) when is_map(attrs) do
    attrs = atomize_sandbox_keys(attrs)

    %Sandbox{
      mode: Map.get(attrs, :mode, :none),
      user: Map.get(attrs, :user),
      group: Map.get(attrs, :group),
      process_tree: Map.get(attrs, :process_tree, :process_group),
      fail_closed?: Map.get(attrs, :fail_closed?, Map.get(attrs, :fail_closed, true))
    }
  end

  defp normalize_sandbox(_attrs), do: :invalid

  defp atomize_sandbox_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {"fail_closed", value} ->
        {:fail_closed, value}

      {"fail_closed?", value} ->
        {:fail_closed?, value}

      {key, value} when key in ["mode", "user", "group", "process_tree"] ->
        {String.to_existing_atom(key), value}

      {key, value} ->
        {key, value}
    end)
  end

  defp validate_sandbox(errors, _runtime, %Sandbox{mode: :none}), do: errors

  defp validate_sandbox(errors, :external_pty, %Sandbox{} = sandbox) do
    errors
    |> validate_sandbox_mode(sandbox.mode)
    |> validate_process_tree(sandbox.process_tree)
    |> validate_optional_binary(:sandbox_user, sandbox.user)
    |> validate_optional_binary(:sandbox_group, sandbox.group)
    |> validate_fail_closed(sandbox.fail_closed?)
    |> require_restricted_user(sandbox)
  end

  defp validate_sandbox(errors, _runtime, %Sandbox{} = sandbox) do
    errors = validate_sandbox_mode(errors, sandbox.mode)

    if sandbox.mode == :none do
      errors
    else
      [{:sandbox, "is only supported for external_pty doors"} | errors]
    end
  end

  defp validate_sandbox(errors, _runtime, _sandbox), do: [{:sandbox, "must be a map"} | errors]

  defp validate_sandbox_mode(errors, mode) when mode in @sandbox_modes, do: errors

  defp validate_sandbox_mode(errors, _mode),
    do: [{:sandbox_mode, "must be none or restricted_user_process_group"} | errors]

  defp validate_process_tree(errors, process_tree) when process_tree in @process_tree_values,
    do: errors

  defp validate_process_tree(errors, _process_tree),
    do: [{:sandbox_process_tree, "must be process_group"} | errors]

  defp validate_optional_binary(errors, _field, nil), do: errors

  defp validate_optional_binary(errors, _field, value) when is_binary(value) and value != "",
    do: errors

  defp validate_optional_binary(errors, field, _value),
    do: [{field, "must be a non-empty string"} | errors]

  defp validate_fail_closed(errors, value) when is_boolean(value), do: errors

  defp validate_fail_closed(errors, _value),
    do: [{:sandbox_fail_closed, "must be a boolean"} | errors]

  defp require_restricted_user(errors, %Sandbox{mode: :restricted_user_process_group, user: user})
       when is_binary(user) and user != "",
       do: errors

  defp require_restricted_user(errors, %Sandbox{mode: :restricted_user_process_group}),
    do: [{:sandbox_user, "is required for restricted_user_process_group"} | errors]

  defp require_restricted_user(errors, _sandbox), do: errors

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

  defp to_env(nil), do: ""
  defp to_env(value), do: to_string(value)
end

defmodule Foglet.Doors.Dropfiles do
  @moduledoc """
  Renders and writes classic BBS dropfiles from safe Foglet session metadata.

  The subsystem owns fixed format-to-filename mapping and delegates each file
  layout to a small renderer module. Renderers receive normalized metadata and
  do not read process-global state.
  """

  alias Foglet.Accounts.User
  alias Foglet.Doors.Dropfiles.Metadata
  alias Foglet.Sessions.Session

  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true, persist: true)

  @formats [:chain_txt, :door_sys, :door32_sys, :dorinfo_def]
  @filenames %{
    chain_txt: "CHAIN.TXT",
    door_sys: "DOOR.SYS",
    door32_sys: "DOOR32.SYS",
    dorinfo_def: "DORINFO.DEF"
  }
  @renderers %{
    chain_txt: Foglet.Doors.Dropfiles.ChainTxt,
    door_sys: Foglet.Doors.Dropfiles.DoorSys,
    door32_sys: Foglet.Doors.Dropfiles.Door32Sys,
    dorinfo_def: Foglet.Doors.Dropfiles.DorinfoDef
  }

  @type format :: :chain_txt | :door_sys | :door32_sys | :dorinfo_def
  @type attrs :: %{
          required(:user) => User.t() | map(),
          required(:session) => Session.t() | map(),
          optional(:sysop_name) => String.t(),
          optional(:time_remaining_minutes) => pos_integer() | String.t(),
          optional(:node_number) => pos_integer() | String.t()
        }

  @doc "Returns all dropfile formats Foglet can render."
  @spec formats() :: nonempty_list(format())
  def formats, do: @formats

  @doc "Returns the fixed filename Foglet writes for a supported dropfile format."
  @spec filename(atom()) :: {:ok, String.t()} | {:error, :unsupported_format}
  def filename(format) when format in @formats, do: {:ok, Map.fetch!(@filenames, format)}
  def filename(_format), do: {:error, :unsupported_format}

  @doc "Renders one classic BBS dropfile as CRLF-terminated text."
  @spec render(atom(), attrs()) :: {:ok, String.t()} | {:error, :unsupported_format}
  def render(format, attrs) when format in @formats and is_map(attrs) do
    metadata =
      attrs
      |> Map.put_new(:sysop_name, default_sysop_name())
      |> Metadata.from_attrs()

    text =
      @renderers
      |> Map.fetch!(format)
      |> renderer_lines(metadata)
      |> crlf_lines()

    {:ok, text}
  end

  def render(_format, _attrs), do: {:error, :unsupported_format}

  @doc "Writes requested classic dropfiles to a working directory using fixed safe filenames."
  @spec write([atom()], attrs(), String.t()) :: {:ok, %{atom() => String.t()}} | {:error, term()}
  # sobelow: format names are fixed by @filenames and working_dir comes from the
  # runtime's generated dropfile directory or validated manifest paths, not from
  # remote/user input.
  @sobelow_skip ["Traversal.FileModule"]
  def write(formats, attrs, working_dir) when is_list(formats) and is_binary(working_dir) do
    Enum.reduce_while(formats, {:ok, %{}}, fn format, {:ok, paths} ->
      with {:ok, name} <- filename(format),
           {:ok, text} <- render(format, attrs),
           path <- Path.join(working_dir, name),
           :ok <- File.write(path, text) do
        {:cont, {:ok, Map.put(paths, format, path)}}
      else
        {:error, reason} -> {:halt, {:error, {format, reason}}}
      end
    end)
  end

  defp default_sysop_name, do: System.get_env("FOGLET_BBS_SYSOP_NAME", "Foglet Sysop")

  defp renderer_lines(Foglet.Doors.Dropfiles.ChainTxt, metadata),
    do: Foglet.Doors.Dropfiles.ChainTxt.lines(metadata)

  defp renderer_lines(Foglet.Doors.Dropfiles.DoorSys, metadata),
    do: Foglet.Doors.Dropfiles.DoorSys.lines(metadata)

  defp renderer_lines(Foglet.Doors.Dropfiles.Door32Sys, metadata),
    do: Foglet.Doors.Dropfiles.Door32Sys.lines(metadata)

  defp renderer_lines(Foglet.Doors.Dropfiles.DorinfoDef, metadata),
    do: Foglet.Doors.Dropfiles.DorinfoDef.lines(metadata)

  defp crlf_lines(lines), do: Enum.join(lines, "\r\n") <> "\r\n"
end

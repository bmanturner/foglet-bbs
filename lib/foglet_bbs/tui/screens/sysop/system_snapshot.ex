defmodule Foglet.TUI.Screens.Sysop.SystemSnapshot do
  @moduledoc """
  Read-only SYSTEM tab (SYSO-04, D-20, D-21).

  Snapshot-on-enter plus manual `r` re-sample. No auto-refresh ticker
  (D-20 forbids). Uses only zero-dep BEAM introspection APIs
  (`:erlang.statistics`, `Registry.count/1`,
  `DynamicSupervisor.count_children/1`, `:erlang.system_info/1`,
  `FogletBbs.Repo.config/0`) — see RESEARCH Pattern 7, D-21.
  """

  import Raxol.Core.Renderer.View

  @type snapshot :: %{
          version: String.t(),
          uptime_ms: non_neg_integer(),
          session_count: non_neg_integer(),
          board_count: non_neg_integer(),
          process_count: non_neg_integer(),
          db_pool_size: non_neg_integer()
        }

  @type t :: %__MODULE__{snapshot: snapshot()}

  defstruct [:snapshot]

  @spec init(keyword()) :: t()
  def init(_opts \\ []), do: %__MODULE__{snapshot: take_snapshot()}

  @spec handle_key(map(), t()) :: {t(), [{atom(), any()}]}
  def handle_key(%{key: :char, char: "r"}, state),
    do: {%{state | snapshot: take_snapshot()}, []}

  def handle_key(_event, state), do: {state, []}

  @spec render(t(), map()) :: any()
  def render(%__MODULE__{snapshot: s}, theme) do
    rows = [
      snapshot_row("Version:", s.version, theme),
      snapshot_row("Uptime:", format_uptime(s.uptime_ms), theme),
      snapshot_row("Sessions:", Integer.to_string(s.session_count), theme),
      snapshot_row("Active boards:", Integer.to_string(s.board_count), theme),
      snapshot_row("OTP processes:", Integer.to_string(s.process_count), theme),
      snapshot_row("DB pool size:", Integer.to_string(s.db_pool_size), theme)
    ]

    footer = text("[r] Refresh", fg: theme.dim.fg)

    column style: %{gap: 0} do
      [text("System snapshot", fg: theme.title.fg, style: [:bold]), text("")] ++
        rows ++ [text(""), footer]
    end
  end

  defp snapshot_row(label, value, theme) do
    text("  #{String.pad_trailing(label, 16)}#{value}", fg: theme.primary.fg)
  end

  @spec take_snapshot() :: snapshot()
  defp take_snapshot do
    vsn =
      case :application.get_key(:foglet_bbs, :vsn) do
        {:ok, v} -> to_string(v)
        :undefined -> "unknown"
      end

    {wall_ms, _} = :erlang.statistics(:wall_clock)
    session_count = safe_registry_count(Foglet.Sessions.Registry)
    board_count = safe_dynsup_count(Foglet.Boards.Supervisor)
    process_count = :erlang.system_info(:process_count)
    pool_size = FogletBbs.Repo.config()[:pool_size] || 0

    %{
      version: vsn,
      uptime_ms: wall_ms,
      session_count: session_count,
      board_count: board_count,
      process_count: process_count,
      db_pool_size: pool_size
    }
  end

  defp safe_registry_count(name) do
    Registry.count(name)
  rescue
    ArgumentError -> 0
  end

  defp safe_dynsup_count(name) do
    %{active: a} = DynamicSupervisor.count_children(name)
    a
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @spec format_uptime(non_neg_integer()) :: String.t()
  defp format_uptime(ms) do
    total_sec = div(ms, 1000)
    h = div(total_sec, 3600)
    m = rem(div(total_sec, 60), 60)
    s = rem(total_sec, 60)

    "~2..0B:~2..0B:~2..0B"
    |> :io_lib.format([h, m, s])
    |> IO.iodata_to_binary()
  end
end

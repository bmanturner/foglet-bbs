defmodule Mix.Tasks.Foglet.BoardChat do
  @moduledoc """
  Inspect and adjust a board's chat configuration.

      mix foglet.board_chat show --board BOARD_SLUG
      mix foglet.board_chat enable --board BOARD_SLUG --actor SYSOP_HANDLE
      mix foglet.board_chat disable --board BOARD_SLUG --actor SYSOP_HANDLE
      mix foglet.board_chat set-mode --board BOARD_SLUG --mode ephemeral|permanent --actor SYSOP_HANDLE
      mix foglet.board_chat set-ttl --board BOARD_SLUG --seconds 60..86400 --actor SYSOP_HANDLE

  Operator break-glass tool for the board chat fields described in
  `Foglet.Boards.Board` (`chat_enabled`, `chat_storage_mode`,
  `chat_message_ttl_seconds`).

  All mutations route through `Foglet.Boards.update_board/3` so the sysop
  authorization check, the chat-mode/ttl bounds, and the
  required/default-subscription invariants run identically to the SSH
  sysop flow. `show` is read-only and does not require an actor.

  Mutations against archived boards are refused before the changeset
  runs to keep error output explicit. Settings already at the requested
  value short-circuit with an "unchanged" message instead of a no-op
  changeset round-trip.
  """
  @shortdoc "Inspect and adjust a board's chat configuration"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.MixTaskHelpers

  @switches [board: :string, actor: :string, mode: :string, seconds: :integer]
  @actions ["show", "enable", "disable", "set-mode", "set-ttl"]
  @modes ["ephemeral", "permanent"]
  @ttl_min 60
  @ttl_max 86_400

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())
    action = List.first(positional)
    board_slug = Keyword.get(opts, :board)

    cond do
      action not in @actions ->
        fail("Unknown action.", usage())

      is_nil(board_slug) ->
        fail("Missing required --board flag.", usage())

      action != "show" and is_nil(Keyword.get(opts, :actor)) ->
        fail("Missing required --actor flag.", usage())

      true ->
        dispatch(action, board_slug, opts)
    end
  end

  defp dispatch("show", slug, _opts) do
    board = fetch_board!(slug, allow_archived: true)
    Mix.shell().info(format_settings(board))
  end

  defp dispatch("enable", slug, opts) do
    update_chat(slug, opts, %{chat_enabled: true},
      unchanged_predicate: & &1.chat_enabled,
      success: "Chat enabled for "
    )
  end

  defp dispatch("disable", slug, opts) do
    update_chat(slug, opts, %{chat_enabled: false},
      unchanged_predicate: &(&1.chat_enabled == false),
      success: "Chat disabled for "
    )
  end

  defp dispatch("set-mode", slug, opts) do
    case Keyword.get(opts, :mode) do
      nil ->
        fail("Missing required --mode flag.", usage())

      mode_string when mode_string in @modes ->
        mode = String.to_existing_atom(mode_string)

        update_chat(slug, opts, %{chat_storage_mode: mode},
          unchanged_predicate: &(&1.chat_storage_mode == mode),
          success: "Storage mode set to #{mode_string} for "
        )

      other ->
        fail("Invalid --mode #{inspect(other)}. Must be ephemeral or permanent.", usage())
    end
  end

  defp dispatch("set-ttl", slug, opts) do
    case Keyword.get(opts, :seconds) do
      nil ->
        fail("Missing required --seconds flag.", usage())

      seconds when is_integer(seconds) and seconds >= @ttl_min and seconds <= @ttl_max ->
        update_chat(slug, opts, %{chat_message_ttl_seconds: seconds},
          unchanged_predicate: &(&1.chat_message_ttl_seconds == seconds),
          success: "Ephemeral TTL set to #{seconds}s for "
        )

      seconds ->
        fail(
          "Invalid --seconds #{inspect(seconds)}. Must be between #{@ttl_min} and #{@ttl_max}.",
          usage()
        )
    end
  end

  defp update_chat(slug, opts, attrs, control) do
    board = fetch_board!(slug, allow_archived: false)
    actor = fetch_actor!(Keyword.fetch!(opts, :actor))
    unchanged_predicate = Keyword.fetch!(control, :unchanged_predicate)
    success_prefix = Keyword.fetch!(control, :success)

    if unchanged_predicate.(board) do
      Mix.shell().info("No change: #{slug} already #{describe_attrs(attrs)}.")
    else
      case Boards.update_board(actor, board, attrs) do
        {:ok, updated} ->
          Mix.shell().info(success_prefix <> updated.slug)
          Mix.shell().info(format_settings(updated))

        {:error, :forbidden} ->
          fail("Forbidden: actor is not authorized to update boards.")

        {:error, %Ecto.Changeset{} = changeset} ->
          MixTaskHelpers.fail_changeset("Failed to update #{slug}:", changeset)
      end
    end
  end

  defp fetch_board!(slug, allow_archived: allow_archived) do
    case Boards.get_board_by_slug(slug) do
      nil ->
        fail("Unknown board: #{slug}")

      %Board{archived: true} when not allow_archived ->
        fail("Board #{slug} is archived.")

      %Board{} = board ->
        board
    end
  end

  defp fetch_actor!(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil -> fail("Unknown actor: #{handle}")
      user -> user
    end
  end

  defp format_settings(%Board{} = board) do
    archived = if board.archived, do: " [archived]", else: ""

    """
    #{board.slug}#{archived}
      chat_enabled:             #{board.chat_enabled}
      chat_storage_mode:        #{board.chat_storage_mode}
      chat_message_ttl_seconds: #{board.chat_message_ttl_seconds}
    """
    |> String.trim_trailing()
  end

  defp describe_attrs(%{chat_enabled: true}), do: "has chat enabled"
  defp describe_attrs(%{chat_enabled: false}), do: "has chat disabled"
  defp describe_attrs(%{chat_storage_mode: mode}), do: "uses storage mode #{mode}"
  defp describe_attrs(%{chat_message_ttl_seconds: seconds}), do: "has ttl #{seconds}s"

  @spec fail(String.t()) :: no_return()
  @spec fail(String.t(), String.t() | nil) :: no_return()
  defp fail(message, detail \\ nil), do: MixTaskHelpers.fail(message, detail)

  defp usage do
    """
    Usage:
      mix foglet.board_chat show --board BOARD_SLUG
      mix foglet.board_chat enable --board BOARD_SLUG --actor SYSOP_HANDLE
      mix foglet.board_chat disable --board BOARD_SLUG --actor SYSOP_HANDLE
      mix foglet.board_chat set-mode --board BOARD_SLUG --mode ephemeral|permanent --actor SYSOP_HANDLE
      mix foglet.board_chat set-ttl --board BOARD_SLUG --seconds 60..86400 --actor SYSOP_HANDLE
    """
  end
end

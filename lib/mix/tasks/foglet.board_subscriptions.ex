defmodule Mix.Tasks.Foglet.BoardSubscriptions do
  @moduledoc """
  Inspect and adjust a user's board subscriptions.

      mix foglet.board_subscriptions list --user HANDLE_OR_EMAIL
      mix foglet.board_subscriptions subscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG
      mix foglet.board_subscriptions unsubscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG

  This is an operator break-glass tool. Mutations route through
  `Foglet.Boards` so required-subscription and archived-board rules match the
  SSH terminal flow.
  """
  @shortdoc "Inspect and adjust board subscriptions"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.MixTaskHelpers

  @switches [user: :string, board: :string]
  @actions ["list", "subscribe", "unsubscribe"]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = parse_args(args)
    action = List.first(positional)
    user_identifier = Keyword.get(opts, :user)
    board_slug = Keyword.get(opts, :board)

    cond do
      action not in @actions ->
        fail("Unknown action.", usage())

      is_nil(user_identifier) ->
        fail("Missing required --user flag.", usage())

      action in ["subscribe", "unsubscribe"] and is_nil(board_slug) ->
        fail("Missing required --board flag.", usage())

      true ->
        dispatch(action, user_identifier, board_slug)
    end
  end

  defp parse_args(args) do
    MixTaskHelpers.parse_args!(args, @switches, usage())
  end

  defp dispatch("list", user_identifier, _board_slug) do
    user = fetch_user!(user_identifier)

    user
    |> Boards.board_directory_for()
    |> Enum.each(fn %{category: category, boards: boards} ->
      Mix.shell().info(category.name)

      Enum.each(boards, fn entry ->
        Mix.shell().info("  #{entry.board.slug} #{status_label(entry)}")
      end)
    end)
  end

  defp dispatch("subscribe", user_identifier, board_slug) do
    user = fetch_user!(user_identifier)
    board = fetch_board!(board_slug)

    case Boards.subscribe_user_to_board(user, board.id) do
      {:ok, :subscribed} ->
        Mix.shell().info("Subscribed #{user.handle} to #{board.slug}")

      {:error, :board_archived} ->
        fail("Board #{board.slug} is archived.")

      {:error, :not_found} ->
        fail("Unknown board: #{board_slug}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset(
          "Failed to subscribe #{user.handle} to #{board.slug}:",
          changeset
        )
    end
  end

  defp dispatch("unsubscribe", user_identifier, board_slug) do
    user = fetch_user!(user_identifier)
    board = fetch_board!(board_slug)

    case Boards.unsubscribe_user_from_board(user, board.id) do
      {:ok, :unsubscribed} ->
        Mix.shell().info("Unsubscribed #{user.handle} from #{board.slug}")

      {:error, :required_subscription} ->
        fail("Cannot unsubscribe #{user.handle} from #{board.slug}: required subscription.")

      {:error, :board_archived} ->
        fail("Board #{board.slug} is archived.")

      {:error, :not_found} ->
        fail("Unknown board: #{board_slug}")
    end
  end

  defp fetch_user!(identifier) do
    Accounts.get_user_by_handle(identifier) || Accounts.get_user_by_email(identifier) ||
      fail("Unknown user: #{identifier}")
  end

  defp fetch_board!(slug) do
    case Boards.get_board_by_slug(slug) do
      nil -> fail("Unknown board: #{slug}")
      %Board{archived: true} -> fail("Board #{slug} is archived.")
      %Board{} = board -> board
    end
  end

  defp status_label(%{subscribed?: true, required_subscription?: true}), do: "[required]"
  defp status_label(%{subscribed?: true}), do: "[subscribed]"
  defp status_label(%{subscribed?: false}), do: "[unsubscribed]"

  @spec fail(String.t()) :: no_return()
  @spec fail(String.t(), String.t() | nil) :: no_return()
  defp fail(message, detail \\ nil), do: MixTaskHelpers.fail(message, detail)

  defp usage do
    """
    Usage:
      mix foglet.board_subscriptions list --user HANDLE_OR_EMAIL
      mix foglet.board_subscriptions subscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG
      mix foglet.board_subscriptions unsubscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG
    """
  end
end

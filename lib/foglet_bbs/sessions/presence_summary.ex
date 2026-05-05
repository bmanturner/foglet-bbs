defmodule Foglet.Sessions.PresenceSummary do
  @moduledoc """
  Reusable live-presence summary boundary for public profile cards.

  The boundary composes the one-session-per-user registry with door and
  board-screen presence. When a live session exists but no richer source is
  known, it returns the honest `:online` fallback.

  Deterministic precedence is: door > chat board > browsing board > online > offline.
  If multiple boards match the same precedence, board names/ids are sorted so
  repeated renders are stable.
  """

  alias Foglet.Sessions.Session
  alias Foglet.Sessions.Supervisor, as: SessionSupervisor

  @type activity ::
          :offline
          | :online
          | {:playing_door, map()}
          | {:browsing_board, map()}
          | {:chatting_in_board, map()}

  @type t :: %__MODULE__{activity: activity(), label: String.t(), online?: boolean()}

  defstruct activity: :offline, label: "Offline", online?: false

  @spec for_user(binary() | nil, keyword()) :: t()
  def for_user(user_id, opts \\ [])
  def for_user(nil, _opts), do: %__MODULE__{}

  def for_user(user_id, opts) when is_binary(user_id) do
    sessions = Keyword.get(opts, :sessions, SessionSupervisor)
    session_mod = Keyword.get(opts, :session, Session)

    case safe_lookup_session(sessions, user_id) do
      {:ok, pid} ->
        session_state = safe_session_state(session_mod, pid)

        activity =
          door_activity_for(user_id, opts) || board_activity_for(user_id, opts) || :online

        %__MODULE__{activity: activity, label: label(activity), online?: true}
        |> maybe_preserve_session_online(session_state)

      {:error, :not_found} ->
        %__MODULE__{}
    end
  end

  def label(:offline), do: "Offline"
  def label(:online), do: "Online"
  def label({:playing_door, door}), do: "Playing #{door_name(door)}"
  def label({:chatting_in_board, board}), do: "Chatting in #{board_name(board)}"
  def label({:browsing_board, board}), do: "Browsing #{board_name(board)}"

  defp safe_lookup_session(sessions, user_id) do
    sessions.lookup_session(user_id)
  rescue
    _ -> {:error, :not_found}
  catch
    :exit, _ -> {:error, :not_found}
  end

  defp safe_session_state(session_mod, pid) do
    session_mod.get_state(pid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp maybe_preserve_session_online(%__MODULE__{} = summary, _session_state), do: summary

  defp door_activity_for(user_id, opts) do
    door_presence = Keyword.get(opts, :door_presence, Foglet.Sessions.DoorPresence)

    case door_presence.get(user_id) do
      {:ok, door} -> {:playing_door, door}
      :error -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp board_activity_for(user_id, opts) do
    boards_mod = Keyword.get(opts, :boards, Foglet.Boards)
    board_screen = Keyword.get(opts, :board_screen, Foglet.Sessions.BoardScreen)

    boards_mod.list_boards()
    |> Enum.flat_map(&entries_for_board(board_screen, &1))
    |> Enum.filter(&(Map.get(&1, :user_id) == user_id))
    |> Enum.sort_by(&activity_sort_key/1)
    |> List.first()
    |> activity_from_entry()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp entries_for_board(board_screen, board) do
    board_id = Map.get(board, :id) || Map.get(board, "id")

    if is_binary(board_id) do
      board_screen.list(board_id)
      |> Enum.map(fn entry -> Map.put(entry, :board, board) end)
    else
      []
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp activity_sort_key(%{tab: :chat, board: board}), do: {0, board_name(board), board_id(board)}

  defp activity_sort_key(%{tab: :threads, board: board}),
    do: {1, board_name(board), board_id(board)}

  defp activity_sort_key(%{board: board}), do: {2, board_name(board), board_id(board)}

  defp activity_from_entry(nil), do: nil
  defp activity_from_entry(%{tab: :chat, board: board}), do: {:chatting_in_board, board}
  defp activity_from_entry(%{tab: :threads, board: board}), do: {:browsing_board, board}
  defp activity_from_entry(_entry), do: nil

  defp board_name(board) do
    Map.get(board, :name) || Map.get(board, "name") || Map.get(board, :slug) ||
      Map.get(board, "slug") || "board"
  end

  defp board_id(board), do: Map.get(board, :id) || Map.get(board, "id") || ""

  defp door_name(door) do
    Map.get(door, :name) || Map.get(door, "name") || Map.get(door, :display_name) ||
      Map.get(door, "display_name") || Map.get(door, :id) || Map.get(door, "id") || "door"
  end
end

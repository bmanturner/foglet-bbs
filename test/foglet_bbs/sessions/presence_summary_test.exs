defmodule Foglet.Sessions.PresenceSummaryTest do
  use ExUnit.Case, async: true

  alias Foglet.Sessions.PresenceSummary

  defmodule OnlineSessions do
    def lookup_session(user_id) when user_id in ["online", "chat", "threads", "door"] do
      {:ok, user_id}
    end

    def lookup_session(_user_id), do: {:error, :not_found}
  end

  defmodule FakeSession do
    @active_at ~U[2099-01-01 00:00:00Z]

    def get_state(user_id), do: %{user_id: user_id, last_action_at: @active_at}
    def idle?(session_state, now), do: Foglet.Sessions.Session.idle?(session_state, now)
  end

  defmodule IdleSession do
    @idle_at ~U[2026-05-05 12:00:00Z]

    def get_state(user_id), do: %{user_id: user_id, last_action_at: @idle_at}
    def idle?(session_state, now), do: Foglet.Sessions.Session.idle?(session_state, now)
  end

  defmodule FakeBoards do
    def list_boards do
      [%{id: "b2", name: "Zed"}, %{id: "b1", name: "General"}]
    end
  end

  defmodule FakeBoardScreen do
    def list("b1"),
      do: [
        %{user_id: "chat", tab: :chat},
        %{user_id: "threads", tab: :threads},
        %{user_id: "door", tab: :chat}
      ]

    def list("b2"), do: [%{user_id: "chat", tab: :threads}]
  end

  defmodule FakeDoorPresence do
    def get("door"), do: {:ok, %{id: "lord", name: "Legend of the Red Dragon"}}
    def get(_user_id), do: :error
  end

  test "returns offline when no authenticated session exists" do
    assert %PresenceSummary{activity: :offline, label: "Offline", online?: false} =
             PresenceSummary.for_user("missing", sessions: OnlineSessions)
  end

  test "returns online fallback when no board activity exists" do
    assert %PresenceSummary{activity: :online, label: "Online", online?: true} =
             PresenceSummary.for_user("online", sessions: OnlineSessions, session: FakeSession)
  end

  test "prefers door activity over chat and browsing board activity deterministically" do
    assert %PresenceSummary{
             activity: {:playing_door, %{id: "lord", name: "Legend of the Red Dragon"}},
             label: "Playing Legend of the Red Dragon",
             online?: true
           } =
             PresenceSummary.for_user("door",
               sessions: OnlineSessions,
               session: FakeSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen,
               door_presence: FakeDoorPresence
             )
  end

  test "prefers chat board activity over browsing board activity deterministically" do
    assert %PresenceSummary{
             activity: {:chatting_in_board, %{id: "b1", name: "General"}},
             label: "Chatting in General",
             online?: true
           } =
             PresenceSummary.for_user("chat",
               sessions: OnlineSessions,
               session: FakeSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen
             )
  end

  test "reports threads tab as browsing board" do
    assert %PresenceSummary{
             activity: {:browsing_board, %{id: "b1", name: "General"}},
             label: "Browsing General",
             online?: true
           } =
             PresenceSummary.for_user("threads",
               sessions: OnlineSessions,
               session: FakeSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen
             )
  end

  test "annotates idle online and activity labels while preserving precedence" do
    now = ~U[2026-05-05 12:03:00Z]

    assert %PresenceSummary{label: "Online [Idle]", online?: true, idle?: true} =
             PresenceSummary.for_user("online",
               sessions: OnlineSessions,
               session: IdleSession,
               now: now
             )

    assert %PresenceSummary{label: "Browsing General [Idle]", idle?: true} =
             PresenceSummary.for_user("threads",
               sessions: OnlineSessions,
               session: IdleSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen,
               now: now
             )

    assert %PresenceSummary{label: "Chatting in General [Idle]", idle?: true} =
             PresenceSummary.for_user("chat",
               sessions: OnlineSessions,
               session: IdleSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen,
               now: now
             )

    assert %PresenceSummary{label: "Playing Legend of the Red Dragon [Idle]", idle?: true} =
             PresenceSummary.for_user("door",
               sessions: OnlineSessions,
               session: IdleSession,
               boards: FakeBoards,
               board_screen: FakeBoardScreen,
               door_presence: FakeDoorPresence,
               now: now
             )
  end

  test "leaves non-idle, offline, and guest labels unannotated" do
    now = ~U[2026-05-05 12:03:00Z]

    assert %PresenceSummary{label: "Online", online?: true, idle?: false} =
             PresenceSummary.for_user("online",
               sessions: OnlineSessions,
               session: FakeSession,
               now: ~U[2026-05-05 12:03:00Z]
             )

    assert %PresenceSummary{label: "Offline", online?: false, idle?: false} =
             PresenceSummary.for_user("missing", sessions: OnlineSessions, now: now)

    assert %PresenceSummary{label: "Offline", online?: false, idle?: false} =
             PresenceSummary.for_user(nil, sessions: OnlineSessions, now: now)
  end
end

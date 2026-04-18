defmodule Foglet.Sessions.SessionTest do
  use FogletBbs.DataCase, async: false

  describe "Foglet.Sessions.Session (SSH-05)" do
    @tag :pending
    test "starts a Session GenServer and registers via Foglet.Sessions.Registry by user_id" do
      flunk("Pending — Plan 02 implements Foglet.Sessions.Session GenServer")
    end

    @tag :pending
    test "second start_link for same user_id returns {:error, {:already_started, old_pid}}" do
      flunk("Pending — Plan 02 implements Registry via-tuple naming")
    end

    @tag :pending
    test "Sessions.Supervisor replaces old session: notifies old, terminates it, starts new (SSH-05 + D-25)" do
      flunk("Pending — Plan 02 implements replace_session/1 in Sessions.Supervisor")
    end

    @tag :pending
    test "old session receives :replaced_by_new_session message before termination" do
      flunk("Pending — Plan 02 implements replacement protocol")
    end

    @tag :pending
    test "session init loads user, handle, role, terminal_size from opts" do
      flunk("Pending — Plan 02 implements Session.init/1")
    end

    @tag :pending
    test "session updates last_seen_at on heartbeat cast" do
      flunk("Pending — Plan 02 implements heartbeat message")
    end
  end

  describe "one-session-per-user race safety" do
    @tag :pending
    test "two near-simultaneous start_child calls for same user produce exactly one live session" do
      flunk("Pending — Plan 02 implements TOCTOU-safe replacement (Pitfall 4)")
    end
  end
end

defmodule Foglet.Sessions.SupervisorTest do
  use FogletBbs.DataCase, async: false

  describe "Foglet.Sessions.Supervisor (SSH-05)" do
    @tag :pending
    test "start_session/1 starts a new Session under the DynamicSupervisor" do
      flunk("Pending — Plan 02 implements Foglet.Sessions.Supervisor.start_session/1")
    end

    @tag :pending
    test "start_session/1 replaces an existing session for the same user_id" do
      flunk("Pending — Plan 02 implements replace_session in Supervisor")
    end

    @tag :pending
    test "terminate_session/1 stops a running session" do
      flunk("Pending — Plan 02 implements terminate_session/1")
    end

    @tag :pending
    test "lookup_session/1 returns {:ok, pid} when present, {:error, :not_found} otherwise" do
      flunk("Pending — Plan 02 implements lookup_session/1")
    end
  end
end

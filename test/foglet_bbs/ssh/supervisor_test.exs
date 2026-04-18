defmodule Foglet.SSH.SupervisorTest do
  use ExUnit.Case, async: false

  describe "Foglet.SSH.Supervisor (SSH-01)" do
    @tag :pending
    test "starts the :ssh.daemon/2 with system_dir set to priv/ssh/" do
      flunk("Pending — Plan 02 implements Foglet.SSH.Supervisor")
    end

    @tag :pending
    test "host key is generated in priv/ssh/ if absent on first boot" do
      flunk("Pending — Plan 02 implements host-key bootstrap")
    end

    @tag :pending
    test "host key persists across supervisor restarts" do
      flunk("Pending — Plan 02 implements host-key persistence (Pitfall 3)")
    end

    @tag :pending
    test "daemon rejects connections if OTP version < 27.3.3 (CVE-2025-32433 guard)" do
      flunk("Pending — Plan 02 implements OTP version assertion in init/1")
    end
  end
end

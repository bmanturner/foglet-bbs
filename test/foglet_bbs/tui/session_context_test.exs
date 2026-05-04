defmodule Foglet.TUI.SessionContextTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.User
  alias Foglet.TUI.SessionContext

  describe "guest contract predicates" do
    test "default context is login-screen unauthenticated, not an intentional guest" do
      context = %SessionContext{}

      refute SessionContext.guest?(context)
      refute SessionContext.authenticated?(context)
      assert SessionContext.login_unauthenticated?(context)
    end

    test "explicit guest context stays distinct from authenticated users" do
      context = %SessionContext{guest: true, guest_mode_enabled: true}

      assert SessionContext.guest?(context)
      refute SessionContext.authenticated?(context)
      refute SessionContext.login_unauthenticated?(context)
    end

    test "authenticated context is never treated as guest even if guest flag is set incorrectly" do
      user = %User{id: "u1", handle: "alice"}

      context = %SessionContext{
        user: user,
        user_id: user.id,
        guest: true,
        guest_mode_enabled: true
      }

      refute SessionContext.guest?(context)
      assert SessionContext.authenticated?(context)
      refute SessionContext.login_unauthenticated?(context)
    end

    test "guest availability follows the guest_mode_enabled snapshot" do
      assert SessionContext.guest_mode_enabled?(%SessionContext{guest_mode_enabled: true})
      refute SessionContext.guest_mode_enabled?(%SessionContext{guest_mode_enabled: false})
    end
  end
end

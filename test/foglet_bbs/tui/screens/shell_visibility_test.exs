defmodule Foglet.TUI.Screens.ShellVisibilityTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.ShellVisibility

  # Minimal user map helpers — mirrors the Foglet.Accounts.User struct fields
  # that ShellVisibility pattern-matches on.
  defp user(role), do: %Foglet.Accounts.User{id: "u1", handle: "test", role: role}
  defp any_user, do: user(:user)

  describe "account_visible?/1" do
    test "returns false for nil user" do
      refute ShellVisibility.account_visible?(nil)
    end

    test "returns true for a :user-role user" do
      assert ShellVisibility.account_visible?(any_user())
    end

    test "returns true for a :mod-role user" do
      assert ShellVisibility.account_visible?(user(:mod))
    end

    test "returns true for a :sysop-role user" do
      assert ShellVisibility.account_visible?(user(:sysop))
    end

    test "returns true for a map without :role key (any authenticated user)" do
      assert ShellVisibility.account_visible?(%{id: "u1"})
    end
  end

  describe "moderation_visible?/1" do
    test "returns false for nil user" do
      refute ShellVisibility.moderation_visible?(nil)
    end

    test "returns false for :user-role user" do
      refute ShellVisibility.moderation_visible?(user(:user))
    end

    test "returns true for :mod-role user" do
      assert ShellVisibility.moderation_visible?(user(:mod))
    end

    test "returns true for :sysop-role user (sysop can also moderate)" do
      assert ShellVisibility.moderation_visible?(user(:sysop))
    end

    test "returns false for a map without :role key" do
      refute ShellVisibility.moderation_visible?(%{id: "u1"})
    end
  end

  describe "sysop_visible?/1" do
    test "returns false for nil user" do
      refute ShellVisibility.sysop_visible?(nil)
    end

    test "returns false for :user-role user" do
      refute ShellVisibility.sysop_visible?(user(:user))
    end

    test "returns false for :mod-role user" do
      refute ShellVisibility.sysop_visible?(user(:mod))
    end

    test "returns true for :sysop-role user" do
      assert ShellVisibility.sysop_visible?(user(:sysop))
    end

    test "returns false for a map without :role key" do
      refute ShellVisibility.sysop_visible?(%{id: "u1"})
    end
  end

  describe "invites_visible?/2" do
    test "open registration hides invites for sysops, mods, and regular users" do
      context = %{registration_mode: "open", invite_code_generators: "any_user"}

      refute ShellVisibility.invites_visible?(user(:sysop), context)
      refute ShellVisibility.invites_visible?(user(:mod), context)
      refute ShellVisibility.invites_visible?(user(:user), context)
    end

    test "invite-backed registration applies invite generation policy" do
      assert ShellVisibility.invites_visible?(
               user(:sysop),
               %{registration_mode: "invite_only", invite_code_generators: "sysop_only"}
             )

      assert ShellVisibility.invites_visible?(
               user(:mod),
               %{registration_mode: "invite_only", invite_code_generators: "mods"}
             )

      assert ShellVisibility.invites_visible?(
               user(:user),
               %{registration_mode: "sysop_approved", invite_code_generators: "any_user"}
             )

      refute ShellVisibility.invites_visible?(
               user(:user),
               %{registration_mode: "invite_only", invite_code_generators: "mods"}
             )
    end
  end
end

defmodule Mix.Tasks.Foglet.User.CreateTest do
  use FogletBbs.DataCase, async: false

  describe "mix foglet.user.create (IDNT-05)" do
    @tag :pending
    test "creates a user given --handle --email --password" do
      flunk("Pending — Plan 04 implements Mix.Tasks.Foglet.User.Create")
    end

    @tag :pending
    test "created user has confirmed_at set (auto-confirm per D-02)" do
      flunk("Pending — Plan 04 implements auto-confirm for sysop-created accounts")
    end

    @tag :pending
    test "missing --handle exits non-zero with usage message" do
      flunk("Pending — Plan 04 implements OptionParser strict handling")
    end

    @tag :pending
    test "duplicate handle exits non-zero" do
      flunk("Pending — Plan 04 surfaces changeset errors")
    end
  end
end

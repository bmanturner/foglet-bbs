defmodule Mix.Tasks.Foglet.User.PromoteTest do
  use FogletBbs.DataCase, async: false

  describe "mix foglet.user.promote (IDNT-06)" do
    @tag :pending
    test "promotes an existing user to sysop given handle + --role sysop" do
      flunk("Pending — Plan 04 implements promote task")
    end

    @tag :pending
    test "accepts roles user, mod, sysop" do
      flunk("Pending — Plan 04 validates --role values")
    end

    @tag :pending
    test "rejects invalid role string with non-zero exit" do
      flunk("Pending — Plan 04 implements role validation (no String.to_atom on input)")
    end

    @tag :pending
    test "unknown handle exits non-zero" do
      flunk("Pending — Plan 04 handles not_found")
    end
  end
end

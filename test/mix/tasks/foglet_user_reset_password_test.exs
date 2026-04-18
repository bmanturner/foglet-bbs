defmodule Mix.Tasks.Foglet.User.ResetPasswordTest do
  use FogletBbs.DataCase, async: false

  describe "mix foglet.user.reset_password (IDNT-08)" do
    @tag :pending
    test "prints a reset URL containing a url-encoded token to stdout" do
      flunk("Pending — Plan 04 implements reset_password task")
    end

    @tag :pending
    test "inserts a user_tokens row with context=\"reset_password\"" do
      flunk("Pending — Plan 04 persists the reset token")
    end

    @tag :pending
    test "unknown handle exits non-zero" do
      flunk("Pending — Plan 04 handles not_found")
    end
  end
end

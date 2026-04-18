defmodule Foglet.Accounts.UserTokenTest do
  use FogletBbs.DataCase, async: true

  describe "build_email_token/2 (IDNT-02, IDNT-08)" do
    @tag :pending
    test "returns {raw_token, %UserToken{}} with SHA256-hashed token in struct" do
      flunk("Pending — Plan 02 implements UserToken.build_email_token/2")
    end

    @tag :pending
    test "raw token is Base.url_encode64 (no padding)" do
      flunk("Pending — Plan 02 implements UserToken.build_email_token/2")
    end

    @tag :pending
    test "sets sent_to to user.email and user_id to user.id" do
      flunk("Pending — Plan 02 implements UserToken.build_email_token/2")
    end
  end

  describe "verify_email_token_query/2" do
    @tag :pending
    test "returns query matching user when token within expiry" do
      flunk("Pending — Plan 02 implements verify_email_token_query/2")
    end

    @tag :pending
    test "rejects token older than context expiry (7 days confirm, 1 day reset)" do
      flunk("Pending — Plan 02 implements verify_email_token_query/2")
    end
  end
end

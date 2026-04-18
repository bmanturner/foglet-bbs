defmodule Foglet.AccountsTest do
  use FogletBbs.DataCase, async: true

  describe "register_user/1 (IDNT-01)" do
    @tag :pending
    test "creates a user with hashed password" do
      flunk("Pending — Plan 03 implements Foglet.Accounts.register_user/1")
    end
  end

  describe "authenticate_by_password/2 (IDNT-01)" do
    @tag :pending
    test "returns {:ok, user} on valid credentials" do
      flunk("Pending — Plan 03 implements authenticate_by_password/2")
    end

    @tag :pending
    test "returns {:error, :invalid_credentials} on invalid password" do
      flunk("Pending — Plan 03 implements authenticate_by_password/2")
    end

    @tag :pending
    test "calls Argon2.no_user_verify/0 on unknown handle (timing safety)" do
      flunk("Pending — Plan 03 implements authenticate_by_password/2")
    end
  end

  describe "register_ssh_key/2 (IDNT-04)" do
    @tag :pending
    test "stores key with computed fingerprint" do
      flunk("Pending — Plan 03 implements register_ssh_key/2")
    end
  end

  describe "delete_user/1 (IDNT-07)" do
    @tag :pending
    test "rewrites user posts to tombstone user_id" do
      flunk("Pending — Plan 03 implements delete_user/1 with Ecto.Multi")
    end

    @tag :pending
    test "clears PII: email randomized, location/tagline/real_name nil" do
      flunk("Pending — Plan 03 implements deletion_changeset/1")
    end

    @tag :pending
    test "deletes ssh_keys and user_tokens for the deleted user" do
      flunk("Pending — Plan 03 implements delete_user/1")
    end

    @tag :pending
    test "sets deleted_at and invalidates password_hash" do
      flunk("Pending — Plan 03 implements deletion_changeset/1")
    end
  end
end

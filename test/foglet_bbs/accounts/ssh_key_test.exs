defmodule Foglet.Accounts.SSHKeyTest do
  use FogletBbs.DataCase, async: true

  describe "SSHKey changeset (IDNT-04)" do
    @tag :pending
    test "computes fingerprint from public_key at insert time" do
      flunk("Pending — Plan 02 implements SSHKey changeset")
    end

    @tag :pending
    test "rejects duplicate fingerprint across users" do
      flunk("Pending — Plan 02 implements unique_constraint(:fingerprint)")
    end

    @tag :pending
    test "rejects duplicate label per user" do
      flunk("Pending — Plan 02 implements unique_constraint([:user_id, :label])")
    end
  end
end

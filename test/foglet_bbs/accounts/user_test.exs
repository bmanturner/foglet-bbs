defmodule Foglet.Accounts.UserTest do
  use FogletBbs.DataCase, async: true

  # Stubs filled in by Plan 02 (schemas) and Plan 03 (context)

  describe "registration_changeset/2 (IDNT-01)" do
    @tag :pending
    test "hashes password with Argon2 and clears :password virtual field" do
      flunk("Pending — Plan 02 implements registration_changeset/2")
    end

    @tag :pending
    test "requires handle, email, password" do
      flunk("Pending — Plan 02 implements registration_changeset/2")
    end

    @tag :pending
    test "rejects duplicate email case-insensitively (citext)" do
      flunk("Pending — Plan 02 implements registration_changeset/2")
    end
  end

  describe "handle uniqueness (IDNT-03)" do
    @tag :pending
    test "rejects duplicate handle case-insensitively" do
      flunk("Pending — Plan 02 implements handle validation")
    end

    @tag :pending
    test "rejects handle with invalid characters" do
      flunk("Pending — Plan 02 implements handle validation")
    end

    @tag :pending
    test "preserves display case of handle in stored value" do
      flunk("Pending — Plan 02 implements handle validation")
    end
  end
end

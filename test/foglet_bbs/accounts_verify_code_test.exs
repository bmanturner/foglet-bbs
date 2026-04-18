defmodule Foglet.AccountsVerifyCodeTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts
  alias Foglet.Accounts.UserToken
  alias FogletBbs.Repo

  import FogletBbs.AccountsFixtures

  describe "UserToken.build_verify_code/1" do
    test "returns {code, %UserToken{}} with 6-char uppercase alphanumeric code" do
      user = user_fixture()
      {code, token_struct} = UserToken.build_verify_code(user)

      assert String.length(code) == 6
      assert code == String.upcase(code)
      assert code =~ ~r/\A[A-Z0-9]+\z/
      assert token_struct.context == "email_verify"
      assert token_struct.sent_to == user.email
      assert token_struct.user_id == user.id
      assert token_struct.token == code
    end

    test "generates different codes on consecutive calls" do
      user = user_fixture()
      {code1, _} = UserToken.build_verify_code(user)
      {code2, _} = UserToken.build_verify_code(user)
      # Extremely high probability these differ (6 chars of 32 symbols each)
      refute code1 == code2
    end
  end

  describe "Accounts.build_verify_code/1" do
    test "persists a token row with context = \"email_verify\"" do
      user = user_fixture()
      {:ok, code} = Accounts.build_verify_code(user)

      assert String.length(code) == 6
      row = Repo.get_by!(UserToken, token: code, context: "email_verify")
      assert row.user_id == user.id
      assert row.sent_to == user.email
    end
  end

  describe "Accounts.verify_email_code/2" do
    test "returns {:ok, confirmed_user} on match" do
      user = user_fixture()
      {:ok, code} = Accounts.build_verify_code(user)

      assert {:ok, confirmed} = Accounts.verify_email_code(user, code)
      assert confirmed.confirmed_at != nil
      assert confirmed.id == user.id
    end

    test "returns {:error, :invalid_code} for wrong code" do
      user = user_fixture()
      {:ok, _code} = Accounts.build_verify_code(user)

      assert {:error, :invalid_code} = Accounts.verify_email_code(user, "WRONG1")
    end

    test "returns {:error, :expired} for code older than 15 minutes" do
      user = user_fixture()
      {_code_unused, token_struct} = UserToken.build_verify_code(user)

      # Insert with inserted_at 16 minutes in the past to simulate expiry
      sixteen_min_ago = DateTime.add(DateTime.utc_now(), -16 * 60, :second)

      {:ok, inserted} =
        token_struct
        |> Ecto.Changeset.change(%{inserted_at: sixteen_min_ago})
        |> Repo.insert()

      assert {:error, :expired} = Accounts.verify_email_code(user, inserted.token)
    end

    test "rejects code when email does not match user" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, code_for_a} = Accounts.build_verify_code(user_a)

      # user_b tries to use user_a's code — sent_to mismatch
      assert {:error, :invalid_code} = Accounts.verify_email_code(user_b, code_for_a)
    end

    test "deletes all email_verify tokens after successful verification" do
      user = user_fixture()
      {:ok, code} = Accounts.build_verify_code(user)
      {:ok, _} = Accounts.verify_email_code(user, code)

      remaining =
        Repo.all(UserToken.by_user_and_contexts_query(user, ["email_verify"]))

      assert remaining == []
    end
  end

  describe "Accounts.register_pending_user/1" do
    test "creates user with status: :pending" do
      attrs = valid_user_attributes()
      assert {:ok, user} = Accounts.register_pending_user(attrs)
      assert user.status == :pending
      assert user.confirmed_at == nil
    end

    test "validates attrs like register_user/1 (rejects invalid)" do
      assert {:error, %Ecto.Changeset{}} =
               Accounts.register_pending_user(%{"handle" => "x"})
    end
  end

  describe "Accounts.register_user/1 (existing — confirming status defaults to :active)" do
    test "creates user with status: :active" do
      attrs = valid_user_attributes()
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.status == :active
    end
  end
end

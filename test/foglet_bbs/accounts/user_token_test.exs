defmodule Foglet.Accounts.UserTokenTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.{User, UserToken}
  alias FogletBbs.AccountsFixtures

  defp insert_user! do
    {:ok, u} =
      %User{}
      |> User.registration_changeset(AccountsFixtures.valid_user_attributes())
      |> Repo.insert()

    u
  end

  describe "build_email_token/2 (IDNT-02, IDNT-08)" do
    test "returns {raw_token, %UserToken{}} with SHA256-hashed token in struct" do
      user = insert_user!()
      {raw, %UserToken{} = token_struct} = UserToken.build_email_token(user, "confirm")

      assert is_binary(raw)
      assert is_binary(token_struct.token)
      assert byte_size(token_struct.token) == 32
      # The struct.token is the SHA256 of the DECODED raw token.
      {:ok, decoded} = Base.url_decode64(raw, padding: false)
      assert :crypto.hash(:sha256, decoded) == token_struct.token
    end

    test "raw token is Base.url_encode64 without padding" do
      user = insert_user!()
      {raw, _} = UserToken.build_email_token(user, "reset_password")
      refute String.contains?(raw, "=")
      # url-safe alphabet only
      assert Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, raw)
    end

    test "sets sent_to to user.email and user_id to user.id" do
      user = insert_user!()
      {_raw, ts} = UserToken.build_email_token(user, "confirm")
      assert ts.sent_to == user.email
      assert ts.user_id == user.id
      assert ts.context == "confirm"
    end

    test "two calls produce different raw tokens" do
      user = insert_user!()
      {raw_a, _} = UserToken.build_email_token(user, "confirm")
      {raw_b, _} = UserToken.build_email_token(user, "confirm")
      refute raw_a == raw_b
    end
  end

  describe "verify_email_token_query/2" do
    test "returns query matching user when token within expiry" do
      user = insert_user!()
      {raw, struct} = UserToken.build_email_token(user, "confirm")
      {:ok, _} = Repo.insert(struct)

      {:ok, query} = UserToken.verify_email_token_query(raw, "confirm")
      assert %User{id: found_id} = Repo.one(query)
      assert found_id == user.id
    end

    test "returns no user when token older than per-context expiry" do
      user = insert_user!()
      {raw, struct} = UserToken.build_email_token(user, "reset_password")
      {:ok, inserted} = Repo.insert(struct)

      # Simulate an aged token by updating inserted_at to > 1 day ago
      old = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:microsecond)

      Repo.update_all(
        from(t in UserToken, where: t.id == ^inserted.id),
        set: [inserted_at: old]
      )

      {:ok, query} = UserToken.verify_email_token_query(raw, "reset_password")
      assert Repo.one(query) == nil
    end

    test "returns :error on malformed base64" do
      assert UserToken.verify_email_token_query("not valid base64!!!", "confirm") == :error
    end

    test "returns no user when sent_to no longer matches user.email" do
      user = insert_user!()
      {raw, struct} = UserToken.build_email_token(user, "confirm")
      {:ok, _} = Repo.insert(struct)

      # User changes email
      {:ok, _} =
        user
        |> Ecto.Changeset.change(%{
          email: "newemail_#{System.unique_integer([:positive])}@example.com"
        })
        |> Repo.update()

      {:ok, query} = UserToken.verify_email_token_query(raw, "confirm")
      assert Repo.one(query) == nil
    end
  end

  describe "validity_days/1" do
    test "enforces per-context expiry windows" do
      assert UserToken.validity_days("confirm") == 7
      assert UserToken.validity_days("reset_password") == 1
    end
  end
end

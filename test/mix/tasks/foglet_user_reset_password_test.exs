defmodule Mix.Tasks.Foglet.User.ResetPasswordTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO
  import Ecto.Query

  alias Foglet.Accounts
  alias Foglet.Accounts.UserToken
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode, nil)
      Config.invalidate("delivery_mode")
    end)

    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.user.reset_password (IDNT-08)" do
    test "Accounts helper persists only the hashed reset token row" do
      user = AccountsFixtures.user_fixture(%{handle: "helperhash"})

      assert {:ok, raw_token} = Accounts.generate_reset_token_for_operator(user)
      {:ok, decoded_token} = Base.url_decode64(raw_token, padding: false)
      hashed_token = :crypto.hash(UserToken.hash_algorithm(), decoded_token)

      assert Repo.exists?(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and t.context == "reset_password" and
                     t.token == ^hashed_token and t.sent_to == ^user.email
             )

      refute Repo.exists?(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and t.context == "reset_password" and
                     t.token == ^raw_token
             )
    end

    test "in email mode prints a break-glass raw reset token to stdout" do
      Config.put!("delivery_mode", "email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "resetme"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.ResetPassword.run(["resetme"])
        end)

      assert output =~ "Break-glass reset token for resetme:"
      assert output =~ "Reset token:"

      assert output =~
               "Give this token to the user through your operator-assisted SSH reset procedure."

      assert output =~ "No email was sent by this task."
      refute output =~ "has been emailed"
      refute output =~ "sent by email"
      refute_reset_url_copy(output)

      [_, token_portion] = Regex.run(~r/Reset token: ([A-Za-z0-9_-]+)/, output)
      refute String.contains?(token_portion, "=")

      # Round-trip the token against the API
      {:ok, query} = UserToken.verify_email_token_query(token_portion, "reset_password")
      assert %{id: found_id} = Repo.one(query)
      assert found_id == user.id
    end

    test "in no-email mode prints operator retrieval reset details" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "noemailreset"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.ResetPassword.run([user.handle])
        end)

      assert output =~ "No-email reset details for noemailreset:"
      assert output =~ "Reset token:"

      assert output =~
               "Give this token to the user through your operator-assisted SSH reset procedure."

      assert output =~ "No email was sent by this task."
      refute_reset_url_copy(output)

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "unknown handle exits non-zero" do
      Config.put!("delivery_mode", "email", nil)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run(["no_such_user"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "User not found"
    end

    test "deleted user is rejected" do
      Config.put!("delivery_mode", "email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "graveyard"})
      {:ok, _} = Accounts.delete_user(user)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run(["graveyard"])) ==
                   {:shutdown, 1}
        end)

      # After delete_user/1 deleted_at is set — task must reject.
      assert output =~ "deleted" or output =~ "User not found"
    end

    test "missing handle exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run([])) == {:shutdown, 1}
        end)

      assert output =~ "Missing required handle"
    end

    test "unknown flag exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run(["foo", "--bogus", "x"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Invalid arguments"
    end
  end

  defp refute_reset_url_copy(output) do
    [
      "http" <> "://",
      "https" <> "://",
      "/users" <> "/reset_password/",
      "reset " <> "URL",
      "operator reset " <> "URL"
    ]
    |> Enum.each(fn forbidden ->
      refute output =~ forbidden
    end)
  end
end

defmodule Mix.Tasks.Foglet.User.ResetPasswordTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO
  import Ecto.Query

  alias Foglet.Accounts
  alias Foglet.Accounts.UserToken
  alias FogletBbs.AccountsFixtures

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.user.reset_password (IDNT-08)" do
    test "prints a reset URL containing a url-encoded token to stdout" do
      user = AccountsFixtures.user_fixture(%{handle: "resetme"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.ResetPassword.run(["resetme"])
        end)

      assert output =~ "Reset URL for resetme"
      assert output =~ "/users/reset_password/"

      # Extract the raw token portion and verify it's url-safe base64
      [url_line] = Regex.run(~r{https://\S+}, output) |> List.wrap()
      token_portion = url_line |> String.split("/") |> List.last()
      assert token_portion =~ ~r/\A[A-Za-z0-9_-]+\z/
      refute String.contains?(token_portion, "=")

      # Round-trip the token against the API
      {:ok, query} = UserToken.verify_email_token_query(token_portion, "reset_password")
      assert %{id: found_id} = Repo.one(query)
      assert found_id == user.id
    end

    test "inserts a user_tokens row with context=\"reset_password\"" do
      user = AccountsFixtures.user_fixture(%{handle: "dbrow"})

      capture_io(fn ->
        Mix.Tasks.Foglet.User.ResetPassword.run(["dbrow"])
      end)

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "unknown handle exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run(["no_such_user"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "User not found"
    end

    test "deleted user is rejected" do
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
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run([])) == {:shutdown, 1}
      end)
    end

    test "unknown flag exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.ResetPassword.run(["foo", "--bogus", "x"])) ==
                 {:shutdown, 1}
      end)
    end
  end
end

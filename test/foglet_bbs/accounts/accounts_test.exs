defmodule FogletBbs.AccountsTest.FailingMailerAdapter do
  def validate_config(_config), do: :ok
  def deliver(_email, _config), do: {:error, :forced_failure}
end

defmodule Foglet.AccountsTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.{SSHKey, User, UserToken}
  alias Foglet.Boards.{Board, Category}
  alias Foglet.Config
  alias Foglet.Posts.Post
  alias Foglet.Threads.Thread
  alias FogletBbs.AccountsFixtures

  import Swoosh.TestAssertions

  describe "register_user/1 (IDNT-01)" do
    setup do
      Config.init_cache()
      current_registration_mode = Config.get("registration_mode", "open")

      on_exit(fn ->
        Config.put!("registration_mode", current_registration_mode)
        Config.invalidate("registration_mode")
      end)

      :ok
    end

    test "creates a user with hashed password" do
      attrs = AccountsFixtures.valid_user_attributes(%{password: "opensesame"})
      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.password_hash != "opensesame"
      assert Argon2.verify_pass("opensesame", user.password_hash)
    end

    test "creates users with account preference defaults" do
      attrs = AccountsFixtures.valid_user_attributes()

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      reloaded = Accounts.get_user!(user.id)

      assert is_binary(reloaded.timezone)
      assert reloaded.timezone != ""
      assert reloaded.preferences["time_format"] == "12h"
      assert reloaded.theme == "gray"
    end

    test "returns {:error, changeset} on invalid attrs" do
      assert {:error, cs} = Accounts.register_user(%{})
      refute cs.valid?
    end

    test "creates pending users in sysop-approved registration mode" do
      Config.put!("registration_mode", "sysop_approved")

      attrs = AccountsFixtures.valid_user_attributes()
      assert {:ok, %User{status: :pending}} = Accounts.register_user(attrs)
    end
  end

  describe "authenticate_by_password/2 (IDNT-01)" do
    test "returns {:ok, user} on valid credentials" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      assert {:ok, %User{id: id}} = Accounts.authenticate_by_password(user.handle, "letmein12")
      assert id == user.id
    end

    test "case-insensitive handle lookup via citext" do
      _user = AccountsFixtures.user_fixture(%{handle: "CamelCase", password: "letmein12"})

      assert {:ok, %User{handle: "CamelCase"}} =
               Accounts.authenticate_by_password("camelcase", "letmein12")

      assert {:ok, %User{handle: "CamelCase"}} =
               Accounts.authenticate_by_password("CAMELCASE", "letmein12")
    end

    test "returns {:error, :invalid_credentials} on invalid password" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(user.handle, "wrong")
    end

    test "returns {:error, :invalid_credentials} on unknown handle (timing-safe)" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password("no_such_user", "anything")
    end

    test "rejects authentication for deleted users" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      {:ok, _} = Accounts.delete_user(user)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(user.handle, "letmein12")
    end
  end

  describe "post_login_screen/1 (VERIFY-01)" do
    setup do
      # The sandbox rolls back all DB writes after each test, so we don't need
      # to restore the config row in on_exit. We only need to clear the ETS
      # cache so the next test doesn't read a stale cached value.
      on_exit(fn ->
        Foglet.Config.invalidate("require_email_verification")
      end)

      :ok
    end

    test "confirmed user routes to :main_menu regardless of config flag" do
      Foglet.Config.put!("require_email_verification", true)
      user = AccountsFixtures.user_fixture()
      {:ok, confirmed} = Accounts.confirm_user(user)

      assert Accounts.post_login_screen(confirmed) == :main_menu

      # Flip the config and re-check — confirmed users are unaffected.
      Foglet.Config.put!("require_email_verification", false)
      assert Accounts.post_login_screen(confirmed) == :main_menu
    end

    test "unconfirmed user with require_email_verification=true routes to :verify" do
      Foglet.Config.put!("require_email_verification", true)
      user = AccountsFixtures.user_fixture()
      assert user.confirmed_at == nil

      assert Accounts.post_login_screen(user) == :verify
    end

    test "unconfirmed user with require_email_verification=false routes to :main_menu" do
      Foglet.Config.put!("require_email_verification", false)
      user = AccountsFixtures.user_fixture()
      assert user.confirmed_at == nil

      assert Accounts.post_login_screen(user) == :main_menu
    end

    test "missing config key raises Ecto.NoResultsError (mis-configured app signal)" do
      # Delete the config row to simulate a stale test DB that didn't run seeds.
      # With the typed-accessor migration (quick task 260422-irb), a missing
      # schema key is no longer silently treated as "true" — seeds are
      # authoritative and an empty row means the app is mis-configured. The
      # raise surfaces that loud-and-clear, matching D-03 of the quick task.
      case from(e in Foglet.Config.Entry, where: e.key == "require_email_verification")
           |> FogletBbs.Repo.delete_all() do
        {_, _} -> :ok
      end

      Foglet.Config.invalidate("require_email_verification")

      user = AccountsFixtures.user_fixture()
      assert user.confirmed_at == nil

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.post_login_screen(user)
      end
    end
  end

  describe "update_role/2 (IDNT-06 support)" do
    test "promotes a user to sysop" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, updated} = Accounts.update_role(user, :sysop)
      assert updated.role == :sysop
    end

    test "accepts string role from Mix task input" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, updated} = Accounts.update_role(user, "mod")
      assert updated.role == :mod
    end

    test "rejects invalid role" do
      user = AccountsFixtures.user_fixture()
      assert {:error, cs} = Accounts.update_role(user, :admin)
      refute cs.valid?
    end
  end

  describe "update_profile/2 (ACCT-02/03/04/05)" do
    test "persists valid private profile and account preferences" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, updated} =
               Accounts.update_profile(user, %{
                 location: "Chicago",
                 tagline: "fog rolling in",
                 real_name: "Brendan Turner",
                 timezone: "America/Chicago",
                 theme: "green",
                 preferences: %{"time_format" => "24h"}
               })

      assert updated.location == "Chicago"
      assert updated.tagline == "fog rolling in"
      assert updated.real_name == "Brendan Turner"
      assert updated.timezone == "America/Chicago"
      assert updated.theme == "green"
      assert updated.preferences["time_format"] == "24h"
    end

    test "rejects invalid timezone and leaves the persisted row unchanged" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, user} = Accounts.update_profile(user, %{timezone: "America/Chicago"})

      assert {:error, changeset} =
               Accounts.update_profile(user, %{timezone: "Not/A_Timezone"})

      refute changeset.valid?
      assert Accounts.get_user!(user.id).timezone == "America/Chicago"
    end

    test "rejects invalid time format and leaves the persisted row unchanged" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, user} =
               Accounts.update_profile(user, %{preferences: %{"time_format" => "24h"}})

      assert {:error, changeset} =
               Accounts.update_profile(user, %{preferences: %{"time_format" => "military"}})

      refute changeset.valid?
      assert Accounts.get_user!(user.id).preferences["time_format"] == "24h"
    end

    test "rejects invalid theme and leaves the persisted row unchanged" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, user} = Accounts.update_profile(user, %{theme: "green"})

      assert {:error, changeset} = Accounts.update_profile(user, %{theme: "new_theme"})

      refute changeset.valid?
      assert Accounts.get_user!(user.id).theme == "green"
    end

    test "normalizes blank private profile fields to nil" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, updated} =
               Accounts.update_profile(user, %{
                 location: "   ",
                 tagline: "",
                 real_name: "\t"
               })

      assert updated.location == nil
      assert updated.tagline == nil
      assert updated.real_name == nil
    end

    test "rejects overlong private profile fields" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, user} = Accounts.update_profile(user, %{location: "Home"})

      assert {:error, changeset} =
               Accounts.update_profile(user, %{
                 location: String.duplicate("l", 81),
                 tagline: String.duplicate("t", 121),
                 real_name: String.duplicate("r", 121)
               })

      refute changeset.valid?
      assert Accounts.get_user!(user.id).location == "Home"
    end

    test "preserves unrelated preference keys when saving time format" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, user} =
               Accounts.update_profile(user, %{
                 preferences: %{"time_format" => "12h", "density" => "compact"}
               })

      assert {:ok, updated} =
               Accounts.update_profile(user, %{preferences: %{"time_format" => "24h"}})

      assert updated.preferences["time_format"] == "24h"
      assert updated.preferences["density"] == "compact"
    end
  end

  describe "register_ssh_key/2 (IDNT-04)" do
    test "stores key with computed fingerprint" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      assert key.user_id == user.id
      assert String.starts_with?(key.fingerprint, "SHA256:")
    end

    test "returns {:error, changeset} for invalid key text" do
      user = AccountsFixtures.user_fixture()

      assert {:error, cs} =
               Accounts.register_ssh_key(user, %{label: "bad", public_key: "nope"})

      refute cs.valid?
    end

    test "list_ssh_keys/1 returns user's keys ordered by inserted_at" do
      user = AccountsFixtures.user_fixture()
      k1 = AccountsFixtures.ssh_key_fixture(user)
      assert [%SSHKey{id: found_id}] = Accounts.list_ssh_keys(user)
      assert found_id == k1.id
    end
  end

  describe "get_user_by_public_key/1 (IDNT-04, Phase 3 consumer)" do
    test "finds the registered user by fingerprint" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      assert {:ok, %User{id: id}} = Accounts.get_user_by_public_key(default_key)
      assert id == user.id
    end

    test "returns {:error, :not_found} for unregistered key" do
      other_key =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@ex"

      assert {:error, :not_found} = Accounts.get_user_by_public_key(other_key)
    end

    test "returns {:error, :not_found} for invalid key text" do
      assert {:error, :not_found} = Accounts.get_user_by_public_key("not a key at all")
    end

    test "returns {:error, :not_found} when owning user is deleted" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      {:ok, _} = Accounts.delete_user(user)
      # delete_user removes ssh_keys — we expect :not_found
      assert {:error, :not_found} = Accounts.get_user_by_public_key(default_key)
    end
  end

  describe "deliver_user_confirmation_instructions/2 (IDNT-02)" do
    test "persists a confirm token and returns the URL" do
      user = AccountsFixtures.user_fixture()
      url_fn = fn raw -> "https://example.test/confirm/#{raw}" end
      assert {:ok, url} = Accounts.deliver_user_confirmation_instructions(user, url_fn)
      assert String.starts_with?(url, "https://example.test/confirm/")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
             )
    end

    test "returns {:error, :already_confirmed} if user already confirmed" do
      user = AccountsFixtures.user_fixture()
      {:ok, confirmed} = Accounts.confirm_user(user)

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(confirmed, fn _ -> "x" end)
    end
  end

  describe "deliver_user_reset_password_instructions/2 (IDNT-08)" do
    test "persists a reset_password token and returns the URL" do
      user = AccountsFixtures.user_fixture()
      url_fn = fn raw -> "https://example.test/reset/#{raw}" end
      assert {:ok, url} = Accounts.deliver_user_reset_password_instructions(user, url_fn)
      assert String.contains?(url, "reset/")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end

  describe "transactional email builders (MAIL-02)" do
    test "Foglet.Mailer is the Swoosh mailer boundary using the test adapter" do
      assert Foglet.Mailer.module_info(:module) == Foglet.Mailer
      assert Application.fetch_env!(:foglet_bbs, Foglet.Mailer)[:adapter] == Swoosh.Adapters.Test
    end

    test "verification_code/2 builds a text email addressed to the user" do
      user = AccountsFixtures.user_fixture(%{handle: "mailuser", email: "mailuser@example.test"})

      email = Foglet.Accounts.Email.verification_code(user, "ABC123")

      assert %Swoosh.Email{} = email
      assert email.to == [{"mailuser", "mailuser@example.test"}]
      assert email.from == {"Foglet BBS", "no-reply@localhost"}
      assert email.subject == "Your Foglet verification code"
      assert email.text_body =~ "ABC123"
    end

    test "password_reset/2 builds terminal-native reset instructions without browser URLs" do
      user = AccountsFixtures.user_fixture(%{handle: "resetter", email: "resetter@example.test"})

      email = Foglet.Accounts.Email.password_reset(user, "RESET-TOKEN")

      assert %Swoosh.Email{} = email
      assert email.to == [{"resetter", "resetter@example.test"}]
      assert email.from == {"Foglet BBS", "no-reply@localhost"}
      assert email.subject == "Foglet password reset instructions"
      assert email.text_body =~ "RESET-TOKEN"
      assert email.text_body =~ "SSH terminal"
      refute email.text_body =~ "/users/reset_password"
      refute email.text_body =~ "http://"
      refute email.text_body =~ "https://"
    end
  end

  describe "deliver_verification_code/1 (MAIL-02/MAIL-03)" do
    setup :set_swoosh_global

    setup do
      original_delivery_mode = Config.get("delivery_mode", "no_email")

      on_exit(fn ->
        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
      end)

      :ok
    end

    test "email mode persists an email_verify token and attempts delivery" do
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{handle: "verifyme", email: "verifyme@example.test"})

      assert {:ok, :attempted} = Accounts.deliver_verification_code(user)

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"verifyme", "verifyme@example.test"}]
        assert email.subject == "Your Foglet verification code"
        assert email.text_body =~ "Return to your SSH terminal session"
      end)
    end

    test "no-email mode returns unavailable without creating a token or email" do
      Config.put!("delivery_mode", "no_email")
      user = AccountsFixtures.user_fixture()

      assert {:error, :unavailable} = Accounts.deliver_verification_code(user)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      refute_email_sent()
    end
  end

  describe "request_password_reset_delivery/1 (MAIL-04/MAIL-05)" do
    setup :set_swoosh_global

    setup do
      original_delivery_mode = Config.get("delivery_mode", "no_email")
      original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

      on_exit(fn ->
        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
        Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      end)

      :ok
    end

    test "email mode returns a generic response and delivers for an active handle match" do
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{handle: "resetme", email: "resetme@example.test"})

      assert {:ok, :generic_response} = Accounts.request_password_reset_delivery("  resetme  ")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"resetme", "resetme@example.test"}]
        assert email.subject == "Foglet password reset instructions"
        assert email.text_body =~ "Return to the SSH terminal reset flow"
        refute email.text_body =~ "/users/reset_password"
        refute email.text_body =~ "http://"
        refute email.text_body =~ "https://"
        true
      end)
    end

    test "email mode returns a generic response and delivers for an active email match" do
      Config.put!("delivery_mode", "email")

      user =
        AccountsFixtures.user_fixture(%{handle: "emailreset", email: "emailreset@example.test"})

      assert {:ok, :generic_response} =
               Accounts.request_password_reset_delivery("emailreset@example.test")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert_email_sent()
    end

    test "email mode returns the same generic response for unknown, deleted, pending, and suspended users" do
      Config.put!("delivery_mode", "email")
      deleted = AccountsFixtures.user_fixture(%{handle: "deletedreset"})
      {:ok, _deleted} = Accounts.delete_user(deleted)

      pending =
        AccountsFixtures.user_fixture(%{handle: "pendingreset"})
        |> User.status_changeset(%{status: :pending})
        |> Repo.update!()

      suspended =
        AccountsFixtures.user_fixture(%{handle: "suspendedreset"})
        |> User.status_changeset(%{status: :suspended})
        |> Repo.update!()

      for identifier <- ["nobody", deleted.handle, pending.handle, suspended.handle] do
        assert {:ok, :generic_response} = Accounts.request_password_reset_delivery(identifier)
      end

      for user <- [deleted, pending, suspended] do
        refute Repo.exists?(
                 from t in UserToken,
                   where: t.user_id == ^user.id and t.context == "reset_password"
               )
      end

      refute_email_sent()
    end

    test "email mode returns the same generic response when delivery fails" do
      Config.put!("delivery_mode", "email")

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.AccountsTest.FailingMailerAdapter
      )

      user = AccountsFixtures.user_fixture(%{handle: "failreset"})

      assert {:ok, :generic_response} = Accounts.request_password_reset_delivery("failreset")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "no-email mode returns unavailable without lookup side effects" do
      Config.put!("delivery_mode", "no_email")
      user = AccountsFixtures.user_fixture(%{handle: "noemailreset"})

      assert {:error, :unavailable} = Accounts.request_password_reset_delivery("noemailreset")

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      refute_email_sent()
    end
  end

  describe "reset_user_password/2 (IDNT-08)" do
    test "updates password and invalidates outstanding reset tokens" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert {:ok, updated} = Accounts.reset_user_password(user, %{password: "brandnew1"})
      assert Argon2.verify_pass("brandnew1", updated.password_hash)
      refute Argon2.verify_pass("original1", updated.password_hash)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end

  describe "delete_user/1 (IDNT-07)" do
    test "clears PII on the user row and preserves the row for FK integrity" do
      user =
        AccountsFixtures.user_fixture(%{
          email: "victim@example.com"
        })

      # seed some profile fields that must be cleared
      {:ok, user} = Accounts.update_profile(user, %{location: "Nowhere", tagline: "ahoy"})

      assert {:ok, anonymized} = Accounts.delete_user(user)
      assert anonymized.deleted_at
      refute anonymized.location
      refute anonymized.tagline
      refute anonymized.real_name
      assert anonymized.email == "deleted-#{user.id}@localhost"
      assert anonymized.password_hash == "invalid-deleted"

      # Row still exists (preserved for FK integrity)
      assert Repo.get(User, user.id)
    end

    test "deletes all ssh_keys and user_tokens for the deleted user" do
      user = AccountsFixtures.user_fixture()
      _ = AccountsFixtures.ssh_key_fixture(user)

      {_raw, _} = AccountsFixtures.user_token_fixture(user, "confirm")
      {_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert Repo.aggregate(from(k in SSHKey, where: k.user_id == ^user.id), :count) == 1
      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 2

      {:ok, _} = Accounts.delete_user(user)

      assert Repo.aggregate(from(k in SSHKey, where: k.user_id == ^user.id), :count) == 0
      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 0
    end

    test "rewrites authored posts to the tombstone user" do
      user = AccountsFixtures.user_fixture()
      tombstone = insert_tombstone_user!()
      post = insert_post_authored_by!(user)

      assert {:ok, _} = Accounts.delete_user(user)

      reloaded_post =
        Post
        |> Repo.get!(post.id)
        |> Repo.preload(:user)

      assert reloaded_post.user_id == tombstone.id
      assert reloaded_post.user.handle == "[deleted]"
    end
  end

  describe "tombstone_user_id/0" do
    test "returns a fixed UUID string" do
      assert Accounts.tombstone_user_id() == "00000000-0000-0000-0000-000000000001"
    end
  end

  defp insert_tombstone_user! do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(%User{
      id: Accounts.tombstone_user_id(),
      handle: "[deleted]",
      email: "tombstone@localhost",
      password_hash: "invalid-tombstone",
      confirmed_at: now,
      role: :user,
      show_in_last_callers: false
    })
  end

  defp insert_post_authored_by!(%User{} = user) do
    unique = System.unique_integer([:positive])

    category =
      %Category{}
      |> Category.changeset(%{name: "Category #{unique}"})
      |> Repo.insert!()

    board =
      %Board{}
      |> Board.changeset(%{
        slug: "board-#{unique}",
        name: "Board #{unique}",
        category_id: category.id
      })
      |> Repo.insert!()

    thread =
      %Thread{board_id: board.id, created_by_id: user.id}
      |> Thread.creation_changeset(%{title: "Thread #{unique}"})
      |> Repo.insert!()

    %Post{
      message_number: 1,
      board_id: board.id,
      thread_id: thread.id,
      user_id: user.id
    }
    |> Post.creation_changeset(%{body: "Authored by deleted user"})
    |> Repo.insert!()
  end
end

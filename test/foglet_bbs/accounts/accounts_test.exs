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

  @alternate_ssh_public_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@example"

  describe "register_user/1 (IDNT-01)" do
    setup :set_swoosh_global

    setup do
      Config.init_cache()
      current_registration_mode = Config.get("registration_mode", "open")
      current_delivery_mode = Config.get("delivery_mode", "no_email")
      original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

      on_exit(fn ->
        Config.put!("registration_mode", current_registration_mode)
        Config.put!("delivery_mode", current_delivery_mode)
        Config.invalidate("registration_mode")
        Config.invalidate("delivery_mode")
        Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      end)

      :ok
    end

    test "creates a user with hashed password" do
      attrs = AccountsFixtures.valid_user_attributes(%{password: "opensesame"})
      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.password_hash != "opensesame"
      assert Argon2.verify_pass("opensesame", user.password_hash)
    end

    test "creates a registration SSH key when offered a public key" do
      attrs =
        AccountsFixtures.valid_user_attributes(%{
          offered_ssh_public_key: AccountsFixtures.default_ssh_public_key()
        })

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)

      assert [
               %SSHKey{
                 user_id: user_id,
                 label: "Registration SSH key",
                 public_key: public_key,
                 fingerprint: "SHA256:" <> _rest
               }
             ] = Accounts.list_ssh_keys(user)

      assert user_id == user.id
      assert public_key == AccountsFixtures.default_ssh_public_key()
    end

    test "does not create an SSH key when no key is offered" do
      attrs = AccountsFixtures.valid_user_attributes()

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert [] = Accounts.list_ssh_keys(user)
    end

    test "rejects duplicate offered public key without orphaning a user" do
      owner = AccountsFixtures.user_fixture()

      assert {:ok, _key} =
               Accounts.register_ssh_key(owner, %{
                 label: "laptop",
                 public_key: AccountsFixtures.default_ssh_public_key()
               })

      attrs =
        AccountsFixtures.valid_user_attributes(%{
          handle: "duplicatekeyuser",
          email: "duplicatekeyuser@example.com",
          offered_ssh_public_key: AccountsFixtures.default_ssh_public_key()
        })

      assert {:error, {:ssh_key, "That SSH public key is already registered."}} =
               Accounts.register_user(attrs)

      refute Accounts.get_user_by_handle("duplicatekeyuser")
    end

    test "rejects malformed offered public key without orphaning a user" do
      attrs =
        AccountsFixtures.valid_user_attributes(%{
          handle: "invalidkeyuser",
          email: "invalidkeyuser@example.com",
          offered_ssh_public_key: "not an openssh key"
        })

      assert {:error, {:ssh_key, "That SSH public key is not valid."}} =
               Accounts.register_user(attrs)

      refute Accounts.get_user_by_handle("invalidkeyuser")
    end

    test "register_pending_user/1 creates a pending user with a registration SSH key" do
      attrs =
        AccountsFixtures.valid_user_attributes(%{
          offered_ssh_public_key: @alternate_ssh_public_key
        })

      assert {:ok, %User{status: :pending} = user} = Accounts.register_pending_user(attrs)

      assert [%SSHKey{label: "Registration SSH key", public_key: public_key}] =
               Accounts.list_ssh_keys(user)

      assert public_key == @alternate_ssh_public_key
      assert Repo.get!(User, user.id).status == :pending
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

    test "sysop-approved registration emails active sysops when delivery is available" do
      sysop =
        AccountsFixtures.user_fixture(%{
          handle: "approvalsysop",
          email: "approvalsysop@example.test"
        })

      assert {:ok, sysop} = Accounts.update_role(sysop, :sysop)

      Config.put!("registration_mode", "sysop_approved")
      Config.put!("delivery_mode", "email")

      attrs =
        AccountsFixtures.valid_user_attributes(%{
          handle: "pendingnew",
          email: "pendingnew@example.test"
        })

      assert {:ok, %User{status: :pending}} = Accounts.register_user(attrs)

      assert_email_sent(fn email ->
        assert email.to == [{sysop.handle, sysop.email}]
        assert email.subject == "Foglet account awaiting approval"
        assert email.text_body =~ "Handle: pendingnew"
        assert email.text_body =~ "Email: pendingnew@example.test"
      end)
    end

    test "sysop-approved registration skips sysop email in no-email mode" do
      sysop =
        AccountsFixtures.user_fixture(%{
          handle: "noemailsysop",
          email: "noemailsysop@example.test"
        })

      assert {:ok, _sysop} = Accounts.update_role(sysop, :sysop)

      Config.put!("registration_mode", "sysop_approved")
      Config.put!("delivery_mode", "no_email")

      attrs = AccountsFixtures.valid_user_attributes(%{handle: "pendingnoemail"})

      assert {:ok, %User{status: :pending}} = Accounts.register_user(attrs)
      refute_email_sent()
    end
  end

  # authenticate_by_password/2 tests → test/foglet_bbs/accounts/auth_test.exs

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

  describe "transition_user_status/3" do
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

    test "active sysop can perform the locked transition graph" do
      Config.put!("delivery_mode", "no_email")
      sysop = user_with_status(:active, "sysoptransition", :sysop)

      pending_to_active = user_with_status(:pending, "pendingactive")
      assert {:ok, result} = Accounts.transition_user_status(sysop, pending_to_active, :active)
      assert %{from: :pending, to: :active, delivery: :skipped_no_email} = result
      assert result.user.status == :active

      pending_to_rejected = user_with_status(:pending, "pendingrejected")

      assert {:ok, result} =
               Accounts.transition_user_status(sysop, pending_to_rejected.handle, "rejected")

      assert %{from: :pending, to: :rejected, delivery: :skipped_no_email} = result
      assert result.user.status == :rejected

      active_to_suspended = AccountsFixtures.user_fixture(%{handle: "activesuspended"})

      assert {:ok, result} =
               Accounts.transition_user_status(sysop, active_to_suspended.id, :suspended)

      assert %{from: :active, to: :suspended, delivery: :not_applicable} = result
      assert result.user.status == :suspended

      suspended_to_active = user_with_status(:suspended, "suspendedactive")
      assert {:ok, result} = Accounts.transition_user_status(sysop, suspended_to_active, :active)
      assert %{from: :suspended, to: :active, delivery: :not_applicable} = result
      assert result.user.status == :active
    end

    test "email mode sends approval and rejection notifications for pending transitions" do
      Config.put!("delivery_mode", "email")
      sysop = user_with_status(:active, "sysopnotify", :sysop)

      approve =
        user_with_status(:pending, "notifyapprove")
        |> Ecto.Changeset.change(%{email: "notifyapprove@example.test"})
        |> Repo.update!()

      reject =
        user_with_status(:pending, "notifyreject")
        |> Ecto.Changeset.change(%{email: "notifyreject@example.test"})
        |> Repo.update!()

      assert {:ok, %{delivery: :attempted}} =
               Accounts.transition_user_status(sysop, approve, :active)

      assert_email_sent(fn email ->
        assert email.to == [{"notifyapprove", "notifyapprove@example.test"}]
        assert email.subject == "Your Foglet account was approved"
      end)

      assert {:ok, %{delivery: :attempted}} =
               Accounts.transition_user_status(sysop, reject, :rejected)

      assert_email_sent(fn email ->
        assert email.to == [{"notifyreject", "notifyreject@example.test"}]
        assert email.subject == "Your Foglet registration was rejected"
      end)
    end

    test "status delivery failure does not roll back a valid transition" do
      Config.put!("delivery_mode", "email")

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.AccountsTest.FailingMailerAdapter
      )

      sysop = user_with_status(:active, "sysopfailnotify", :sysop)
      pending = user_with_status(:pending, "failnotify")

      assert {:ok, %{delivery: {:failed, :forced_failure}, user: updated}} =
               Accounts.transition_user_status(sysop, pending, :active)

      assert updated.status == :active
      assert Accounts.get_user!(pending.id).status == :active
    end

    test "invalid transitions do not mutate persisted status" do
      sysop = user_with_status(:active, "sysopinvalid", :sysop)

      for {from, to, handle} <- [
            {:rejected, :active, "rejectedactive"},
            {:suspended, :rejected, "suspendedrejected"},
            {:active, :rejected, "activerejected"},
            {:pending, :suspended, "pendingsuspended"}
          ] do
        user = user_with_status(from, handle)

        assert {:error, :invalid_transition} = Accounts.transition_user_status(sysop, user, to)
        assert Accounts.get_user!(user.id).status == from
      end
    end

    test "sysop cannot change their own status through the administration boundary" do
      sysop = user_with_status(:active, "sysopself", :sysop)

      assert {:error, :invalid_transition} =
               Accounts.transition_user_status(sysop, sysop, :suspended)

      assert Accounts.get_user!(sysop.id).status == :active
    end

    test "non-active non-sysop actors are forbidden before target mutation" do
      target = user_with_status(:pending, "forbiddentarget")

      for actor <- [
            AccountsFixtures.user_fixture(%{handle: "regularactor"}),
            AccountsFixtures.user_fixture(%{handle: "modactor", role: :mod}),
            user_with_status(:pending, "pendingactor", :sysop),
            user_with_status(:rejected, "rejectedactor", :sysop),
            user_with_status(:suspended, "suspendedactor", :sysop),
            deleted_user_fixture("deletedactor"),
            nil
          ] do
        assert {:error, :forbidden} = Accounts.transition_user_status(actor, target, :active)
      end

      assert Accounts.get_user!(target.id).status == :pending
    end

    test "unknown target and deleted target return tagged errors" do
      sysop = user_with_status(:active, "sysopmissing", :sysop)
      deleted = deleted_user_fixture("deletedtarget")

      assert {:error, :not_found} =
               Accounts.transition_user_status(sysop, "missing-target", :active)

      assert {:error, :deleted} = Accounts.transition_user_status(sysop, deleted.handle, :active)
    end
  end

  describe "valid_status_transitions/1" do
    @describetag :valid_status_transitions

    test ":pending -> [:active, :rejected]" do
      assert Accounts.valid_status_transitions(:pending) == [:active, :rejected]
    end

    test ":active -> [:suspended]" do
      assert Accounts.valid_status_transitions(:active) == [:suspended]
    end

    test ":suspended -> [:active]" do
      assert Accounts.valid_status_transitions(:suspended) == [:active]
    end

    test ":rejected -> []" do
      assert Accounts.valid_status_transitions(:rejected) == []
    end
  end

  describe "list_user_status_admin_targets/1" do
    test "returns non-deleted users grouped by status for sysops" do
      sysop = user_with_status(:active, "sysoplist", :sysop)
      pending = user_with_status(:pending, "listpending")
      active = AccountsFixtures.user_fixture(%{handle: "listactive"})
      suspended = user_with_status(:suspended, "listsuspended")
      rejected = user_with_status(:rejected, "listrejected")
      deleted = deleted_user_fixture("listdeleted")

      assert {:ok, targets} = Accounts.list_user_status_admin_targets(sysop)

      assert pending.id in Enum.map(targets.pending, & &1.id)
      assert active.id in Enum.map(targets.active, & &1.id)
      assert suspended.id in Enum.map(targets.suspended, & &1.id)
      assert rejected.id in Enum.map(targets.rejected, & &1.id)
      refute deleted.id in (targets |> Map.values() |> List.flatten() |> Enum.map(& &1.id))
    end

    test "returns forbidden for non-sysops" do
      actor = AccountsFixtures.user_fixture()

      assert {:error, :forbidden} = Accounts.list_user_status_admin_targets(actor)
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

  defp user_with_status(status, handle, role \\ :user) do
    {:ok, user} =
      AccountsFixtures.user_fixture(%{handle: handle})
      |> Accounts.update_role(role)

    user
    |> User.status_changeset(%{status: status})
    |> Repo.update!()
  end

  defp deleted_user_fixture(handle) do
    user = AccountsFixtures.user_fixture(%{handle: handle})
    {:ok, deleted} = Accounts.delete_user(user)
    deleted
  end

  describe "register_ssh_key/2 (IDNT-04, KEYS-02, KEYS-03, KEYS-04)" do
    test "KEYS-02 stores key with computed fingerprint" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, key} =
               Accounts.register_ssh_key(user, %{
                 label: "laptop",
                 public_key: AccountsFixtures.default_ssh_public_key()
               })

      assert key.user_id == user.id
      assert String.starts_with?(key.fingerprint, "SHA256:")
    end

    test "KEYS-02 returns {:error, changeset} for blank and invalid key attrs" do
      user = AccountsFixtures.user_fixture()

      assert {:error, blank_cs} =
               Accounts.register_ssh_key(user, %{label: "", public_key: ""})

      refute blank_cs.valid?
      assert %{label: ["can't be blank"], public_key: ["can't be blank"]} = errors_on(blank_cs)

      assert {:error, cs} =
               Accounts.register_ssh_key(user, %{label: "bad", public_key: "nope"})

      refute cs.valid?
    end

    test "KEYS-02 rejects duplicate global fingerprint" do
      user_a = AccountsFixtures.user_fixture()
      user_b = AccountsFixtures.user_fixture()
      public_key = AccountsFixtures.default_ssh_public_key()

      assert {:ok, _key} =
               Accounts.register_ssh_key(user_a, %{label: "laptop", public_key: public_key})

      assert {:error, changeset} =
               Accounts.register_ssh_key(user_b, %{label: "workstation", public_key: public_key})

      assert "has already been taken" in errors_on(changeset).fingerprint
    end

    test "KEYS-02 rejects duplicate label for the same user" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, _key} =
               Accounts.register_ssh_key(user, %{
                 label: "laptop",
                 public_key: AccountsFixtures.default_ssh_public_key()
               })

      assert {:error, changeset} =
               Accounts.register_ssh_key(user, %{
                 label: "laptop",
                 public_key: @alternate_ssh_public_key
               })

      assert "has already been taken" in errors_on(changeset).label
    end

    test "KEYS-03 list_ssh_keys/1 returns user's keys ordered by inserted_at" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      k1 = AccountsFixtures.ssh_key_fixture(user)
      k2 = AccountsFixtures.ssh_key_fixture(user, %{public_key: @alternate_ssh_public_key})

      _other_key =
        AccountsFixtures.ssh_key_fixture(other_user, %{
          public_key:
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKwR0WDlTnrzZcQ36aGfcf70IUiKVrR0P0gnMPD6e1qR third@example"
        })

      assert [%SSHKey{id: first_id}, %SSHKey{id: second_id}] = Accounts.list_ssh_keys(user)
      assert first_id == k1.id
      assert second_id == k2.id
    end

    test "KEYS-04 revoke_ssh_key/2 hard-deletes an owned key" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)

      assert {:ok, %SSHKey{id: key_id}} = Accounts.revoke_ssh_key(user, key.id)
      assert key_id == key.id
      assert Repo.get(SSHKey, key.id) == nil
    end

    test "KEYS-04 revoke_ssh_key/2 rejects another user's key without deleting it" do
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(owner)

      assert {:error, :not_found} = Accounts.revoke_ssh_key(other_user, key.id)
      assert %SSHKey{id: key_id} = Repo.get(SSHKey, key.id)
      assert key_id == key.id
    end
  end

  # get_user_by_public_key/1 tests → test/foglet_bbs/accounts/auth_test.exs
  # authenticate_by_public_key/1 tests → test/foglet_bbs/accounts/auth_test.exs

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

    test "approval and rejection notifications build status email messages" do
      approved =
        AccountsFixtures.user_fixture(%{handle: "approvedmail", email: "approved@example.test"})

      rejected =
        AccountsFixtures.user_fixture(%{handle: "rejectedmail", email: "rejected@example.test"})

      approval = Foglet.Accounts.Email.approval_notification(approved)
      rejection = Foglet.Accounts.Email.rejection_notification(rejected)

      assert approval.to == [{"approvedmail", "approved@example.test"}]
      assert approval.from == {"Foglet BBS", "no-reply@localhost"}
      assert approval.subject == "Your Foglet account was approved"

      assert rejection.to == [{"rejectedmail", "rejected@example.test"}]
      assert rejection.from == {"Foglet BBS", "no-reply@localhost"}
      assert rejection.subject == "Your Foglet registration was rejected"
    end
  end

  # deliver_verification_code/1 tests → test/foglet_bbs/accounts/verification_test.exs
  # request_password_reset_delivery/1 tests → test/foglet_bbs/accounts/verification_test.exs
  # reset_user_password/2 tests → test/foglet_bbs/accounts/verification_test.exs

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

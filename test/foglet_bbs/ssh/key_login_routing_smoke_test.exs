defmodule Foglet.SSH.KeyLoginRoutingSmokeTest do
  @moduledoc """
  FOG-119 SSH/TUI harness smoke for the FOG-114 umbrella.

  End-to-end verification that an unregistered offered SSH key flows through
  registration with the opt-in checkbox and produces the correct post-login
  routing on the next connection, for every gate the umbrella must respect.

  Each scenario:
    1. stash a fresh, unregistered ed25519 OpenSSH key for an inbound peer,
    2. drive the SSH channel-up and assert the guest TUI context carries the
       offered key text,
    3. submit registration through `Foglet.Accounts.register_user/1` (or
       `register_pending_user/1`), with or without `:offered_ssh_public_key`
       to model the checkbox state,
    4. stash the same key for a fresh peer to model reconnect,
    5. assert the routed `Foglet.TUI.App` initial screen and persistence shape.
  """

  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.{Auth, SSHKey, User}
  alias Foglet.Config
  alias Foglet.SSH.{CLIHandler, PubkeyStash, RateLimiter}
  alias Foglet.TUI.App, as: TUIApp
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  setup do
    reset_cli_counter!()
    reset_pubkey_stash!()
    warm_login_config_cache!()
    start_supervised!({RateLimiter, clean_period: :timer.minutes(10)})

    Config.init_cache()
    original_mode = Config.get("registration_mode", "open")
    original_delivery = Config.get("delivery_mode", "no_email")
    original_require_verification = Config.get("require_email_verification", true)

    on_exit(fn ->
      Config.put!("registration_mode", original_mode)
      Config.put!("delivery_mode", original_delivery)
      Config.put!("require_email_verification", original_require_verification)
      Config.invalidate("registration_mode")
      Config.invalidate("delivery_mode")
      Config.invalidate("require_email_verification")
    end)

    :ok
  end

  describe "FOG-119 — offered-key registration → key-login routing" do
    test "1. open registration, verify not required → main_menu on reconnect" do
      configure!("open", verify: false)
      key = generate_unregistered_keypair!()

      # First connection: unregistered key → guest, offered key carried.
      first_ctx = connect_and_build_context!(peer(:p1), key)
      assert_offered_guest!(first_ctx, key.openssh_text)

      # Submit registration with the checkbox checked.
      attrs = registration_attrs(:open, key.openssh_text)
      {:ok, user} = Accounts.register_user(attrs)
      assert user.status == :active
      assert_persisted_registration_key!(user, key.openssh_text)

      # Reconnect: same key, fresh peer, fresh stash entry.
      second_ctx = connect_and_build_context!(peer(:p2), key)

      assert second_ctx.session_context.user.id == user.id
      assert second_ctx.session_context.pubkey_authenticated
      assert second_ctx.session_context.offered_ssh_public_key == nil

      {:ok, state} = TUIApp.init(second_ctx)
      assert state.current_screen == :main_menu
      assert state.modal == nil
    end

    test "2. open registration, verify required → verify on reconnect (NOT main menu)" do
      configure!("open", verify: true)
      key = generate_unregistered_keypair!()

      first_ctx = connect_and_build_context!(peer(:p1), key)
      assert_offered_guest!(first_ctx, key.openssh_text)

      {:ok, user} = Accounts.register_user(registration_attrs(:open, key.openssh_text))
      assert user.status == :active
      assert is_nil(user.confirmed_at)
      assert_persisted_registration_key!(user, key.openssh_text)

      second_ctx = connect_and_build_context!(peer(:p2), key)
      assert second_ctx.session_context.user.id == user.id
      assert second_ctx.session_context.pubkey_authenticated
      # `:verify` is a gated outcome — offered key is intentionally not re-carried.
      assert second_ctx.session_context.offered_ssh_public_key == nil

      {:ok, state} = TUIApp.init(second_ctx)
      assert state.current_screen == :verify
      refute state.current_screen == :main_menu
      assert state.modal == nil
    end

    test "3. sysop-approved registration → pending block on reconnect (NOT main menu)" do
      configure!("sysop_approved", verify: false)
      key = generate_unregistered_keypair!()

      first_ctx = connect_and_build_context!(peer(:p1), key)
      assert_offered_guest!(first_ctx, key.openssh_text)

      attrs = registration_attrs(:sysop, key.openssh_text)
      {:ok, user} = Accounts.register_user(attrs)
      assert user.status == :pending
      assert_persisted_registration_key!(user, key.openssh_text)

      second_ctx = connect_and_build_context!(peer(:p2), key)
      assert second_ctx.session_context.user.id == user.id
      assert second_ctx.session_context.pubkey_authenticated
      assert second_ctx.session_context.offered_ssh_public_key == nil

      {:ok, state} = TUIApp.init(second_ctx)
      assert state.current_screen == :login
      refute state.current_screen == :main_menu
      assert %Foglet.TUI.Modal{type: :error, message: msg} = state.modal
      assert msg =~ "waiting for sysop approval"
    end

    test "4. invite-only registration → main_menu, invite consumed, key persisted" do
      configure!("invite_only", verify: false)
      key = generate_unregistered_keypair!()

      issuer = sysop_user_fixture()
      invite = AccountsFixtures.invite_fixture(issuer)

      first_ctx = connect_and_build_context!(peer(:p1), key)
      assert_offered_guest!(first_ctx, key.openssh_text)

      attrs =
        registration_attrs(:invite, key.openssh_text)
        |> Map.put(:invite_code, invite.code)

      {:ok, user} = Accounts.register_user(attrs)
      assert user.status == :active
      assert_persisted_registration_key!(user, key.openssh_text)

      reloaded_invite = Repo.get!(Foglet.Accounts.Invite, invite.id)
      refute is_nil(reloaded_invite.consumed_at)
      assert reloaded_invite.consumed_by_user_id == user.id

      second_ctx = connect_and_build_context!(peer(:p2), key)
      assert second_ctx.session_context.user.id == user.id
      assert second_ctx.session_context.pubkey_authenticated

      {:ok, state} = TUIApp.init(second_ctx)
      assert state.current_screen == :main_menu
      assert state.modal == nil
    end

    test "5. negative — checkbox unchecked → guest on reconnect, no ssh_keys row" do
      configure!("open", verify: false)
      key = generate_unregistered_keypair!()

      first_ctx = connect_and_build_context!(peer(:p1), key)
      assert_offered_guest!(first_ctx, key.openssh_text)

      # Submit registration WITHOUT offered_ssh_public_key (checkbox unchecked).
      attrs = registration_attrs(:open, nil)
      {:ok, user} = Accounts.register_user(attrs)
      assert user.status == :active

      # No ssh_keys row was created.
      assert ssh_keys_for(user) == []
      assert {:error, :not_found} = Auth.lookup_by_public_key(key.openssh_text)

      # Reconnect: key still unmatched, guest session, offered key carried.
      second_ctx = connect_and_build_context!(peer(:p2), key)
      assert second_ctx.session_context.user == nil
      refute second_ctx.session_context.pubkey_authenticated
      assert second_ctx.session_context.offered_ssh_public_key == key.openssh_text

      {:ok, state} = TUIApp.init(second_ctx)
      assert state.current_screen == :login
      assert state.modal == nil
    end

    test "6. negative — rejected/suspended/deleted users cannot key-login to main_menu" do
      configure!("open", verify: false)

      check_blocked_status!(:rejected, fn modal ->
        assert modal.type == :error
        assert modal.message =~ "turned down"
      end)

      check_blocked_status!(:suspended, fn modal ->
        assert modal.type == :error
        assert modal.message =~ "suspended"
      end)

      # Deleted users: the lookup hides them entirely. The carrier is reset, so
      # the connection presents as a brand-new guest with the key offered for
      # re-registration — never as the deleted account.
      key_deleted = generate_unregistered_keypair!()
      user_deleted = active_user_with_key!(key_deleted.openssh_text)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, _} =
        user_deleted
        |> Ecto.Changeset.change(deleted_at: now)
        |> Repo.update()

      assert {:error, :not_found} = Auth.lookup_by_public_key(key_deleted.openssh_text)

      ctx = connect_and_build_context!(peer(:p_deleted), key_deleted)
      assert ctx.session_context.user == nil
      refute ctx.session_context.pubkey_authenticated
      assert ctx.session_context.offered_ssh_public_key == key_deleted.openssh_text

      {:ok, state} = TUIApp.init(ctx)
      assert state.current_screen == :login
      refute state.current_screen == :main_menu
      assert state.modal == nil
    end
  end

  # --- Helpers ---

  defp check_blocked_status!(target_status, modal_assertion) do
    key = generate_unregistered_keypair!()
    user = active_user_with_key!(key.openssh_text)

    {:ok, _} =
      user
      |> User.status_changeset(%{status: target_status})
      |> Repo.update()

    ctx = connect_and_build_context!(peer({:gated, target_status}), key)

    assert ctx.session_context.user.id == user.id
    assert ctx.session_context.user.status == target_status
    assert ctx.session_context.pubkey_authenticated
    # Gated lookups intentionally do not re-carry the offered key.
    assert ctx.session_context.offered_ssh_public_key == nil

    {:ok, state} = TUIApp.init(ctx)
    assert state.current_screen == :login
    refute state.current_screen == :main_menu
    assert %Foglet.TUI.Modal{} = state.modal
    modal_assertion.(state.modal)
  end

  defp connect_and_build_context!(peer, %{public_key: public_key}) do
    PubkeyStash.put(peer, public_key)

    assert {:ok, returned_state} =
             CLIHandler.channel_up_for_test(%CLIHandler{}, fresh_channel_id(), nil, peer)

    CLIHandler.context_for_test(returned_state, 80, 24)
  end

  defp assert_offered_guest!(ctx, openssh_text) do
    sc = ctx.session_context
    assert sc.user == nil
    assert sc.user_id == nil
    refute sc.pubkey_authenticated
    assert sc.offered_ssh_public_key == openssh_text
  end

  defp configure!(registration_mode, opts) do
    Config.put!("registration_mode", registration_mode)
    Config.put!("require_email_verification", Keyword.get(opts, :verify, false))
    Config.put!("delivery_mode", Keyword.get(opts, :delivery, "no_email"))
    Config.invalidate("registration_mode")
    Config.invalidate("require_email_verification")
    Config.invalidate("delivery_mode")
    :ok
  end

  defp registration_attrs(:open, openssh_text), do: base_attrs(openssh_text)
  defp registration_attrs(:sysop, openssh_text), do: base_attrs(openssh_text)
  defp registration_attrs(:invite, openssh_text), do: base_attrs(openssh_text)

  defp base_attrs(openssh_text) do
    suffix = System.unique_integer([:positive, :monotonic])

    attrs = %{
      handle: "fog119_#{suffix}",
      email: "fog119_#{suffix}@example.com",
      password: "correct horse battery"
    }

    case openssh_text do
      nil -> attrs
      text when is_binary(text) -> Map.put(attrs, :offered_ssh_public_key, text)
    end
  end

  defp active_user_with_key!(openssh_text) do
    user = AccountsFixtures.user_fixture()
    AccountsFixtures.ssh_key_fixture(user, %{public_key: openssh_text, label: "fog119-fixture"})
    user
  end

  defp sysop_user_fixture do
    user = AccountsFixtures.user_fixture()
    {:ok, promoted} = user |> Ecto.Changeset.change(role: :sysop) |> Repo.update()
    promoted
  end

  defp assert_persisted_registration_key!(%User{id: id}, openssh_text) do
    {:ok, fingerprint} = SSHKey.compute_fingerprint(openssh_text)
    keys = Repo.all(Ecto.Query.from(k in SSHKey, where: k.user_id == ^id))
    assert Enum.any?(keys, &(&1.fingerprint == fingerprint)),
           "expected an ssh_keys row for user #{id} matching offered key fingerprint"
  end

  defp ssh_keys_for(%User{id: id}) do
    Repo.all(Ecto.Query.from(k in SSHKey, where: k.user_id == ^id))
  end

  defp generate_unregistered_keypair! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "foglet_fog119_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    key_path = Path.join(dir, "id_ed25519")

    {_, 0} =
      System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", "", "-C", "fog119"],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm_rf!(dir) end)

    openssh_text =
      (key_path <> ".pub")
      |> File.read!()
      |> String.trim()

    [{public_key, _}] = :ssh_file.decode(openssh_text, :public_key)

    # Match the exact byte-for-byte shape `:ssh_file.encode/2` produces — the
    # CLIHandler carries the encoded text verbatim into `SessionContext`,
    # including the trailing ` \n` the encoder appends. Do not trim here, or
    # the carry-through assertions become a vacuous post-trim comparison.
    canonical_text =
      public_key
      |> then(&:ssh_file.encode([{&1, []}], :openssh_key))
      |> to_string()

    %{public_key: public_key, openssh_text: canonical_text}
  end

  defp peer(tag) do
    n = :erlang.phash2(tag, 250) + 2
    {{10, 119, 0, n}, 11_900 + n}
  end

  defp fresh_channel_id, do: System.unique_integer([:positive, :monotonic])

  defp warm_login_config_cache! do
    _ = Config.registration_mode()
    _ = Config.delivery_mode()
  end

  defp reset_pubkey_stash! do
    if :ets.whereis(PubkeyStash) != :undefined do
      :ets.delete(PubkeyStash)
    end

    PubkeyStash.init()
  end

  defp reset_cli_counter! do
    table = CLIHandler.Counter

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    CLIHandler.init_counter()
  end
end

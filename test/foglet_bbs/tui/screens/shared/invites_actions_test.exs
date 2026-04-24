defmodule Foglet.TUI.Screens.Shared.InvitesActionsTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Config
  alias Foglet.TUI.Screens.Shared.{InvitesActions, InvitesState}
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  describe "load/2 and refresh/2" do
    test "load lists invites through Accounts status maps" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)

      assert {:ok, %InvitesState{} = state} = InvitesActions.load(sysop, InvitesState.new())

      assert [%{code: code, issuer_id: issuer_id, status: :available}] = state.items
      assert code == invite.code
      assert issuer_id == sysop.id
      assert state.selected_index == 0
      assert state.error == nil
    end

    test "refresh preserves last generated code while replacing items" do
      sysop = actor_fixture(:sysop)
      AccountsFixtures.invite_fixture(sysop)

      state = InvitesState.new(last_generated_code: "INVITEKEEP")

      assert {:ok, refreshed} = InvitesActions.refresh(sysop, state)
      assert [%{status: :available}] = refreshed.items
      assert refreshed.last_generated_code == "INVITEKEEP"
    end
  end

  describe "generate/2" do
    setup :restore_invite_config

    test "generate persists exactly one invite and refreshes from Accounts list" do
      sysop = actor_fixture(:sysop)
      assert {:ok, before_items} = Accounts.list_invites(sysop)

      assert {:ok, state} = InvitesActions.generate(sysop, InvitesState.new(items: before_items))

      assert {:ok, after_items} = Accounts.list_invites(sysop)
      assert length(after_items) == length(before_items) + 1
      assert state.items == after_items
      assert state.last_generated_code == hd(after_items).code
      assert state.error == nil
    end

    test "maps Accounts errors and preserves local state on failed generate" do
      sysop = actor_fixture(:sysop)
      user = AccountsFixtures.user_fixture()

      state =
        InvitesState.new(items: [%{code: "KEEP", status: :available}], last_generated_code: "OLD")

      Config.put!("invite_code_generators", "sysop_only", sysop.id)

      assert {:ok, failed} = InvitesActions.generate(user, state)
      assert failed.items == state.items
      assert failed.selected_index == state.selected_index
      assert failed.last_generated_code == "OLD"
      assert failed.error == "You are not allowed to manage invites."
    end
  end

  describe "selection" do
    test "select_next and select_prev clamp to available items" do
      state = InvitesState.new(items: [%{code: "A"}, %{code: "B"}])

      assert InvitesActions.select_next(state).selected_index == 1

      assert state
             |> InvitesActions.select_next()
             |> InvitesActions.select_next()
             |> Map.fetch!(:selected_index) == 1

      assert state
             |> InvitesActions.select_next()
             |> InvitesActions.select_prev()
             |> Map.fetch!(:selected_index) == 0

      assert InvitesActions.select_prev(state).selected_index == 0
    end
  end

  describe "revoke_selected/2" do
    test "available invite revoke sets persisted revoked_at and refreshed rendered status revoked" do
      sysop = actor_fixture(:sysop)
      AccountsFixtures.invite_fixture(sysop, %{code: "INVITEAVAILABLE001"})
      AccountsFixtures.invite_fixture(sysop, %{code: "INVITEAVAILABLE002"})
      {:ok, items} = Accounts.list_invites(sysop)
      selected_index = Enum.find_index(items, &(&1.code == "INVITEAVAILABLE001"))

      state = InvitesState.new(items: items, selected_index: selected_index)

      assert {:ok, revoked_state} = InvitesActions.revoke_selected(sysop, state)

      assert %{status: :revoked, revoked_at: %DateTime{}} =
               Enum.find(revoked_state.items, &(&1.code == "INVITEAVAILABLE001"))

      assert revoked_state.error == nil

      assert {:ok, %{status: :revoked, revoked_at: %DateTime{}}} =
               Accounts.get_invite_status("INVITEAVAILABLE001")
    end

    test "unauthorized actor revoke sets error and leaves persisted invite fields unchanged" do
      sysop = actor_fixture(:sysop)
      user = AccountsFixtures.user_fixture()
      invite = AccountsFixtures.invite_fixture(sysop)
      {:ok, items} = Accounts.list_invites(sysop)
      state = InvitesState.new(items: items, selected_index: 0, last_generated_code: "OLD")
      before_status = invite_status!(invite.code)

      assert {:ok, failed} = InvitesActions.revoke_selected(user, state)
      assert failed.items == state.items
      assert failed.selected_index == state.selected_index
      assert failed.last_generated_code == "OLD"
      assert failed.error == "You are not allowed to manage invites."

      assert invite_status!(invite.code) == before_status
    end

    test "consumed invite revoke sets error and leaves persisted invite fields unchanged" do
      sysop = actor_fixture(:sysop)
      user = AccountsFixtures.user_fixture()
      invite = AccountsFixtures.invite_fixture(sysop)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      invite
      |> Ecto.Changeset.change(consumed_at: now, consumed_by_user_id: user.id)
      |> Repo.update!()

      {:ok, items} = Accounts.list_invites(sysop)
      state = InvitesState.new(items: items)
      before_status = invite_status!(invite.code)

      assert {:ok, failed} = InvitesActions.revoke_selected(sysop, state)
      assert failed.items == state.items
      assert failed.selected_index == state.selected_index
      assert failed.error == "That invite is already consumed or revoked."

      assert invite_status!(invite.code) == before_status
    end

    test "already revoked invite revoke sets error and leaves persisted invite fields unchanged" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      invite
      |> Ecto.Changeset.change(revoked_at: now)
      |> Repo.update!()

      {:ok, items} = Accounts.list_invites(sysop)
      state = InvitesState.new(items: items)
      before_status = invite_status!(invite.code)

      assert {:ok, failed} = InvitesActions.revoke_selected(sysop, state)
      assert failed.items == state.items
      assert failed.selected_index == state.selected_index
      assert failed.error == "That invite is already consumed or revoked."

      assert invite_status!(invite.code) == before_status
    end

    test "missing code revoke sets error and leaves persisted invites unchanged" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)

      state =
        InvitesState.new(
          items: [
            %{
              code: "MISSINGINVITECODE001",
              status: :available,
              revoked_at: nil,
              consumed_at: nil,
              consumed_by_user_id: nil
            }
          ]
        )

      before_status = invite_status!(invite.code)

      assert {:ok, failed} = InvitesActions.revoke_selected(sysop, state)
      assert failed.items == state.items
      assert failed.selected_index == state.selected_index
      assert failed.error == "That invite could not be found."

      assert invite_status!(invite.code) == before_status
    end
  end

  describe "shared screen delegation" do
    test "account moderation and sysop contain no duplicated invite lifecycle or Repo calls" do
      for path <- [
            "lib/foglet_bbs/tui/screens/account.ex",
            "lib/foglet_bbs/tui/screens/moderation.ex",
            "lib/foglet_bbs/tui/screens/sysop.ex"
          ] do
        source = File.read!(path)

        assert String.contains?(source, "InvitesActions"),
               "Expected #{path} to delegate invite keys through InvitesActions"

        refute source =~ ~r/Accounts\.(create_invite|list_invites|revoke_invite)/
        refute String.contains?(source, "FogletBbs.Repo")
      end
    end
  end

  describe "handle_key/3" do
    setup :restore_invite_config

    test "dispatches generate refresh revoke and selection keys" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)
      {:ok, state} = InvitesActions.load(sysop, InvitesState.new())

      assert {:ok, %InvitesState{last_generated_code: code}} =
               InvitesActions.handle_key("g", sysop, state)

      assert is_binary(code)
      assert {:ok, %InvitesState{}} = InvitesActions.handle_key("R", sysop, state)
      assert {:ok, %InvitesState{}} = InvitesActions.handle_key("D", sysop, state)

      assert {:ok, %InvitesState{selected_index: 0}} =
               InvitesActions.handle_key(:down, sysop, state)

      assert {:ok, %InvitesState{selected_index: 0}} =
               InvitesActions.handle_key(:up, sysop, state)

      assert :no_match = InvitesActions.handle_key("x", sysop, state)

      assert {:ok, %{code: status_code}} = Accounts.get_invite_status(invite.code)
      assert status_code == invite.code
    end
  end

  defp restore_invite_config(_context) do
    Config.init_cache()
    current_generators = Config.get("invite_code_generators", "sysops")
    current_limit = Config.get("invite_generation_per_user_limit", 0)

    on_exit(fn ->
      Config.put!("invite_code_generators", current_generators)
      Config.put!("invite_generation_per_user_limit", current_limit)
      Config.invalidate("invite_code_generators")
      Config.invalidate("invite_generation_per_user_limit")
    end)

    :ok
  end

  defp actor_fixture(role) do
    user = AccountsFixtures.user_fixture()
    {:ok, actor} = Accounts.update_role(user, role)
    actor
  end

  defp invite_status!(code) do
    assert {:ok, status} = Accounts.get_invite_status(code)
    status
  end
end

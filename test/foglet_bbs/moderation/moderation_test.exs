defmodule Foglet.ModerationTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Moderation
  alias Foglet.Moderation.Action
  alias Foglet.Oneliners
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.BoardsFixtures

  describe "record_hide_oneliner!/4" do
    test "inserts a durable hide-oneliner audit action" do
      moderator = AccountsFixtures.user_fixture(%{role: :mod})
      author = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "abusive"})

      action =
        Moderation.record_hide_oneliner!(moderator, entry, "abuse", %{
          "body" => entry.body,
          "author_handle" => author.handle
        })

      assert %Action{} = action
      assert action.kind == :hide_oneliner
      assert action.target_kind == :oneliner
      assert action.target_id == entry.id
      assert action.reason == "abuse"
      assert action.mod_id == moderator.id
      assert action.metadata == %{"body" => "abusive", "author_handle" => author.handle}
    end
  end

  describe "list_actions_for_scopes/2" do
    test "returns site hide actions newest first with moderator preloaded" do
      first_moderator = AccountsFixtures.user_fixture(%{role: :mod})
      second_moderator = AccountsFixtures.user_fixture(%{role: :sysop})
      first_author = AccountsFixtures.user_fixture()
      second_author = AccountsFixtures.user_fixture()

      {:ok, first_entry} = Oneliners.create_entry(first_author, %{body: "first"})
      {:ok, second_entry} = Oneliners.create_entry(second_author, %{body: "second"})

      first_action =
        Moderation.record_hide_oneliner!(first_moderator, first_entry, "spam", %{})

      second_action =
        Moderation.record_hide_oneliner!(second_moderator, second_entry, "abuse", %{})

      actions = Moderation.list_actions_for_scopes([:site])

      assert Enum.map(actions, & &1.id) == [second_action.id, first_action.id]
      assert Enum.all?(actions, &Ecto.assoc_loaded?(&1.mod))
      assert [%Action{mod: %{id: first_listed_moderator_id}} | _] = actions
      assert first_listed_moderator_id == second_moderator.id
    end

    test "returns an empty list for empty scopes" do
      moderator = AccountsFixtures.user_fixture(%{role: :mod})
      author = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "hidden"})

      Moderation.record_hide_oneliner!(moderator, entry, "spam", %{})

      assert Moderation.list_actions_for_scopes([]) == []
    end

    test "accepts board-scope shape without returning site-scoped oneliner actions" do
      moderator = AccountsFixtures.user_fixture(%{role: :mod})
      author = AccountsFixtures.user_fixture()
      board_id = Ecto.UUID.generate()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "hidden"})

      Moderation.record_hide_oneliner!(moderator, entry, "spam", %{})

      assert Moderation.list_actions_for_scopes([{:board, board_id}]) == []
    end
  end

  describe "workspace_snapshot/1" do
    test "returns scoped moderation workspace rows for a moderator" do
      moderator = AccountsFixtures.user_fixture()
      {:ok, moderator} = Accounts.update_role(moderator, :mod)
      user = AccountsFixtures.user_fixture(%{handle: "activeuser"})
      category = BoardsFixtures.category_fixture(%{display_order: 1})
      board = BoardsFixtures.board_fixture(category, %{name: "General", display_order: 2})
      {:ok, entry} = Oneliners.create_entry(user, %{body: "bad line"})

      action = Moderation.record_hide_oneliner!(moderator, entry, "abuse", %{"body" => entry.body})

      assert {:ok, snapshot} = Moderation.workspace_snapshot(moderator)
      assert snapshot.scopes == [:site]
      assert snapshot.queue == []
      assert snapshot.sanctions_available? == false
      assert Enum.map(snapshot.log, & &1.id) == [action.id]
      assert Enum.any?(snapshot.users, &match?(%{id: _, handle: "activeuser", role: :user}, &1))
      assert Enum.any?(snapshot.boards, &match?(%{id: _, name: "General", scope: {:board, _}}, &1))
      assert Enum.find(snapshot.boards, &(&1.id == board.id)).scope == {:board, board.id}
    end

    test "does not leak populated data to regular users or guests" do
      moderator = AccountsFixtures.user_fixture(%{role: :mod})
      user = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(user, %{body: "hidden"})
      Moderation.record_hide_oneliner!(moderator, entry, "spam", %{})

      assert Moderation.workspace_snapshot(user) == {:error, :forbidden}
      assert Moderation.workspace_snapshot(nil) == {:error, :forbidden}
    end

    test "accepts synthetic board-scope lists in read helpers" do
      board_id = Ecto.UUID.generate()

      assert [] = Moderation.list_actions_for_scopes([{:board, board_id}])
      assert [] = Moderation.board_scope_rows([{:board, board_id}])
    end
  end
end

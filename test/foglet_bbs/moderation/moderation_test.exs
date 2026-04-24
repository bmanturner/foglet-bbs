defmodule Foglet.ModerationTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Moderation
  alias Foglet.Moderation.Action
  alias Foglet.Oneliners
  alias FogletBbs.AccountsFixtures

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
end

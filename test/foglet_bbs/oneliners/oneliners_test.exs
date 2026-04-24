defmodule Foglet.OnelinersTest do
  use FogletBbs.DataCase, async: false

  import Ecto.Query, warn: false

  alias Foglet.Moderation.Action
  alias Foglet.Oneliners
  alias Foglet.Oneliners.Entry
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  describe "Entry schema and create_changeset/2" do
    test "defines the locked persistence fields without updated_at" do
      fields = Entry.__schema__(:fields)

      assert :body in fields
      assert :hidden in fields
      assert :hidden_reason in fields
      assert :user_id in fields
      assert :hidden_by_id in fields
      assert :inserted_at in fields
      refute :updated_at in fields
    end

    test "validates and trims a valid body" do
      user = AccountsFixtures.user_fixture()

      changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: "  hello  "})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :body) == "hello"
    end

    test "rejects blank and overlong bodies while accepting 120 characters" do
      user = AccountsFixtures.user_fixture()

      blank_changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: "   "})

      overlong_changeset =
        Entry.create_changeset(%Entry{user_id: user.id}, %{body: String.duplicate("x", 121)})

      max_changeset =
        Entry.create_changeset(%Entry{user_id: user.id}, %{body: String.duplicate("x", 120)})

      refute blank_changeset.valid?
      assert {"can't be blank", _} = Keyword.fetch!(blank_changeset.errors, :body)

      refute overlong_changeset.valid?

      assert {"should be at most %{count} character(s)", _} =
               Keyword.fetch!(overlong_changeset.errors, :body)

      assert max_changeset.valid?
    end
  end

  describe "create_entry/2" do
    test "inserts a visible row owned by the authenticated actor" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, %Entry{} = entry} = Oneliners.create_entry(user, %{body: "hello"})
      assert entry.user_id == user.id
      refute entry.hidden
    end

    test "ignores caller supplied user_id" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      assert {:ok, %Entry{} = entry} =
               Oneliners.create_entry(user, %{body: "hello", user_id: other_user.id})

      assert entry.user_id == user.id
    end

    test "rejects when the latest visible entry belongs to the same user" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, %Entry{}} = Oneliners.create_entry(user, %{body: "first"})
      before_count = Repo.aggregate(Entry, :count)

      assert {:error, :same_user_latest_visible} = Oneliners.create_entry(user, %{body: "second"})
      assert Repo.aggregate(Entry, :count) == before_count
    end
  end

  describe "list_recent_visible/1" do
    test "returns visible entries newest first, capped to limit, with user preloaded" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      hidden_entry =
        %Entry{user_id: user.id, hidden: true}
        |> Entry.create_changeset(%{body: "hidden"})
        |> Repo.insert!()

      assert {:ok, oldest} = Oneliners.create_entry(user, %{body: "oldest"})
      assert {:ok, middle} = Oneliners.create_entry(other_user, %{body: "middle"})
      assert {:ok, newest} = Oneliners.create_entry(user, %{body: "newest"})

      entries = Oneliners.list_recent_visible(3)

      assert Enum.map(entries, & &1.id) == [newest.id, middle.id, oldest.id]
      refute hidden_entry.id in Enum.map(entries, & &1.id)
      assert Enum.all?(entries, &Ecto.assoc_loaded?(&1.user))
    end

    test "caps normal limits to 20 and clamps non-positive limits to 0" do
      first_user = AccountsFixtures.user_fixture()
      second_user = AccountsFixtures.user_fixture()

      for index <- 1..22 do
        user = if rem(index, 2) == 0, do: first_user, else: second_user
        assert {:ok, %Entry{}} = Oneliners.create_entry(user, %{body: "line #{index}"})
      end

      assert Oneliners.list_recent_visible(0) == []
      assert Oneliners.list_recent_visible(-5) == []
      assert length(Oneliners.list_recent_visible(100)) == 20

      assert [latest | _] = Oneliners.list_recent_visible(100)
      assert latest.body == "line 22"
    end

    test "does not let hidden latest entries block the same user" do
      user = AccountsFixtures.user_fixture()

      %Entry{user_id: user.id, hidden: true}
      |> Entry.create_changeset(%{body: "hidden latest"})
      |> Repo.insert!()

      assert {:ok, %Entry{body: "visible"}} = Oneliners.create_entry(user, %{body: "visible"})

      assert [%Entry{body: "visible"}] =
               from(e in Entry, where: e.hidden == false, select: e)
               |> Repo.all()
    end
  end

  describe "hide_entry/3" do
    test "active mod and active sysop can hide a visible oneliner with a reason" do
      for role <- [:mod, :sysop] do
        actor = operator_fixture(role)
        author = AccountsFixtures.user_fixture()
        {:ok, entry} = Oneliners.create_entry(author, %{body: "abuse #{role}"})

        assert {:ok, %Entry{} = hidden_entry} = Oneliners.hide_entry(actor, entry, "abuse")
        assert hidden_entry.hidden
        assert hidden_entry.hidden_reason == "abuse"
        assert hidden_entry.hidden_by_id == actor.id
      end
    end

    test "regular, nil, pending, suspended, deleted, and board-scope-only actors are forbidden without side effects" do
      actors = [
        AccountsFixtures.user_fixture(),
        nil,
        operator_fixture(:mod, %{status: :pending}),
        operator_fixture(:mod, %{status: :suspended}),
        deleted_operator_fixture(),
        board_scope_only_actor_fixture()
      ]

      for actor <- actors do
        author = AccountsFixtures.user_fixture()
        {:ok, entry} = Oneliners.create_entry(author, %{body: "line #{System.unique_integer()}"})
        before_action_count = Repo.aggregate(Action, :count)

        assert {:error, :forbidden} = Oneliners.hide_entry(actor, entry.id, "abuse")

        reloaded_entry = Repo.get!(Entry, entry.id)
        refute reloaded_entry.hidden
        assert is_nil(reloaded_entry.hidden_reason)
        assert is_nil(reloaded_entry.hidden_by_id)
        assert Repo.aggregate(Action, :count) == before_action_count
      end
    end

    test "blank and whitespace reasons are invalid before persistence and create no audit" do
      actor = operator_fixture(:mod)

      for reason <- ["", "   "] do
        author = AccountsFixtures.user_fixture()
        {:ok, entry} = Oneliners.create_entry(author, %{body: "line #{System.unique_integer()}"})
        before_action_count = Repo.aggregate(Action, :count)

        assert {:error, %Ecto.Changeset{} = changeset} =
                 Oneliners.hide_entry(actor, entry, reason)

        assert {"can't be blank", _} = Keyword.fetch!(changeset.errors, :hidden_reason)

        reloaded_entry = Repo.get!(Entry, entry.id)
        refute reloaded_entry.hidden
        assert is_nil(reloaded_entry.hidden_reason)
        assert is_nil(reloaded_entry.hidden_by_id)
        assert Repo.aggregate(Action, :count) == before_action_count
      end
    end

    test "missing target returns not_found and creates no audit" do
      actor = operator_fixture(:mod)
      before_action_count = Repo.aggregate(Action, :count)

      assert {:error, :not_found} = Oneliners.hide_entry(actor, Ecto.UUID.generate(), "abuse")
      assert Repo.aggregate(Action, :count) == before_action_count
    end

    test "successful hide inserts exactly one audit row with target metadata" do
      actor = operator_fixture(:mod)
      author = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "metadata body"})

      before_action_count = Repo.aggregate(Action, :count)

      assert {:ok, %Entry{} = hidden_entry} = Oneliners.hide_entry(actor, entry.id, " abuse ")

      assert Repo.aggregate(Action, :count) == before_action_count + 1
      [action] = Repo.all(from action in Action, where: action.target_id == ^hidden_entry.id)
      assert action.kind == :hide_oneliner
      assert action.target_kind == :oneliner
      assert action.reason == "abuse"
      assert action.mod_id == actor.id
      assert action.metadata == %{"body" => "metadata body", "author_handle" => author.handle}
    end

    test "already-hidden entries cannot be hidden again or re-audited" do
      first_actor = operator_fixture(:mod)
      second_actor = operator_fixture(:sysop)
      author = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "single audit"})

      assert {:ok, %Entry{} = hidden_entry} = Oneliners.hide_entry(first_actor, entry.id, "abuse")
      before_action_count = Repo.aggregate(Action, :count)

      assert {:error, :already_hidden} =
               Oneliners.hide_entry(second_actor, hidden_entry.id, "different reason")

      reloaded_entry = Repo.get!(Entry, hidden_entry.id)
      assert reloaded_entry.hidden
      assert reloaded_entry.hidden_reason == "abuse"
      assert reloaded_entry.hidden_by_id == first_actor.id
      assert Repo.aggregate(Action, :count) == before_action_count
    end

    test "after hide, list_recent_visible excludes hidden entry and preserves newest-first order" do
      actor = operator_fixture(:mod)
      first_author = AccountsFixtures.user_fixture()
      second_author = AccountsFixtures.user_fixture()

      assert {:ok, oldest} = Oneliners.create_entry(first_author, %{body: "oldest"})
      assert {:ok, hidden} = Oneliners.create_entry(second_author, %{body: "hide me"})
      assert {:ok, newest} = Oneliners.create_entry(first_author, %{body: "newest"})

      assert {:ok, %Entry{}} = Oneliners.hide_entry(actor, hidden, "abuse")

      assert Enum.map(Oneliners.list_recent_visible(3), & &1.id) == [newest.id, oldest.id]
    end
  end

  defp operator_fixture(role, attrs \\ %{}) when role in [:mod, :sysop] do
    user = AccountsFixtures.user_fixture()

    user
    |> Ecto.Changeset.change(Map.merge(%{role: role}, attrs))
    |> Repo.update!()
  end

  defp deleted_operator_fixture do
    operator_fixture(:mod, %{deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)})
  end

  defp board_scope_only_actor_fixture do
    operator_fixture(:mod, %{role: :user})
  end
end

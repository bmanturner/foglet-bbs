defmodule Foglet.ModerationTest do
  use FogletBbs.DataCase, async: false

  import Ecto.Query, warn: false

  alias Foglet.Accounts
  alias Foglet.Moderation
  alias Foglet.Moderation.{Action, Report}
  alias Foglet.Notifications.Notification
  alias Foglet.Oneliners
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.BoardsFixtures
  alias FogletBbs.Repo

  describe "record_hide_oneliner!/4" do
    test "inserts a durable hide-oneliner audit action" do
      moderator = moderator_fixture()
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
      moderator = moderator_fixture()
      author = AccountsFixtures.user_fixture()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "hidden"})

      Moderation.record_hide_oneliner!(moderator, entry, "spam", %{})

      assert Moderation.list_actions_for_scopes([]) == []
    end

    test "accepts board-scope shape without returning site-scoped oneliner actions" do
      moderator = moderator_fixture()
      author = AccountsFixtures.user_fixture()
      board_id = Ecto.UUID.generate()
      {:ok, entry} = Oneliners.create_entry(author, %{body: "hidden"})

      Moderation.record_hide_oneliner!(moderator, entry, "spam", %{})

      assert Moderation.list_actions_for_scopes([{:board, board_id}]) == []
    end
  end

  describe "report workflows" do
    test "active users can create post, oneliner, and user reports" do
      reporter = AccountsFixtures.user_fixture()
      post = post_fixture()
      reported_user = AccountsFixtures.user_fixture()
      {:ok, oneliner} = Oneliners.create_entry(reported_user, %{body: "problem line"})

      assert {:ok, %Report{} = post_report} =
               Moderation.create_report(reporter, %{
                 target_kind: :post,
                 target_id: post.id,
                 reason: "spam",
                 notes: "contains unsolicited ads"
               })

      assert post_report.reporter_id == reporter.id
      assert post_report.target_kind == :post
      assert post_report.target_id == post.id
      assert post_report.status == :open
      assert post_report.notes == "contains unsolicited ads"

      assert {:ok, %Report{} = oneliner_report} =
               Moderation.create_report(reporter, %{
                 target_kind: :oneliner,
                 target_id: oneliner.id,
                 reason: "abuse"
               })

      assert oneliner_report.target_kind == :oneliner
      assert oneliner_report.target_id == oneliner.id

      assert {:ok, %Report{} = user_report} =
               Moderation.create_report(reporter, %{
                 target_kind: :user,
                 target_id: reported_user.id,
                 reason: "harassment"
               })

      assert user_report.target_kind == :user
      assert user_report.target_id == reported_user.id
    end

    test "rejects duplicate open reports from the same reporter for the same target" do
      reporter = AccountsFixtures.user_fixture()
      post = post_fixture()
      other_post = post_fixture()

      attrs = %{
        target_kind: :post,
        target_id: post.id,
        reason: "spam",
        notes: "first report"
      }

      assert {:ok, %Report{} = first_report} = Moderation.create_report(reporter, attrs)

      assert {:error, changeset} =
               Moderation.create_report(reporter, %{attrs | notes: "trying again"})

      assert %{target_id: ["already has an open report from you"]} = errors_on(changeset)
      assert Repo.aggregate(Report, :count) == 1

      assert {:ok, %Report{} = different_target_report} =
               Moderation.create_report(reporter, %{attrs | target_id: other_post.id})

      assert different_target_report.id != first_report.id
    end

    test "allows another same-target report after prior report is closed" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()
      post = post_fixture()

      attrs = %{
        target_kind: :post,
        target_id: post.id,
        reason: "spam"
      }

      assert {:ok, %Report{} = first_report} = Moderation.create_report(reporter, attrs)

      assert {:ok, %Report{} = resolved} =
               Moderation.resolve_report(moderator, first_report, %{resolution_note: "handled"})

      assert resolved.status == :resolved
      assert {:ok, %Report{} = second_report} = Moderation.create_report(reporter, attrs)
      assert second_report.id != first_report.id
    end

    test "rejects unsupported target kinds and missing targets" do
      reporter = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Moderation.create_report(reporter, %{
                 target_kind: :thread,
                 target_id: Ecto.UUID.generate(),
                 reason: "spam"
               })

      assert %{target_kind: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               Moderation.create_report(reporter, %{
                 target_kind: :post,
                 target_id: Ecto.UUID.generate(),
                 reason: "spam"
               })

      assert %{target_id: ["does not reference an existing reportable target"]} =
               errors_on(changeset)
    end

    test "regular users cannot list, resolve, or dismiss reports" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()
      report = report_fixture(moderator, reporter)

      assert Moderation.list_open_reports(reporter) == {:error, :forbidden}

      assert Moderation.resolve_report(reporter, report, %{resolution_note: "handled"}) ==
               {:error, :forbidden}

      assert Moderation.dismiss_report(reporter, report, %{resolution_note: "not actionable"}) ==
               {:error, :forbidden}
    end

    test "moderators can list open reports newest first" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()

      first = report_fixture(moderator, reporter, %{reason: "spam"})
      second = report_fixture(moderator, reporter, %{reason: "abuse"})

      assert {:ok, reports} = Moderation.list_open_reports(moderator)
      assert Enum.map(reports, & &1.id) == [second.id, first.id]
      assert Enum.all?(reports, &Ecto.assoc_loaded?(&1.reporter))
    end

    test "moderators can resolve and dismiss reports with resolution details" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()
      resolve_report = report_fixture(moderator, reporter)
      dismiss_report = report_fixture(moderator, reporter)

      assert {:ok, %Report{} = resolved} =
               Moderation.resolve_report(moderator, resolve_report, %{
                 resolution_note: "post removed"
               })

      assert resolved.status == :resolved
      assert resolved.resolved_by_id == moderator.id
      assert resolved.resolution_note == "post removed"
      assert %DateTime{} = resolved.resolved_at

      assert {:ok, %Report{} = dismissed} =
               Moderation.dismiss_report(moderator, dismiss_report, %{
                 resolution_note: "not actionable"
               })

      assert dismissed.status == :dismissed
      assert dismissed.resolved_by_id == moderator.id
      assert dismissed.resolution_note == "not actionable"
      assert %DateTime{} = dismissed.resolved_at
    end

    test "resolving a report notifies only the reporter with a privacy-safe deduped summary" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()
      unrelated = AccountsFixtures.user_fixture()

      report =
        report_fixture(moderator, reporter, %{
          reason: "spam",
          notes: "private reporter notes with @#{unrelated.handle}"
        })

      assert {:ok, %Report{} = resolved} =
               Moderation.resolve_report(moderator, report, %{
                 resolution_note: "private moderator note"
               })

      [notification] = Repo.all(Notification)
      assert notification.user_id == reporter.id
      assert notification.actor_id == moderator.id
      assert notification.kind == :mod_action
      assert notification.dedupe_key == "mod_action:report:#{report.id}:resolved"

      assert notification.payload == %{
               "action_id" => report.id,
               "action_kind" => "resolve_report",
               "reason" => "Your report was resolved."
             }

      assert Repo.aggregate(Notification, :count) == 1
      refute Repo.exists?(from n in Notification, where: n.user_id == ^unrelated.id)

      payload_text = inspect(notification.payload)
      refute payload_text =~ report.notes
      refute payload_text =~ resolved.resolution_note
      refute payload_text =~ unrelated.handle
    end

    test "dismissing a report notifies the reporter once and preserves audit-free report workflow" do
      moderator = moderator_fixture()
      reporter = AccountsFixtures.user_fixture()
      report = report_fixture(moderator, reporter, %{notes: "do not leak this"})

      assert {:ok, %Report{} = dismissed} =
               Moderation.dismiss_report(moderator, report, %{
                 resolution_note: "private moderator dismissal note"
               })

      assert dismissed.status == :dismissed
      assert Repo.aggregate(Action, :count) == 0

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.user_id == reporter.id
      assert notification.dedupe_key == "mod_action:report:#{report.id}:dismissed"

      assert notification.payload == %{
               "action_id" => report.id,
               "action_kind" => "dismiss_report",
               "reason" => "Your report was dismissed."
             }

      assert {:error, :not_open} =
               Moderation.dismiss_report(moderator, dismissed, %{
                 resolution_note: "second pass"
               })

      assert Repo.aggregate(Notification, :count) == 1
    end
  end

  describe "workspace_snapshot/1" do
    test "returns scoped moderation workspace rows and open reports for a moderator" do
      moderator = AccountsFixtures.user_fixture()
      {:ok, moderator} = Accounts.update_role(moderator, :mod)
      user = AccountsFixtures.user_fixture(%{handle: "activeuser"})
      category = BoardsFixtures.category_fixture(%{display_order: 1})
      board = BoardsFixtures.board_fixture(category, %{name: "General", display_order: 2})
      {:ok, entry} = Oneliners.create_entry(user, %{body: "bad line"})

      action =
        Moderation.record_hide_oneliner!(moderator, entry, "abuse", %{"body" => entry.body})

      report = report_fixture(moderator, user, %{reason: "spam", notes: "needs review"})

      assert {:ok, snapshot} = Moderation.workspace_snapshot(moderator)
      assert snapshot.scopes == [:site]
      assert snapshot.sanctions_available? == false
      assert Enum.map(snapshot.queue, & &1.id) == [report.id]
      assert Enum.map(snapshot.log, & &1.id) == [action.id]
      assert Enum.any?(snapshot.users, &match?(%{id: _, handle: "activeuser", role: :user}, &1))

      assert Enum.any?(
               snapshot.boards,
               &match?(%{id: _, name: "General", scope: {:board, _}}, &1)
             )

      assert Enum.find(snapshot.boards, &(&1.id == board.id)).scope == {:board, board.id}
    end

    test "does not leak populated data to regular users or guests" do
      moderator = moderator_fixture()
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

  defp moderator_fixture do
    user = AccountsFixtures.user_fixture()
    {:ok, moderator} = Accounts.update_role(user, :mod)
    moderator
  end

  defp report_fixture(moderator, reporter, attrs \\ %{}) do
    post = post_fixture()

    params =
      Map.merge(
        %{
          target_kind: :post,
          target_id: post.id,
          reason: "spam",
          notes: "needs review"
        },
        attrs
      )

    assert {:ok, %Report{} = report} = Moderation.create_report(reporter, params)
    assert {:ok, [_report | _]} = Moderation.list_open_reports(moderator)
    report
  end

  defp post_fixture do
    author = AccountsFixtures.user_fixture()
    category = BoardsFixtures.category_fixture()
    board = BoardsFixtures.board_fixture(category)
    thread = BoardsFixtures.thread_fixture(board, author)
    BoardsFixtures.post_fixture(thread, author)
  end
end

# QA gate fixtures (FOG-113) — opt-in dev-only seeds that construct the five
# permission/state gates QA needs to drive end-to-end through the SSH/TUI
# harness without ad-hoc DB edits.
#
# Idempotent. Safe to re-run. Run standalone with:
#
#     mix run priv/repo/seeds/qa_gates.exs
#
# Also invoked by priv/repo/seeds.exs in non-test environments after the
# default category, board, and seed users are present.
#
# Seeded surfaces (use seed users `sysop` / `foglet`, password
# `seedpassword123!`):
#
#   1. Locked thread on a normal board:
#        board: general → thread: "Locked: archived discussion (QA)"
#   2. Archived/read-only board with a historical thread:
#        board: qa-archived (archived=true) → thread: "Historical announcement"
#   3. No-subscription scenario for `foglet`:
#        board: qa-optional (default_subscription=false) — foglet is NOT
#        auto-subscribed; the directory shows it as unsubscribed.
#   4. Board requiring subscription:
#        board: qa-required (default_subscription=true,
#        required_subscription=true) — sysop and foglet are pre-subscribed
#        and unsubscribe is rejected.
#   5. Board where posting is not allowed for `foglet`'s role (:user):
#        board: qa-mods-only (postable_by=:mods_only) — foglet sees the board
#        but cannot start a thread or reply.

import Ecto.Query, warn: false

alias Foglet.Accounts
alias Foglet.Boards
alias Foglet.Boards.Board
alias Foglet.Boards.Category
alias Foglet.Posts
alias Foglet.Threads
alias Foglet.Threads.Thread
alias FogletBbs.Repo

# Skip in :test — fixtures collide with isolated test setup (FOG-61).
if Mix.env() == :test do
  IO.puts("  [qa-gates seed] skipping (MIX_ENV=test)")
else
  qa_category =
    case Repo.get_by(Category, name: "QA Gates") do
      nil ->
        cat =
          Repo.insert!(%Category{
            name: "QA Gates",
            description: "Permission/state gate fixtures for SSH/TUI QA (FOG-113).",
            display_order: 90,
            archived: false
          })

        IO.puts("  [qa-gates seed] inserted category: QA Gates")
        cat

      existing ->
        existing
    end

  general_board = Repo.get_by(Board, slug: "general")
  sysop = Accounts.get_user_by_handle("sysop")
  foglet_user = Accounts.get_user_by_handle("foglet")

  cond do
    is_nil(general_board) ->
      IO.puts(
        "  [qa-gates seed] general board missing — run priv/repo/seeds.exs main fixtures first"
      )

    is_nil(sysop) or is_nil(foglet_user) ->
      IO.puts(
        "  [qa-gates seed] seed users (sysop/foglet) missing — run priv/repo/seeds.exs main fixtures first"
      )

    true ->
      # Ensure the general board's server is running so message-number
      # allocation goes through the single writer.
      case Foglet.Boards.Supervisor.start_board(general_board.id) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      # ----- Gate 1: locked thread on the normal `general` board -----
      locked_title = "Locked: archived discussion (QA)"

      locked_thread =
        Repo.one(
          from t in Thread,
            where:
              t.board_id == ^general_board.id and t.title == ^locked_title and
                is_nil(t.deleted_at),
            limit: 1
        ) ||
          (
            {:ok, %{thread: t}} =
              Threads.create_thread(general_board.id, sysop.id, %{
                title: locked_title,
                body: "This thread is locked for QA. Replies must be rejected by the lock gate."
              })

            {:ok, _} =
              Posts.create_reply(t.id, general_board.id, foglet_user.id, %{
                body: "Final reply before lock — QA reference."
              })

            IO.puts("  [qa-gates seed] inserted thread: #{locked_title}")
            t
          )

      unless locked_thread.locked do
        {:ok, _} = Threads.lock_thread(locked_thread)
        IO.puts("  [qa-gates seed] locked thread: #{locked_title}")
      end

      # ----- Gate 2: archived board with a historical thread -----
      archived_board =
        case Repo.get_by(Board, slug: "qa-archived") do
          nil ->
            board =
              Repo.insert!(%Board{
                slug: "qa-archived",
                name: "QA Archived",
                description: "Archived/read-only board with a historical thread (FOG-113).",
                display_order: 91,
                readable_by: :public,
                postable_by: :members,
                default_subscription: false,
                required_subscription: false,
                archived: false,
                category_id: qa_category.id
              })

            IO.puts("  [qa-gates seed] inserted board: qa-archived (pre-archive)")
            board

          existing ->
            existing
        end

      historical_title = "Historical announcement"

      historical_thread_exists? =
        Repo.exists?(
          from t in Thread,
            where:
              t.board_id == ^archived_board.id and t.title == ^historical_title and
                is_nil(t.deleted_at)
        )

      unless historical_thread_exists? do
        case Foglet.Boards.Supervisor.start_board(archived_board.id) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        {:ok, %{thread: _}} =
          Threads.create_thread(archived_board.id, sysop.id, %{
            title: historical_title,
            body:
              "This is the historical thread on the archived board. The board will be flipped to archived for the QA gate."
          })

        IO.puts("  [qa-gates seed] inserted historical thread on qa-archived")
      end

      unless archived_board.archived do
        {:ok, _} = archived_board |> Board.archive_changeset() |> Repo.update()
        IO.puts("  [qa-gates seed] archived board: qa-archived")
      end

      # ----- Gate 3: no-subscription board (foglet is NOT auto-subscribed) -----
      _optional_board =
        case Repo.get_by(Board, slug: "qa-optional") do
          nil ->
            board =
              Repo.insert!(%Board{
                slug: "qa-optional",
                name: "QA Optional",
                description:
                  "Optional board (default_subscription=false). foglet starts unsubscribed (FOG-113).",
                display_order: 92,
                readable_by: :public,
                postable_by: :members,
                default_subscription: false,
                required_subscription: false,
                archived: false,
                category_id: qa_category.id
              })

            IO.puts("  [qa-gates seed] inserted board: qa-optional (no auto-subscribe)")
            board

          existing ->
            existing
        end

      # ----- Gate 4: required-subscription board -----
      required_board =
        case Repo.get_by(Board, slug: "qa-required") do
          nil ->
            board =
              Repo.insert!(%Board{
                slug: "qa-required",
                name: "QA Required",
                description:
                  "Required-subscription board (sysop+foglet pre-subscribed; unsubscribe rejected) (FOG-113).",
                display_order: 93,
                readable_by: :public,
                postable_by: :members,
                default_subscription: true,
                required_subscription: true,
                archived: false,
                category_id: qa_category.id
              })

            IO.puts("  [qa-gates seed] inserted board: qa-required")
            board

          existing ->
            existing
        end

      # Idempotent — Boards.subscribe/2 uses on_conflict: :nothing.
      {:ok, _} = Boards.subscribe(sysop.id, required_board.id)
      {:ok, _} = Boards.subscribe(foglet_user.id, required_board.id)

      # ----- Gate 5: posting-not-allowed-for-role board -----
      _mods_only_board =
        case Repo.get_by(Board, slug: "qa-mods-only") do
          nil ->
            board =
              Repo.insert!(%Board{
                slug: "qa-mods-only",
                name: "QA Mods Only",
                description:
                  "postable_by=:mods_only. foglet (role :user) cannot start threads or reply (FOG-113).",
                display_order: 94,
                readable_by: :public,
                postable_by: :mods_only,
                default_subscription: false,
                required_subscription: false,
                archived: false,
                category_id: qa_category.id
              })

            IO.puts("  [qa-gates seed] inserted board: qa-mods-only")
            board

          existing ->
            existing
        end

      IO.puts("QA gates seed complete.")
  end
end

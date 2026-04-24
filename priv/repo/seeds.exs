# Idempotent seeds for Phase 1. Safe to re-run.
#
#     mix run priv/repo/seeds.exs
#
# Seeds:
#   * Tombstone user (fixed UUID for post-anonymization — D-07 / IDNT-07)
#   * Default configuration entries (D-09, D-10)

import Ecto.Query, warn: false

alias Foglet.Accounts
alias Foglet.Accounts.User
alias FogletBbs.Repo

# --- Tombstone user ---
tombstone_id = Accounts.tombstone_user_id()
now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

case Repo.get(User, tombstone_id) do
  nil ->
    Repo.insert!(
      %User{
        id: tombstone_id,
        handle: "[deleted]",
        email: "tombstone@localhost",
        password_hash: "invalid-tombstone",
        confirmed_at: now,
        role: :user,
        show_in_last_callers: false
      },
      on_conflict: :nothing
    )

    IO.puts("  [seed] inserted tombstone user #{tombstone_id}")

  _existing ->
    IO.puts("  [seed] tombstone user already present")
end

# --- Default configuration entries ---
# Delegated to priv/repo/seeds/config.exs so the `test` mix alias can run it
# standalone (without dev-only fixtures below).
Code.eval_file(Path.join(__DIR__, "seeds/config.exs"))

IO.puts("Seeds complete.")

# ============================================================
# Phase 2: Default category and board
# ============================================================

alias Foglet.Boards.Board
alias Foglet.Boards.Category

general_category =
  case Repo.get_by(Category, name: "General") do
    nil ->
      cat =
        Repo.insert!(%Category{
          name: "General",
          description: "General discussion",
          display_order: 1,
          archived: false
        })

      IO.puts("  [seed] inserted category: General")
      cat

    existing ->
      IO.puts("  [seed] category General already present")
      existing
  end

unless Repo.get_by(Board, slug: "general") do
  Repo.insert!(%Board{
    slug: "general",
    name: "General",
    description: "General discussion board. Default board for all new users.",
    display_order: 1,
    readable_by: :public,
    postable_by: :members,
    default_subscription: true,
    required_subscription: false,
    archived: false,
    category_id: general_category.id
  })

  IO.puts("  [seed] inserted board: general (default_subscription: true)")
end

# ============================================================
# Phase 3: Sample threads and posts for UAT testing
# ============================================================

alias Foglet.Threads
alias Foglet.Threads.Thread
alias Foglet.Posts
alias Foglet.Posts.Post

# NOTE: Seeds are intended for development use only. The password below is a
# well-known dev fixture and must never be used in production. Do not run
# `mix run priv/repo/seeds.exs` against a production database.
seed_sysop =
  case Accounts.get_user_by_handle("sysop") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          handle: "sysop",
          email: "sysop@foglet.local",
          password: "seedpassword123!"
        })

      user
      |> User.confirm_changeset()
      |> Ecto.Changeset.change(%{role: :sysop})
      |> Repo.update!()

      IO.puts("  [seed] inserted user: sysop")
      user

    existing ->
      IO.puts("  [seed] user sysop already present")
      existing
  end

seed_member =
  case Accounts.get_user_by_handle("foglet") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          handle: "foglet",
          email: "foglet@foglet.local",
          password: "seedpassword123!"
        })

      user
      |> User.confirm_changeset()
      |> Repo.update!()

      IO.puts("  [seed] inserted user: foglet")
      user

    existing ->
      IO.puts("  [seed] user foglet already present")
      existing
  end

general_board = Repo.get_by(Board, slug: "general")

if general_board do
  # Ensure the Board Server is running. On first-run, boot_board_servers/0 fires
  # before Phase 2 seeds insert the board, so the server may not have started yet.
  case Foglet.Boards.Supervisor.start_board(general_board.id) do
    {:ok, _} -> :ok
    {:error, {:already_started, _}} -> :ok
  end

  find_thread = fn title ->
    Repo.one(
      from t in Thread,
        where: t.board_id == ^general_board.id and t.title == ^title and is_nil(t.deleted_at),
        limit: 1
    )
  end

  # 1. Welcome announcement (sticky)
  unless find_thread.("Welcome to Foglet BBS!") do
    {:ok, %{thread: welcome}} =
      Threads.create_thread(general_board.id, seed_sysop.id, %{
        title: "Welcome to Foglet BBS!",
        body: """
        Welcome aboard!

        Foglet BBS is a classic bulletin board system accessible over SSH.

        **Getting started:**
        - Press `B` from the Main Menu to browse boards
        - Press `C` to start a new thread
        - Press `R` while reading to compose a reply

        Enjoy your stay.
        """
      })

    Threads.sticky_thread(welcome)
    IO.puts("  [seed] inserted thread: Welcome to Foglet BBS! (sticky)")
  else
    IO.puts("  [seed] thread 'Welcome to Foglet BBS!' already present")
  end

  # 2. Introduce Yourself — with a reply from the member user
  intro_thread =
    case find_thread.("Introduce Yourself") do
      nil ->
        {:ok, %{thread: t}} =
          Threads.create_thread(general_board.id, seed_sysop.id, %{
            title: "Introduce Yourself",
            body: "Tell us who you are! Where are you calling from?"
          })

        IO.puts("  [seed] inserted thread: Introduce Yourself")
        t

      existing ->
        IO.puts("  [seed] thread 'Introduce Yourself' already present")
        existing
    end

  intro_post_count =
    Repo.one(
      from p in Post,
        where: p.thread_id == ^intro_thread.id and is_nil(p.deleted_at),
        select: count()
    )

  if intro_post_count < 2 do
    {:ok, _} =
      Posts.create_reply(intro_thread.id, general_board.id, seed_member.id, %{
        body: "Hey! I'm foglet — just setting up the system. Glad to be here."
      })

    IO.puts("  [seed] inserted reply in thread: Introduce Yourself")
  end

  # 3. General Chat — with a couple of replies to exercise post navigation
  chat_thread =
    case find_thread.("General Chat") do
      nil ->
        {:ok, %{thread: t}} =
          Threads.create_thread(general_board.id, seed_member.id, %{
            title: "General Chat",
            body: "Anything goes — share what's on your mind."
          })

        IO.puts("  [seed] inserted thread: General Chat")
        t

      existing ->
        IO.puts("  [seed] thread 'General Chat' already present")
        existing
    end

  chat_post_count =
    Repo.one(
      from p in Post,
        where: p.thread_id == ^chat_thread.id and is_nil(p.deleted_at),
        select: count()
    )

  if chat_post_count < 3 do
    {:ok, _} =
      Posts.create_reply(chat_thread.id, general_board.id, seed_sysop.id, %{
        body: "Glad this system is up and running. The SSH interface feels snappy."
      })

    {:ok, _} =
      Posts.create_reply(chat_thread.id, general_board.id, seed_member.id, %{
        body:
          "Agreed. Markdown preview in the composer is a nice touch — **bold** and *italic* both render correctly."
      })

    IO.puts("  [seed] inserted replies in thread: General Chat")
  end
else
  IO.puts("  [seed] general board not found — skipping threads/posts (run Phase 2 seeds first)")
end

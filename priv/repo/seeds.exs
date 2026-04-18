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
alias Foglet.Config
alias Foglet.Config.Entry
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
default_config = [
  {"registration_mode", "open",
   "Account registration policy (D-02/D-03): open | invite_only | sysop_approved"},
  {"invite_code_generators", "sysop_only",
   "Who may generate invite codes (D-04): sysop_only | mods | any_user"},
  {"max_post_length", 8192, "Maximum post body length in characters (D-31)"}
]

Enum.each(default_config, fn {key, value, description} ->
  case Repo.get_by(Entry, key: key) do
    nil ->
      Config.put!(key, value, nil)

      # Set description on first insert (put!/3 doesn't touch description)
      Entry
      |> Repo.get_by!(key: key)
      |> Ecto.Changeset.change(%{description: description})
      |> Repo.update!()

      IO.puts("  [seed] inserted config #{key} = #{inspect(value)}")

    _existing ->
      IO.puts("  [seed] config #{key} already present")
  end
end)

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
    archived: false,
    category_id: general_category.id
  })

  IO.puts("  [seed] inserted board: general (default_subscription: true)")
end

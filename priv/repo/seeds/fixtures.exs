# Idempotent production-safe fixtures. Safe to re-run.
#
#     mix run priv/repo/seeds/fixtures.exs
#
# Seeds rows the running application requires regardless of environment:
#
#   * Tombstone user (fixed UUID for post-anonymization — D-07 / IDNT-07).
#     Foglet.Accounts rewrites authorship of deleted users' posts to this id;
#     without the row, account deletion would fail with an FK violation.
#
# Release-safe: no Mix dependency, no dev fixtures. Invoked from
# `FogletBbs.Release.seed/0` on production deploys and from
# `priv/repo/seeds.exs` during local setup. The `test` mix alias deliberately
# skips this file — tests insert their own tombstone via fixtures and a
# pre-seeded row would collide on the fixed UUID (FOG-61).

alias Foglet.Accounts
alias Foglet.Accounts.User
alias FogletBbs.Repo

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

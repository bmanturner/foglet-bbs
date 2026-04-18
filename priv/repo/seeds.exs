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
  {"registration.mode", "sysop_approved",
   "Account registration policy: open | invite_only | sysop_approved"},
  {"registration.require_email_verification", false,
   "Require email verification on signup (wired in Phase 10)"}
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

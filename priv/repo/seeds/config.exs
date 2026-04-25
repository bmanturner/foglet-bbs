# Idempotent config seeds. Safe to re-run.
#
#     mix run priv/repo/seeds/config.exs
#
# Seeds the `configuration` table with one row per schematized key in
# `Foglet.Config.Schema`, including "delivery_mode".
#
# The `delivery_mode` seed is environment-aware: if SMTP delivery is enabled
# through the same env vars the runtime mailer uses, the initial DB value is
# seeded to "email"; otherwise it stays at the schema default of "no_email".
#
# Split out from `priv/repo/seeds.exs` so the `test` mix alias can seed ONLY
# config (required by `Foglet.Config.get!/1` and all typed accessors) without
# also inserting dev-only fixtures like the sysop user, the general board, or
# sample threads/posts.

import Ecto.Query, warn: false

alias Foglet.Config
alias Foglet.Config.Entry
alias Foglet.Config.Schema
alias FogletBbs.Repo

smtp_delivery_enabled? =
  System.get_env("FOGLET_SMTP_RELAY") || System.get_env("FOGLET_SMTP_HOST")

Enum.each(Schema.entries(), fn %{key: key, default: default, description: description} ->
  default =
    if key == "delivery_mode" and smtp_delivery_enabled? do
      "email"
    else
      default
    end

  case Repo.get_by(Entry, key: key) do
    nil ->
      Config.put!(key, default, nil)

      # Set description on first insert (put!/3 doesn't touch description)
      Entry
      |> Repo.get_by!(key: key)
      |> Ecto.Changeset.change(%{description: description})
      |> Repo.update!()

      IO.puts("  [seed] inserted config #{key} = #{inspect(default)}")

    _existing ->
      IO.puts("  [seed] config #{key} already present")
  end
end)

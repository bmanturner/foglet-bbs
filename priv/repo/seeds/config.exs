# Idempotent config seeds. Safe to re-run.
#
#     mix run priv/repo/seeds/config.exs
#
# Seeds the `configuration` table with one row per schematized key in
# `Foglet.Config.Schema`, including "delivery_mode", using each key's declared
# default value.
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

Enum.each(Schema.entries(), fn %{key: key, default: default, description: description} ->
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

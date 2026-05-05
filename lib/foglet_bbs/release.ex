defmodule FogletBbs.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :foglet_bbs

  @production_seed_files [
    "repo/seeds/config.exs",
    "repo/seeds/fixtures.exs"
  ]

  def migrate do
    :ok = load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Runs migrations and production-safe seeds in one shot.

  Used as the deploy `release_command` so every deployed instance has the
  rows the running application assumes exist (config defaults, tombstone
  user). Add new release-safe seed files to `@production_seed_files`.
  """
  def seed do
    :ok = load_app()
    priv = priv_dir()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)

          for relative <- @production_seed_files do
            Code.eval_file(Path.join(priv, relative))
          end

          repo
        end)
    end

    :ok
  end

  def rollback(repo, version) do
    :ok = load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp priv_dir do
    @app |> :code.priv_dir() |> List.to_string()
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    {:ok, _apps} = Application.ensure_all_started(:ssl)
    :ok = Application.ensure_loaded(@app)
  end
end

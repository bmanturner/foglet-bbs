defmodule Foglet.Config do
  @moduledoc """
  Runtime configuration API with ETS caching.

  The ETS table `:foglet_config` is a read-through cache. Writes go to
  the DB first, then invalidate the ETS key so the next read
  re-populates it.

  Started from `FogletBbs.Application.start/2` before the
  `Supervisor.start_link/2` call so any supervised process can read
  config immediately. `init_cache/0` is idempotent on repeat calls to
  guard against Pitfall 4 (ETS table created before application starts).

  See `docs/DATA_MODEL.md` §11.
  """

  alias Foglet.Config.Entry
  alias FogletBbs.Repo

  @table :foglet_config

  @doc """
  Initialize the named ETS table. Idempotent — returns `:ok` even if the
  table already exists. Called from `FogletBbs.Application.start/2`
  and defensively from every public API function.
  """
  @spec init_cache() :: :ok
  def init_cache do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end

  @doc """
  Read a config value. First checks ETS; on miss, loads from DB,
  caches the unwrapped value, and returns it. Raises
  `Ecto.NoResultsError` if the key is not in the DB.
  """
  @spec get!(String.t()) :: term()
  def get!(key) when is_binary(key) do
    init_cache()

    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        entry = Repo.get_by!(Entry, key: key)
        value = unwrap(entry.value)
        :ets.insert(@table, {key, value})
        value
    end
  end

  @doc """
  Read a config value, returning `default` if the key is missing or the lookup fails.
  """
  @spec get(String.t(), term()) :: term()
  def get(key, default) when is_binary(key) do
    get!(key)
  rescue
    _ -> default
  end

  @doc """
  Upsert a config value. Wraps the value as `%{"v" => value}` for jsonb,
  invalidates the ETS cache for the key, and records the updating user.

  Pass `nil` for `updated_by_id` when called from seeds or startup code.
  """
  @spec put!(String.t(), term(), String.t() | nil) :: Entry.t()
  def put!(key, value, updated_by_id \\ nil) when is_binary(key) do
    init_cache()
    wrapped = %{"v" => value}

    entry =
      case Repo.get_by(Entry, key: key) do
        nil ->
          %Entry{}
          |> Entry.changeset(%{
            key: key,
            value: wrapped,
            updated_by_id: updated_by_id
          })
          |> Repo.insert!()

        existing ->
          existing
          |> Entry.changeset(%{value: wrapped, updated_by_id: updated_by_id})
          |> Repo.update!()
      end

    invalidate(key)
    entry
  end

  @doc "Drop the key from the ETS cache so the next get!/1 re-reads from DB."
  @spec invalidate(String.t()) :: :ok
  def invalidate(key) when is_binary(key) do
    init_cache()
    :ets.delete(@table, key)
    :ok
  end

  # ---------- Private ----------

  defp unwrap(%{"v" => v}), do: v
  defp unwrap(value), do: value
end

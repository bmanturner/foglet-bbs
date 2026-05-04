defmodule Foglet.Config do
  @moduledoc """
  Runtime configuration API with ETS caching and typed accessors.

  The ETS table `:foglet_config` is a read-through cache. Writes go to
  the DB first, then invalidate the ETS key so the next read
  re-populates it.

  Started from `FogletBbs.Application.start/2` before the
  `Supervisor.start_link/2` call so any supervised process can read
  config immediately. `init_cache/0` is idempotent on repeat calls to
  guard against Pitfall 4 (ETS table created before application starts).

  Writes through `put!/3` are validated against `Foglet.Config.Schema`:
  unknown keys raise `Foglet.Config.UnknownKeyError`; type / enum / range
  violations raise `Foglet.Config.InvalidValueError`. The read path
  (`get!/1`, `get/2`, `fetch/1`) stays permissive because rows on the
  `configuration` table may pre-date the schema.

  See `docs/DATA_MODEL.md` §11.
  """

  require Logger

  alias Foglet.Config.Entry
  alias Foglet.Config.InvalidValueError
  alias Foglet.Config.Schema
  alias Foglet.Config.UnknownKeyError
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
  Read a config value, returning `default` if the key is missing.
  Other errors (DB outages, malformed values) propagate.
  """
  @spec get(String.t(), term()) :: term()
  def get(key, default) when is_binary(key) do
    get!(key)
  rescue
    Ecto.NoResultsError -> default
  end

  @doc """
  Structured lookup: returns `{:ok, value}` if the key is present in the
  configuration DB, `:error` if it is missing. Matches the stdlib
  `Map.fetch/2` / `Keyword.fetch/2` / `Access.fetch/2` shape.

  DB errors (connection failures, malformed values) propagate as
  exceptions; only a missing-key miss is converted to `:error`.

  Uses the same ETS-backed read path as `get!/1`, so a cache hit does not
  round-trip to Postgres.
  """
  @spec fetch(String.t()) :: {:ok, term()} | :error
  def fetch(key) when is_binary(key) do
    {:ok, get!(key)}
  rescue
    Ecto.NoResultsError -> :error
  end

  @doc """
  Upsert a config value. Wraps the value as `%{"v" => value}` for jsonb,
  invalidates the ETS cache for the key, and records the updating user.

  The value is validated against `Foglet.Config.Schema` before any DB
  work — unknown keys raise `Foglet.Config.UnknownKeyError`, and
  type/enum/range violations raise `Foglet.Config.InvalidValueError`.
  Neither failure mode touches the DB or the ETS cache.

  Pass `nil` for `updated_by_id` when called from seeds or startup code.
  """
  @spec put!(String.t(), term(), String.t() | nil) :: Entry.t()
  def put!(key, value, updated_by_id \\ nil) when is_binary(key) do
    case Schema.validate(key, value) do
      :ok ->
        do_put!(key, value, updated_by_id)

      {:error, {:unknown_key, ^key}} ->
        raise UnknownKeyError, key: key

      {:error, %{reason: reason, expected: expected, got: got}} ->
        raise InvalidValueError, key: key, reason: reason, expected: expected, got: got
    end
  end

  @doc """
  Actor-aware config write (D-19). Returns tagged tuples for all failure modes; never raises.
  Use this from interactive callers (TUI sysop screen in Phase 2, future API clients).

  For trusted internal paths (seeds, Mix tasks, test setup), call `put!/3` directly with
  `nil` as `updated_by_id` — the non-actor pathway continues unchanged.

  Authorization: the actor must be permitted for `:edit_config` at `:site` scope
  (`Foglet.Authorization`). Sysops are permitted; mods, regular users, and `nil` actors
  are all denied.

  Validation errors (unknown key, invalid value) are returned as `{:error, :unknown_key}` /
  `{:error, :invalid_value}` instead of raising. On any failure, no DB mutation and no ETS
  invalidation occur.
  """
  @spec put(Foglet.Accounts.User.t() | nil, String.t(), term()) ::
          {:ok, Entry.t()}
          | {:error, :forbidden}
          | {:error, :unknown_key}
          | {:error, :invalid_value}
          | {:error, :db_error}
  def put(actor, key, value) when is_binary(key) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site) do
      case Schema.validate(key, value) do
        :ok ->
          try do
            {:ok, do_put!(key, value, actor && actor.id)}
          rescue
            e in [Ecto.InvalidChangesetError, Postgrex.Error, DBConnection.ConnectionError] ->
              Logger.error(
                "Foglet.Config.put/3 DB failure for key #{inspect(key)}: #{inspect(e)}"
              )

              {:error, :db_error}
          end

        {:error, {:unknown_key, ^key}} ->
          {:error, :unknown_key}

        {:error, %{reason: _reason}} ->
          {:error, :invalid_value}
      end
    end
  end

  @doc "Drop the key from the ETS cache so the next get!/1 re-reads from DB."
  @spec invalidate(String.t()) :: :ok
  def invalidate(key) when is_binary(key) do
    init_cache()
    :ets.delete(@table, key)
    :ok
  end

  # ---------- Typed accessors ----------
  #
  # One hand-written function per schematized key. Each reads via
  # `get!/1` so the ETS cache, sandbox isolation, and "seeds missing =
  # raise" semantics are inherited. The `?` suffix on the boolean
  # accessor follows Elixir's predicate naming convention.

  @doc "Account registration policy (D-02/D-03). See Foglet.Config.Schema."
  @spec registration_mode() :: String.t()
  def registration_mode, do: get!("registration_mode")

  @doc "Who may generate invite codes (D-04)."
  @spec invite_code_generators() :: String.t()
  def invite_code_generators, do: get!("invite_code_generators")

  @doc "Maximum post body length in characters (D-31)."
  @spec max_post_length() :: integer()
  def max_post_length, do: get!("max_post_length")

  @doc "Maximum thread title length in characters (D-13)."
  @spec max_thread_title_length() :: integer()
  def max_thread_title_length, do: get!("max_thread_title_length")

  @doc "Outbound transactional delivery mode (MAIL-01)."
  @spec delivery_mode() :: String.t()
  def delivery_mode, do: get!("delivery_mode")

  @doc "Whether new registrations must verify email before gaining access (Phase 6 D-01)."
  @spec require_email_verification?() :: boolean()
  def require_email_verification?, do: get!("require_email_verification")

  @doc "Whether unauthenticated visitors may enter first-class read-only Guest Mode (FOG-583)."
  @spec guest_mode_enabled?() :: boolean()
  def guest_mode_enabled? do
    case Application.fetch_env(:foglet_bbs, :guest_mode_enabled) do
      {:ok, value} -> value
      :error -> get!("guest_mode_enabled")
    end
  end

  @doc "Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02)."
  @spec email_verify_resend_cooldown_seconds() :: integer()
  def email_verify_resend_cooldown_seconds, do: get!("email_verify_resend_cooldown_seconds")

  @doc "Per-user invite generation cap when invite_code_generators == \"any_user\" (INVT-07 D-04). 0 = unlimited."
  @spec invite_generation_per_user_limit() :: non_neg_integer()
  def invite_generation_per_user_limit, do: get!("invite_generation_per_user_limit")

  # ---------- Private ----------

  defp do_put!(key, value, updated_by_id) do
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

  defp unwrap(%{"v" => v}), do: v
  defp unwrap(value), do: value
end

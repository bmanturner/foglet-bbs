defmodule Foglet.SiteCounters do
  @moduledoc """
  Domain boundary for durable site-level counters.

  The total BBS call counter is persisted in Postgres and intentionally does not
  use the SSH active-connection ETS counter. A missing row is treated as an
  uninitialized counter with value `0`; the first increment bootstraps the row
  with an atomic upsert.
  """

  import Ecto.Query

  alias Foglet.SiteCounters.Counter
  alias FogletBbs.Repo

  @bbs_call_counter_name "bbs_calls"

  @doc """
  Returns the durable total number of accepted BBS calls.

  If the counter has not been initialized yet, this returns `0` without creating
  a row. The database remains the source of truth for every read.
  """
  @spec get_call_count() :: non_neg_integer()
  def get_call_count do
    Counter
    |> where([counter], counter.name == ^@bbs_call_counter_name)
    |> select([counter], counter.value)
    |> Repo.one()
    |> case do
      nil -> 0
      value -> value
    end
  end

  @doc """
  Atomically increments the durable total BBS call counter and returns the new total.
  """
  @spec increment_call_count() :: pos_integer()
  def increment_call_count do
    now = DateTime.utc_now()

    {_rows, [%Counter{value: value}]} =
      Repo.insert_all(
        Counter,
        [
          %{
            id: Ecto.UUID.generate(),
            name: @bbs_call_counter_name,
            value: 1,
            inserted_at: now,
            updated_at: now
          }
        ],
        conflict_target: [:name],
        on_conflict: [inc: [value: 1], set: [updated_at: now]],
        returning: [:value]
      )

    value
  end
end

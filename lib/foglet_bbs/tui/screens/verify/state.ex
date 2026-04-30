defmodule Foglet.TUI.Screens.Verify.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Verify`.

  `Foglet.TUI.Screens.Verify.init/1` builds this map and
  `Verify.update/3` owns code entry, submit/resend events, cooldowns, and
  verification task outcomes. App stores the returned value under
  `state.screen_state[:verify]` and only interprets emitted effects.

  Fields:
    * `buffer`                — the 0..6 characters typed so far
    * `attempts`              — count of invalid attempts since last reset
    * `cooldown_until`        — `DateTime` when the invalid-attempts cooldown
                                ends, or `nil` (set after `@max_attempts`
                                failures; blocks code entry, not resend)
    * `resend_cooldown_until` — `DateTime` when the resend cooldown ends, or
                                `nil` (set after a successful resend; blocks
                                further resends, not code entry)

  The two cooldowns are independent (VERIFY-02 D-10).
  """

  @type t :: %{
          buffer: String.t(),
          attempts: non_neg_integer(),
          cooldown_until: DateTime.t() | nil,
          resend_cooldown_until: DateTime.t() | nil
        }

  @doc "Returns the default (empty) verify screen state."
  @spec default() :: t()
  def default do
    %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
  end

  @doc "Reads the verify screen-state map from the app state."
  @spec get(map()) :: t()
  def get(state), do: Map.get(state.screen_state || %{}, :verify) || default()

  @doc "Writes an updated verify screen-state map into the app state."
  @spec put(map(), t()) :: map()
  def put(state, vs) do
    %{state | screen_state: Map.put(state.screen_state || %{}, :verify, vs)}
  end

  @doc "Removes the verify screen state from the app state."
  @spec clear(map()) :: map()
  def clear(state) do
    %{state | screen_state: Map.delete(state.screen_state || %{}, :verify)}
  end

  @doc "Returns `true` if the invalid-attempts cooldown is currently active."
  @spec cooldown?(t()) :: boolean()
  def cooldown?(%{cooldown_until: nil}), do: false

  def cooldown?(%{cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  @doc "Returns `true` if the resend cooldown is currently active."
  @spec resend_cooldown?(t()) :: boolean()
  def resend_cooldown?(%{resend_cooldown_until: nil}), do: false

  def resend_cooldown?(%{resend_cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  @doc """
  Increments the attempt counter and, once `max_attempts` is reached, sets
  `cooldown_until` to `now + cooldown_seconds`.

  Returns the updated screen state with `buffer` cleared.
  """
  @spec record_invalid_attempt(map(), non_neg_integer(), non_neg_integer()) :: map()
  def record_invalid_attempt(vs, max_attempts, cooldown_seconds) do
    new_attempts = vs.attempts + 1

    if new_attempts >= max_attempts do
      %{
        vs
        | buffer: "",
          attempts: new_attempts,
          cooldown_until: DateTime.add(DateTime.utc_now(), cooldown_seconds, :second)
      }
    else
      %{vs | buffer: "", attempts: new_attempts}
    end
  end

  @doc """
  Resets the state after a successful resend: clears the buffer, zeroes
  attempts and the invalid-attempts cooldown, and sets `resend_cooldown_until`
  to `now + cooldown_seconds`.
  """
  @spec after_resend(map(), non_neg_integer()) :: map()
  def after_resend(vs, cooldown_seconds) do
    %{
      vs
      | buffer: "",
        attempts: 0,
        cooldown_until: nil,
        resend_cooldown_until: DateTime.add(DateTime.utc_now(), cooldown_seconds, :second)
    }
  end
end

defmodule Foglet.TUI.Command do
  @moduledoc """
  Thin wrapper around `Raxol.Core.Runtime.Command.task/1` that adds
  structured error handling for TUI task closures.

  ## Contracts

  Foglet has two explicit task result contracts because the App shell handles
  app-global work and screen-owned work differently:

  - `task/2` is for **app-global tasks** whose results are handled directly by
    `Foglet.TUI.App`. Success passes the closure's return value through unchanged
    to the `{:command_result, inner}` re-dispatch path. Failure returns
    `{:task_error, op, reason}` so the App shell can log and show a generic
    recoverable error modal.
  - `screen_task/4` is for **screen-scoped tasks** created from
    `%Foglet.TUI.Effect{type: :task}`. Success returns
    `{:screen_task_result, screen_key, op, {:ok, result}}`; failure calls the
    supplied failure callback and returns
    `{:screen_task_result, screen_key, op, {:error, {:task_failed, kind}}}`.
    This keeps screen reducers on their `{:task_result, op, result}` boundary
    instead of falling through to the app-global `{:task_error, ...}` modal path.

  `op` is the atom you supply to identify which operation failed — used for
  logging and for building human-readable error messages.

  For `task/2`, `reason` is a string produced by `Exception.format/3` (includes
  the full stacktrace) — intended for server-side logs, **not** for display in
  the modal. For `screen_task/4`, the raw reason is only passed to the failure
  callback so callers can log through their own privacy-safe boundary.
  """

  @type screen_failure_metadata :: %{
          screen_key: atom(),
          op: atom(),
          failure_kind: atom(),
          reason: term()
        }

  @spec task(atom(), (-> term())) :: Raxol.Core.Runtime.Command.t()
  def task(op, fun) when is_atom(op) and is_function(fun, 0) do
    Raxol.Core.Runtime.Command.task(fn ->
      try do
        fun.()
      rescue
        e ->
          reason = Exception.format(:error, e, __STACKTRACE__)
          {:task_error, op, reason}
      catch
        kind, value ->
          reason = Exception.format(kind, value, __STACKTRACE__)
          {:task_error, op, reason}
      end
    end)
  end

  @spec screen_task(atom(), atom(), (-> term()), (screen_failure_metadata() -> term())) ::
          Raxol.Core.Runtime.Command.t()
  def screen_task(screen_key, op, fun, on_failure \\ fn _metadata -> :ok end)
      when is_atom(screen_key) and is_atom(op) and is_function(fun, 0) and
             is_function(on_failure, 1) do
    task(op, fn ->
      try do
        {:screen_task_result, screen_key, op, {:ok, fun.()}}
      rescue
        e ->
          report_screen_failure(on_failure, screen_key, op, :exception, e)
          {:screen_task_result, screen_key, op, {:error, {:task_failed, :exception}}}
      catch
        kind, value ->
          failure_kind = safe_failure_kind(kind)
          report_screen_failure(on_failure, screen_key, op, failure_kind, value)
          {:screen_task_result, screen_key, op, {:error, {:task_failed, failure_kind}}}
      end
    end)
  end

  defp report_screen_failure(on_failure, screen_key, op, failure_kind, reason) do
    on_failure.(%{screen_key: screen_key, op: op, failure_kind: failure_kind, reason: reason})
  end

  defp safe_failure_kind(:error), do: :exception
  defp safe_failure_kind(kind) when kind in [:exception, :throw, :exit], do: kind
  defp safe_failure_kind(kind) when is_atom(kind), do: kind
  defp safe_failure_kind(_kind), do: :unknown
end

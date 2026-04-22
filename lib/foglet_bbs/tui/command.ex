defmodule Foglet.TUI.Command do
  @moduledoc """
  Thin wrapper around `Raxol.Core.Runtime.Command.task/1` that adds
  structured error handling for TUI task closures.

  ## Contract

  - **Success:** the closure's return value is passed through unchanged to
    the `{:command_result, inner}` re-dispatch path in `Foglet.TUI.App`.
  - **Failure:** if the closure raises an exception or throws, the wrapper
    catches it and returns `{:task_error, op, reason}` instead of letting
    the task crash silently (which would leave the TUI stuck on "Loading…").

  `op` is the atom you supply to identify which operation failed — used
  for logging and for building a human-readable error modal message in
  `Foglet.TUI.App.do_update/2`.

  `reason` is a string produced by `Exception.format/3` (includes the
  full stacktrace) — intended for server-side logs, **not** for display
  in the modal.
  """

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
end

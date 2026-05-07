defmodule Foglet.TUI.App.Tasks do
  @moduledoc """
  Bridge between Raxol's `Command.task` runtime and screen reducers.

  Raxol wraps every async task return value in `{:command_result, inner}`
  before delivering it back to `Foglet.TUI.App.update/2`. Screen-initiated
  tasks return `{:screen_task_result, key, op, result}` so we know which
  screen to route the result to. Task crashes/timeouts surface as
  `{:task_error, op, reason}` and need a generic user-facing modal.

  This module owns the message-shape contract; `App.do_update/2` keeps the
  dispatch case statement and re-enters itself on the unwrapped inner
  message so existing handlers (`:boards_loaded`, `:posts_loaded`, etc.)
  continue to fire.
  """

  require Logger

  alias Foglet.TUI.App.Routing

  @doc """
  Strips Raxol's `{:command_result, inner}` wrapper. Returns the inner
  message so `App.do_update/2` can re-dispatch it to the matching handler
  (`:boards_loaded`, `:read_pointers_flushed`, etc.).
  """
  @spec unwrap({:command_result, term()}) :: term()
  def unwrap({:command_result, inner}), do: inner

  @doc """
  Handles screen-targeted task results and task errors.

    * `{:screen_task_result, key, op, result}` — routes the result to the
      named screen as `{:task_result, op, result}`.
    * `{:task_error, op, reason}` — logs and shows a generic error modal
      using a humanized op name (e.g., `:load_boards` → "load boards").
  """
  @spec handle(tuple(), struct()) :: {struct(), [Raxol.Core.Runtime.Command.t()]}
  def handle({:screen_task_result, key, op, result}, state) do
    Routing.route_screen_update(state, key, {:task_result, op, result})
  end

  def handle({:task_error, op, reason}, state) do
    Logger.error("[TUI.App] task #{inspect(op)} failed: #{reason}")

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Something went wrong while trying to #{humanize_op(op)}. Please try again."
    }

    {%{state | modal: modal}, []}
  end

  defp humanize_op(op) when is_atom(op) do
    op |> to_string() |> String.replace("_", " ")
  end
end

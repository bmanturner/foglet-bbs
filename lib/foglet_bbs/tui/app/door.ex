defmodule Foglet.TUI.App.Door do
  @moduledoc """
  App-shell terminal-handoff helper for the door (external program) lifecycle.

  Owns:
    * the `session_context.door_active?` flag that suppresses Raxol rendering
      while a door owns the SSH PTY (`suppress_render?/1`),
    * the reducer for `:door_exited` and `:door_launch_failed` messages,
      which clears the flag, surfaces a modal explaining what happened, and
      forwards the original event to the active screen (`handle/2`).

  The flag is runtime-only: while true, `Foglet.TUI.App.view/1` returns nil so
  the SSH door runner can write directly to the terminal without Raxol
  fighting it for bytes. Modal copy references `Foglet.AppName.name()` so it
  stays correct if the BBS is rebranded.
  """

  alias Foglet.AppName
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing

  @doc """
  Returns true if a door currently owns the terminal and Raxol should not
  render. Called from `App.view/1`.
  """
  @spec suppress_render?(App.t() | map()) :: boolean()
  def suppress_render?(%{session_context: session_context}) when is_map(session_context),
    do: Map.get(session_context, :door_active?, false)

  def suppress_render?(_state), do: false

  @doc """
  Handles `:door_exited` and `:door_launch_failed` reducer messages. Clears
  the door-active flag, builds a user-facing modal, and forwards the event to
  the active screen so screens like DoorList can update their own state.
  """
  @spec handle(term(), App.t()) :: {App.t(), [Raxol.Core.Runtime.Command.t()]}
  def handle({:door_exited, door_id, {:error, _reason}, _status} = event, state) do
    mark_door_returned(state, launch_failure_modal(door_id), event)
  end

  def handle({:door_exited, door_id, reason, _status} = event, state) do
    modal = %Foglet.TUI.Modal{
      type: exit_modal_type(reason),
      message: exit_message(door_id, reason)
    }

    mark_door_returned(state, modal, event)
  end

  def handle({:door_launch_failed, door_id, _reason} = event, state) do
    mark_door_returned(state, launch_failure_modal(door_id), event)
  end

  defp mark_door_returned(state, modal, event) do
    state = %{
      state
      | session_context: mark_door_active(state.session_context, false),
        modal: modal
    }

    active_screen = Routing.screen_key(Routing.current_route(state))
    {routed_state, cmds} = Routing.route_screen_update(state, active_screen, event)
    {%{routed_state | modal: modal}, cmds}
  end

  defp mark_door_active(session_context, active?) when is_map(session_context),
    do: Map.put(session_context, :door_active?, active?)

  defp mark_door_active(_session_context, active?), do: %{door_active?: active?}

  defp launch_failure_modal(door_id) do
    %Foglet.TUI.Modal{
      type: :error,
      message:
        "#{display_name(door_id)} could not start. You are still connected and back in #{AppName.name()}. Check server logs for launch details."
    }
  end

  defp exit_modal_type(reason) when reason in [:timeout, :idle_timeout], do: :warning
  defp exit_modal_type(_reason), do: :info

  defp exit_message(door_id, :normal) do
    "#{display_name(door_id)} has closed. You are back in #{AppName.name()}."
  end

  defp exit_message(door_id, :timeout) do
    "#{display_name(door_id)} reached its maximum play time and was closed. You are back in #{AppName.name()}."
  end

  defp exit_message(door_id, :idle_timeout) do
    "#{display_name(door_id)} was idle too long and was closed. You are back in #{AppName.name()}."
  end

  defp exit_message(door_id, _reason) do
    "#{display_name(door_id)} closed unexpectedly. You are back in #{AppName.name()}. Check server logs for details."
  end

  defp display_name(door_id) when is_binary(door_id) do
    door_id
    |> String.replace(["-", "_"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

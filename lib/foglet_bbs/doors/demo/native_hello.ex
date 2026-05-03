defmodule Foglet.Doors.Demo.NativeHello do
  @moduledoc """
  Tiny native demo door used by SSH/TUI QA. It stays attached long enough for
  the harness to prove user input reaches the native door, then exits on Enter
  or `/quit`.
  """

  @behaviour Foglet.Doors.Door

  @impl true
  def init(%{session: session, terminal_size: {cols, rows}}) do
    handle = Map.get(session, :handle) || "guest"

    {:ok, %{handle: handle},
     [
       "Native Hello welcomes ",
       handle,
       " (",
       to_string(cols),
       "x",
       to_string(rows),
       ")\n",
       "Press Enter to return to Foglet.\n"
     ]}
  end

  @impl true
  def handle_input("/quit" <> _rest, state),
    do: {:stop, :normal, state, "Leaving Native Hello.\n"}

  def handle_input("\r", state), do: {:stop, :normal, state, "Leaving Native Hello.\n"}
  def handle_input("\n", state), do: {:stop, :normal, state, "Leaving Native Hello.\n"}
  def handle_input(data, state), do: {:ok, state, ["native> ", data]}

  @impl true
  def handle_resize({cols, rows}, state) do
    {:ok, state, ["Native Hello resized to ", to_string(cols), "x", to_string(rows), "\n"]}
  end
end

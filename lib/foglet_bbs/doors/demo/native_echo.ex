defmodule Foglet.Doors.Demo.NativeEcho do
  @moduledoc """
  Tiny native demo door used by tests and SSH harness QA.
  """

  @behaviour Foglet.Doors.Door

  @impl true
  def init(%{session: session, terminal_size: {cols, rows}}) do
    handle = Map.get(session, :handle) || "guest"

    {:ok, %{size: {cols, rows}},
     ["Native Echo ready for ", handle, " (", to_string(cols), "x", to_string(rows), ")\n"]}
  end

  @impl true
  def handle_input("/quit" <> _rest, state), do: {:stop, :normal, state, "Leaving Native Echo.\n"}
  def handle_input(data, state), do: {:ok, state, ["echo> ", data]}

  @impl true
  def handle_resize({cols, rows} = size, state) do
    {:ok, %{state | size: size}, ["resized ", to_string(cols), "x", to_string(rows), "\n"]}
  end
end

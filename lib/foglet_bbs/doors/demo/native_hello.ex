defmodule Foglet.Doors.Demo.NativeHello do
  @moduledoc """
  Tiny native demo door that starts and returns immediately for SSH/TUI QA.
  """

  @behaviour Foglet.Doors.Door

  @impl true
  def init(%{session: session, terminal_size: {cols, rows}, send_output: send_output}) do
    handle = Map.get(session, :handle) || "guest"

    send_output.([
      "Native Hello welcomes ",
      handle,
      " (",
      to_string(cols),
      "x",
      to_string(rows),
      ")\n"
    ])

    {:stop, :normal}
  end

  @impl true
  def handle_input(_data, state), do: {:ok, state, []}

  @impl true
  def handle_resize(_size, state), do: {:ok, state, []}
end

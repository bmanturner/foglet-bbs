defmodule Foglet.Doors.Door do
  @moduledoc """
  Behaviour for native Elixir doors hosted by `Foglet.Doors.Runner`.

  Native doors run inside the runner GenServer process and receive only a narrow
  launch context. They should keep work incremental and return output as iodata;
  they must not own SSH channel state directly.
  """

  @type context :: %{
          required(:door_id) => String.t(),
          required(:session) => map(),
          required(:terminal_size) => {pos_integer(), pos_integer()},
          required(:send_output) => (iodata() -> :ok)
        }

  @callback init(context()) :: {:ok, term(), iodata()} | {:ok, term()} | {:stop, term()}
  @callback handle_input(binary(), term()) :: {:ok, term(), iodata()} | {:stop, term(), iodata()}
  @callback handle_resize({pos_integer(), pos_integer()}, term()) :: {:ok, term(), iodata()}

  @optional_callbacks handle_input: 2, handle_resize: 2
end

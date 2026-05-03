defmodule Foglet.TUI.RenderCadenceTest do
  use ExUnit.Case, async: false

  alias Raxol.Core.Runtime.Events.Dispatcher

  defmodule TestApp do
    use Raxol.Core.Runtime.Application

    @impl true
    def init(_context), do: {:ok, %{count: 0}}

    @impl true
    def update(:noop, state), do: {state, []}
    def update(:increment, state), do: {%{state | count: state.count + 1}, []}
    def update({:command_result, :noop}, state), do: {state, []}

    @impl true
    def view(_state), do: nil
  end

  setup do
    Process.flag(:trap_exit, true)

    on_exit(fn ->
      case Process.whereis(Dispatcher) do
        nil -> :ok
        pid -> _ = catch_exit(GenServer.stop(pid, :normal, 1_000))
      end
    end)

    initial_state = %{
      app_module: TestApp,
      model: %{count: 0},
      width: 80,
      height: 24,
      debug_mode: false,
      plugin_manager: nil,
      command_registry_table: :render_cadence_command_registry
    }

    {:ok, dispatcher} = Dispatcher.start_link(self(), initial_state)
    %{dispatcher: dispatcher}
  end

  test "no-op subscription messages do not request a render", %{dispatcher: dispatcher} do
    send(dispatcher, {:subscription, :noop})

    refute_receive :render_needed, 100
    assert {:ok, %{count: 0}} = GenServer.call(dispatcher, :get_model)
  end

  test "no-op command results do not request a render", %{dispatcher: dispatcher} do
    send(dispatcher, {:command_result, :noop})

    refute_receive :render_needed, 100
    assert {:ok, %{count: 0}} = GenServer.call(dispatcher, :get_model)
  end

  test "state-changing subscription messages still request a render", %{dispatcher: dispatcher} do
    send(dispatcher, {:subscription, :increment})

    assert_receive :render_needed, 100
    assert {:ok, %{count: 1}} = GenServer.call(dispatcher, :get_model)
  end
end

defmodule Foglet.TUI.ScreenTest do
  use ExUnit.Case, async: true

  defmodule SampleScreen do
    @behaviour Foglet.TUI.Screen

    defmodule State do
      defstruct counter: 0, user_handle: nil
    end

    @impl Foglet.TUI.Screen
    def init(ctx) do
      current_user = Map.get(ctx, :current_user)

      %State{
        user_handle: current_user && current_user.handle
      }
    end

    @impl Foglet.TUI.Screen
    def update({:increment, amount}, %State{} = state, _ctx) do
      {%{state | counter: state.counter + amount}, []}
    end

    @impl Foglet.TUI.Screen
    def update(_message, %State{} = state, _ctx), do: {state, []}

    @impl Foglet.TUI.Screen
    def render(%State{} = state, ctx) do
      %{
        counter: state.counter,
        terminal_size: Map.fetch!(ctx, :terminal_size),
        user_handle: state.user_handle
      }
    end
  end

  describe "new screen contract" do
    test "runs init, update, and render over local state without App input" do
      ctx = %{
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        terminal_size: {100, 32}
      }

      state = SampleScreen.init(ctx)
      assert %SampleScreen.State{counter: 0, user_handle: "alice"} = state

      assert {%SampleScreen.State{counter: 3} = updated, []} =
               SampleScreen.update({:increment, 3}, state, ctx)

      assert SampleScreen.render(updated, ctx) == %{
               counter: 3,
               terminal_size: {100, 32},
               user_handle: "alice"
             }
    end
  end
end

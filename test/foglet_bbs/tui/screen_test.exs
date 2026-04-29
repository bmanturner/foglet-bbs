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

  defmodule StatefulSample do
    @behaviour Foglet.TUI.Screen

    defmodule State do
      @type t :: %__MODULE__{
              route_params: map()
            }

      defstruct route_params: %{}

      def new(attrs \\ []) do
        %__MODULE__{
          route_params: Keyword.get(attrs, :route_params, %{})
        }
      end
    end

    @impl Foglet.TUI.Screen
    def init(ctx) do
      State.new(route_params: Map.fetch!(ctx, :route_params))
    end

    @impl Foglet.TUI.Screen
    def update({:replace_route_params, route_params}, %State{} = state, _ctx) do
      {%{state | route_params: route_params}, []}
    end

    @impl Foglet.TUI.Screen
    def render(%State{} = state, ctx) do
      %{
        route_params: state.route_params,
        terminal_size: Map.fetch!(ctx, :terminal_size)
      }
    end
  end

  defmodule StatelessSample do
    @behaviour Foglet.TUI.Screen

    @impl Foglet.TUI.Screen
    def init(_ctx), do: :stateless

    @impl Foglet.TUI.Screen
    def update(_message, :stateless, _ctx), do: {:stateless, []}

    @impl Foglet.TUI.Screen
    def render(:stateless, ctx) do
      %{current_user: Map.fetch!(ctx, :current_user)}
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

    test "stateful screens can initialize an explicit state struct with new/1" do
      ctx = %{
        route_params: %{board_id: 10},
        terminal_size: {90, 28}
      }

      state = StatefulSample.init(ctx)
      assert %StatefulSample.State{route_params: %{board_id: 10}} = state

      assert {%StatefulSample.State{route_params: %{board_id: 11}} = updated, []} =
               StatefulSample.update({:replace_route_params, %{board_id: 11}}, state, ctx)

      assert StatefulSample.render(updated, ctx) == %{
               route_params: %{board_id: 11},
               terminal_size: {90, 28}
             }
    end

    test "stateless screens explicitly keep no local state" do
      ctx = %{current_user: nil}

      assert StatelessSample.init(ctx) == :stateless
      assert StatelessSample.update(:ignored, :stateless, ctx) == {:stateless, []}
      assert StatelessSample.render(:stateless, ctx) == %{current_user: nil}
    end
  end

  describe "Screen behaviour (Phase 39 R6, D-05)" do
    test "lists subscriptions/2 in @optional_callbacks" do
      optional = Foglet.TUI.Screen.behaviour_info(:optional_callbacks)
      assert {:subscriptions, 2} in optional
    end
  end
end

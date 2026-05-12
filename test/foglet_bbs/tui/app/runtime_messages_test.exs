defmodule Foglet.TUI.App.RuntimeMessagesTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.App.RuntimeMessages
  alias Foglet.TUI.Context

  defmodule SampleScreen do
    defmodule State do
      defstruct messages: []
    end

    def init(%Context{}), do: %State{}

    def update(message, %State{} = state, %Context{}) do
      {%{state | messages: [message | state.messages]}, []}
    end

    def render(%State{} = state, %Context{}), do: {:sample_render, state}
  end

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :sample_runtime,
          session_context: %{domain: %{screen_modules: %{sample_runtime: SampleScreen}}},
          terminal_size: {100, 30},
          route_params: %{thread_id: "t1"},
          screen_state: %{sample_runtime: %SampleScreen.State{}}
        },
        attrs
      )
    )
  end

  describe "concern/1 classifies runtime messages by handler concern" do
    test "known runtime messages map to stable concerns" do
      now = ~U[2026-05-11 15:30:00Z]
      modal = %Foglet.TUI.Modal{type: :info, message: "hi"}
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      cases = [
        {{:window_change, 120, 40}, :terminal},
        {{:navigate, :main_menu}, :routing},
        {{:set_user, user}, :session},
        {:enter_guest, :session},
        {{:show_modal, modal}, :modal},
        {:dismiss_modal, :modal},
        {{:confirm_modal, :yes}, :modal},
        {{:key, %{key: "j"}}, :input},
        {{:board_activity, "b1", :new_post}, :pubsub},
        {{:online_presence, :join, %{user_id: "u1"}}, :presence},
        {{:notification, "u1", :dm, %{body: "hey"}}, :notification},
        {{:door_exited, "door", :normal, 0}, :door},
        {{:door_launch_failed, "door", :enoent}, :door},
        {:heartbeat_tick, :session},
        {{:tui_clock, :minute_tick, now}, :clock},
        {:main_menu_clock_tick, :clock},
        {:login_menu_scramble_tick, :routing},
        {:initial_route_enter, :routing},
        {{:session_replaced, "u1"}, :session},
        {{:promote_session, user}, :session},
        {{:command_result, {:screen_task_result, :sample_runtime, :load, {:ok, :ok}}}, :tasks},
        {{:screen_task_result, :sample_runtime, :load, {:ok, :ok}}, :tasks},
        {{:terminate_after_modal, :pending_approval}, :modal},
        {{:task_error, :load, :boom}, :tasks},
        {:unknown_message, :unknown}
      ]

      Enum.each(cases, fn {message, expected_concern} ->
        assert RuntimeMessages.concern(message) == expected_concern
      end)
    end
  end

  describe "handle/2 routes runtime messages through the expected concern" do
    test "screen-routed, stateful, and no-op messages preserve the contract" do
      now = ~U[2026-05-11 15:30:00Z]
      modal = %Foglet.TUI.Modal{type: :info, message: "old"}

      cases = [
        %{
          name: :window_change,
          state: state(),
          message: {:window_change, 120, 40},
          assert: fn new_state, cmds ->
            assert new_state.terminal_size == {120, 40}
            assert cmds == []
          end
        },
        %{
          name: :show_modal,
          state: state(),
          message: {:show_modal, modal},
          assert: fn new_state, cmds ->
            assert new_state.modal == modal
            assert cmds == []
          end
        },
        %{
          name: :initial_route_enter,
          state: state(),
          message: :initial_route_enter,
          assert: fn new_state, cmds ->
            assert cmds == []

            assert %SampleScreen.State{messages: [:on_route_enter]} =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :key,
          state: state(),
          message: {:key, %{key: "j"}},
          assert: fn new_state, cmds ->
            assert cmds == []

            assert %SampleScreen.State{messages: [{:key, %{key: "j"}}]} =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :online_presence,
          state: state(),
          message: {:online_presence, :join, %{user_id: "u1"}},
          assert: fn new_state, cmds ->
            assert cmds == []

            assert %SampleScreen.State{messages: [{:online_presence, :join, %{user_id: "u1"}}]} =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :notification,
          state: state(),
          message: {:notification, "u1", :dm, %{body: "hey"}},
          assert: fn new_state, cmds ->
            assert cmds == []
            assert %Foglet.TUI.Modal{type: :info, message: "New message: hey"} = new_state.modal
          end
        },
        %{
          name: :door_launch_failed,
          state:
            state(
              session_context: %{
                domain: %{screen_modules: %{sample_runtime: SampleScreen}},
                door_active?: true
              }
            ),
          message: {:door_launch_failed, "external-echo", :enoent},
          assert: fn new_state, cmds ->
            assert cmds == []
            refute new_state.session_context.door_active?
            assert %Foglet.TUI.Modal{type: :error} = new_state.modal

            assert %SampleScreen.State{
                     messages: [{:door_launch_failed, "external-echo", :enoent}]
                   } =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :clock_tick,
          state: state(),
          message: {:tui_clock, :minute_tick, now},
          assert: fn new_state, cmds ->
            assert cmds == []
            assert new_state.session_context.clock_now == now
          end
        },
        %{
          name: :main_menu_clock_tick,
          state: state(),
          message: :main_menu_clock_tick,
          assert: fn new_state, cmds ->
            assert new_state == state()
            assert cmds == []
          end
        },
        %{
          name: :login_menu_scramble_tick_off_login,
          state: state(current_screen: :main_menu),
          message: :login_menu_scramble_tick,
          assert: fn new_state, cmds ->
            assert new_state == state(current_screen: :main_menu)
            assert cmds == []
          end
        },
        %{
          name: :screen_task_result,
          state: state(),
          message: {:screen_task_result, :sample_runtime, :load, {:ok, :loaded}},
          assert: fn new_state, cmds ->
            assert cmds == []

            assert %SampleScreen.State{messages: [{:task_result, :load, {:ok, :loaded}}]} =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :main_menu_unread_notification_result,
          state: state(current_screen: :board_list, unread_notifications_count: 0),
          message: {:screen_task_result, :main_menu, :load_unread_notifications_count, {:ok, 12}},
          assert: fn new_state, cmds ->
            assert cmds == []
            assert new_state.unread_notifications_count == 12
          end
        },
        %{
          name: :command_result,
          state: state(),
          message:
            {:command_result, {:screen_task_result, :sample_runtime, :load, {:ok, :loaded}}},
          assert: fn new_state, cmds ->
            assert cmds == []

            assert %SampleScreen.State{messages: [{:task_result, :load, {:ok, :loaded}}]} =
                     Routing.screen_state_for(new_state, :sample_runtime)
          end
        },
        %{
          name: :task_error,
          state: state(),
          message: {:task_error, :load_boards, :boom},
          assert: fn new_state, cmds ->
            assert cmds == []
            assert %Foglet.TUI.Modal{type: :error, message: message} = new_state.modal
            assert message =~ "load boards"
          end
        },
        %{
          name: :terminate_after_modal,
          state: state(),
          message: {:terminate_after_modal, :pending_approval},
          assert: fn new_state, cmds ->
            assert cmds == []
            assert %Foglet.TUI.Modal{} = new_state.modal
            assert is_function(new_state.modal.on_confirm, 1)
            assert is_function(new_state.modal.on_cancel, 1)
          end
        },
        %{
          name: :unknown,
          state: state(),
          message: :unknown_message,
          assert: fn new_state, cmds ->
            assert new_state == state()
            assert cmds == []
          end
        }
      ]

      Enum.each(cases, fn %{message: message, state: runtime_state, assert: assert_result} ->
        {new_state, cmds} = RuntimeMessages.handle(message, runtime_state)
        assert_result.(new_state, cmds)
      end)
    end
  end
end

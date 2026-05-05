defmodule Foglet.TUI.GuestModeRuntimeTest do
  use ExUnit.Case, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.BoardChat
  alias Foglet.Config
  alias Foglet.Doors.Manifest
  alias Foglet.Sessions.Session
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ChatRoom.State, as: ChatRoomState
  alias Foglet.TUI.Screens.DoorList
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State, as: PostReaderState
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.Screens.ThreadList.State, as: ThreadListState
  alias Foglet.TUI.SessionContext

  @demo_doors_env "FOGLET_ENABLE_DEMO_DOORS"

  setup do
    original = System.get_env(@demo_doors_env)
    System.delete_env(@demo_doors_env)

    Config.init_cache()
    :ets.insert(:foglet_config, {"registration_mode", "open"})
    :ets.insert(:foglet_config, {"guest_mode_enabled", true})
    :ets.insert(:foglet_config, {"max_post_length", 8000})

    on_exit(fn -> restore_env(@demo_doors_env, original) end)
    :ok
  end

  test "login G enters explicit guest state only when guest mode is enabled" do
    local_state = LoginState.default()
    context = Context.new(session_context: %{guest_mode_enabled: true})

    {_local_state, effects} = Login.update({:key, %{key: :char, char: "G"}}, local_state, context)

    assert [%Effect{type: :session, payload: :enter_guest}] = effects

    context = Context.new(session_context: %{guest_mode_enabled: false})

    assert {^local_state, []} =
             Login.update({:key, %{key: :char, char: "G"}}, local_state, context)
  end

  test "App routes explicit guests to main menu without an authenticated user" do
    {:ok, state} =
      App.init(%{
        session_context: %SessionContext{guest: true, guest_mode_enabled: true, user: nil}
      })

    assert state.current_screen == :main_menu
    assert state.current_user == nil
    assert Guest.guest?(state)
  end

  test "explicit guest initial main menu entry loads and renders read-only oneliners" do
    Process.put(:fake_oneliners_owner, self())

    Process.put(:fake_oneliners_entries, [
      %{id: "ol1", body: "guest-readable row", user: %{handle: "alice"}}
    ])

    {:ok, state} =
      App.init(%{
        terminal_size: {80, 24},
        session_context: %{
          guest: true,
          guest_mode_enabled: true,
          user: nil,
          domain: %{oneliners: Foglet.TUI.FakeOneliners}
        }
      })

    assert state.current_screen == :main_menu
    assert state.current_user == nil
    assert Guest.guest?(state)

    refute_received {:list_recent_visible, 5}

    {state, cmds} = App.update(:initial_route_enter, state)

    assert %MainMenuState{oneliner_status: :loading} = App.screen_state_for(state, :main_menu)
    assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

    assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [%{id: "ol1"} = entry]}} =
             task.()

    assert entry.body == "guest-readable row"
    assert_received {:list_recent_visible, 5}

    {state, []} =
      App.update({:screen_task_result, :main_menu, :load_oneliners, {:ok, [entry]}}, state)

    rendered_text =
      state
      |> App.screen_state_for(:main_menu)
      |> MainMenu.render(
        Context.new(
          current_user: nil,
          session_context: state.session_context,
          terminal_size: {80, 24}
        )
      )
      |> collect_text_values()

    assert "> @alice  guest-readable ro" in rendered_text

    refute Enum.any?(
             MainMenu.visible_actions(%{current_user: nil, recent_oneliners: [entry]}),
             fn group ->
               Enum.any?(group.commands, &(&1.key in ["O", "H"]))
             end
           )
  end

  test "guest main menu sanitizes hostile oneliner controls before text nodes and serialized render" do
    Process.put(:fake_oneliners_owner, self())

    hostile_body = "safe \e[31mred\e[0m \e]52;c;clipboard\a osc \e]0;title\e\\ st\abel"

    Process.put(:fake_oneliners_entries, [
      %{id: "ol1", body: hostile_body, user: %{handle: "alice"}}
    ])

    {:ok, state} =
      App.init(%{
        terminal_size: {80, 24},
        session_context: %{
          guest: true,
          guest_mode_enabled: true,
          user: nil,
          domain: %{oneliners: Foglet.TUI.FakeOneliners}
        }
      })

    {state, [%Raxol.Core.Runtime.Command{type: :task, data: task}]} =
      App.update(:initial_route_enter, state)

    assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [entry]}} = task.()
    assert entry.body == hostile_body

    {state, []} =
      App.update({:screen_task_result, :main_menu, :load_oneliners, {:ok, [entry]}}, state)

    view =
      state
      |> App.screen_state_for(:main_menu)
      |> MainMenu.render(
        Context.new(
          current_user: nil,
          session_context: state.session_context,
          terminal_size: {80, 24}
        )
      )

    rendered_text = collect_text_values(view)
    serialized_output = AsciiRenderer.render(view, {80, 24})

    assert Enum.any?(rendered_text, &String.contains?(&1, "@alice  safe red osc"))
    refute unsafe_terminal_text?(Enum.join(rendered_text, ""))
    refute unsafe_terminal_text?(serialized_output)
  end

  test "login-screen unauthenticated nil-user state does not load guest oneliners" do
    Process.put(:fake_oneliners_owner, self())
    Process.put(:fake_oneliners_entries, [%{id: "ol1", body: "should stay hidden"}])

    {:ok, state} =
      App.init(%{
        session_context: %{
          guest: false,
          user: nil,
          domain: %{oneliners: Foglet.TUI.FakeOneliners}
        }
      })

    assert state.current_screen == :login
    refute Guest.guest?(state)

    {_state, cmds} = App.update(:initial_route_enter, state)

    assert cmds == []
    refute_received {:list_recent_visible, 5}
  end

  test "explicit guest entry from login queues main menu oneliner load" do
    Process.put(:fake_oneliners_owner, self())

    Process.put(:fake_oneliners_entries, [
      %{id: "ol1", body: "loaded after G", user: %{handle: "alice"}}
    ])

    {:ok, state} =
      App.init(%{
        terminal_size: {80, 24},
        session_context: %{
          guest: false,
          guest_mode_enabled: true,
          user: nil,
          domain: %{oneliners: Foglet.TUI.FakeOneliners}
        }
      })

    assert state.current_screen == :login
    refute Guest.guest?(state)

    {state, []} = App.update(:initial_route_enter, state)
    refute_received {:list_recent_visible, 5}

    {state, [%Raxol.Core.Runtime.Command{type: :task, data: task}]} =
      App.update(:enter_guest, state)

    assert state.current_screen == :main_menu
    assert state.current_user == nil
    assert Guest.guest?(state)
    assert %MainMenuState{oneliner_status: :loading} = App.screen_state_for(state, :main_menu)

    assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [%{id: "ol1"}]}} = task.()
    assert_received {:list_recent_visible, 5}
  end

  test "session effect enters guest mode in the App without crashing anonymous Session" do
    Process.put(:fake_oneliners_owner, self())
    Process.put(:fake_oneliners_entries, [%{id: "ol1", body: "guest row"}])

    {:ok, session_pid} = start_supervised({Session, [user_id: nil]})

    state = %App{
      current_screen: :login,
      session_pid: session_pid,
      session_context: %{
        guest: false,
        guest_mode_enabled: true,
        user: nil,
        session_pid: session_pid,
        domain: %{oneliners: Foglet.TUI.FakeOneliners}
      }
    }

    {state, [%Raxol.Core.Runtime.Command{type: :task, data: task}]} =
      Effects.apply_effect(state, Effect.session(:enter_guest))

    assert state.current_screen == :main_menu
    assert state.current_user == nil
    assert Guest.guest?(state)
    assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [%{id: "ol1"}]}} = task.()
    assert_received {:list_recent_visible, 5}

    session_state = Session.get_state(session_pid)
    assert session_state.user_id == nil
    assert session_state.handle == nil
  end

  test "Main Menu hides write/account actions but routes guests to browsable doors" do
    enable_demo_doors()

    context = Context.new(session_context: %{guest: true, guest_mode_enabled: true})
    local_state = MainMenuState.new(context)

    refute Enum.any?(MainMenu.visible_destinations(nil), fn {key, _label} -> key == "A" end)
    assert Enum.any?(MainMenu.visible_destinations(nil), fn {key, _label} -> key == "D" end)

    refute Enum.any?(
             MainMenu.visible_actions(%{current_user: nil, recent_oneliners: []}),
             fn group ->
               Enum.any?(group.commands, &(&1.key == "O"))
             end
           )

    {_, compose_effects} = MainMenu.update({:key, %{key: :char, char: "C"}}, local_state, context)
    assert [%Effect{type: :modal, payload: {:open, compose_modal}}] = compose_effects
    assert compose_modal.type == :error

    {_, door_effects} = MainMenu.update({:key, %{key: :char, char: "D"}}, local_state, context)
    assert [%Effect{type: :navigate, payload: %{screen: :door_list}}] = door_effects
  end

  test "guests can navigate to Door Games list and launch attempts stay denied" do
    enable_demo_doors()

    context = Context.new(session_context: %{guest: true, guest_mode_enabled: true})
    state = DoorList.init(context)

    assert [_ | _] = state.doors

    {state, effects} = DoorList.update({:key, %{key: :enter}}, state, context)
    assert [%Effect{type: :modal, payload: {:open, modal}}] = effects
    assert modal.type == :error

    door = hd(state.doors)

    {^state, effects} =
      DoorList.update({:modal_submit, :launch_door, %{door_id: door.id}}, state, context)

    assert [%Effect{type: :modal, payload: {:open, modal}}] = effects
    assert modal.type == :error
  end

  test "App runtime allows direct guest Door Games routes but denies launches" do
    state = %App{
      session_context: %{guest: true, guest_mode_enabled: true},
      current_screen: :main_menu,
      session_pid: self(),
      terminal_size: {80, 24}
    }

    {state, []} = Effects.apply_effect(state, Effect.navigate(:door_list))
    assert state.current_screen == :door_list
    assert state.modal == nil

    manifest = %Manifest{id: "demo", slug: "demo", display_name: "Demo", runtime: :native_elixir}

    {state, []} = Effects.apply_effect(state, Effect.launch_door(manifest))
    assert state.modal.type == :error
    refute_received {:foglet_launch_door, _, _, _}
  end

  test "App runtime denies direct guest write routes" do
    state = %App{
      session_context: %{guest: true, guest_mode_enabled: true},
      current_screen: :main_menu
    }

    {state, []} = Effects.apply_effect(state, Effect.navigate(:new_thread))
    assert state.current_screen == :main_menu
    assert state.modal.type == :error

    manifest = %Manifest{id: "demo", slug: "demo", display_name: "Demo", runtime: :native_elixir}
    state = %{state | modal: nil}

    {state, []} = Effects.apply_effect(state, Effect.launch_door(manifest))
    assert state.modal.type == :error
  end

  defp enable_demo_doors, do: System.put_env(@demo_doors_env, "true")

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  test "thread and post reader compose shortcuts deny guests with modal effects" do
    context = Context.new(session_context: %{guest: true, guest_mode_enabled: true})

    thread_state =
      ThreadListState.new(
        board: %{id: "b1", name: "General", archived: false},
        board_id: "b1",
        threads: [%{id: "t1", title: "Welcome"}],
        status: :loaded
      )

    {^thread_state, thread_effects} =
      ThreadList.update({:key, %{key: :char, char: "C"}}, thread_state, context)

    assert [%Effect{type: :modal, payload: {:open, thread_modal}}] = thread_effects
    assert thread_modal.type == :error

    post_state =
      PostReaderState.new(
        board: %{id: "b1", name: "General", archived: false},
        board_id: "b1",
        thread: %{id: "t1", title: "Welcome", locked: false},
        thread_id: "t1",
        posts: [%{id: "p1", body: "hi"}],
        status: :loaded
      )

    {^post_state, post_effects} =
      PostReader.update({:key, %{key: :char, char: "R"}}, post_state, context)

    assert [%Effect{type: :modal, payload: {:open, post_modal}}] = post_effects
    assert post_modal.type == :error
  end

  test "chat and board presence backends reject nil guest identity" do
    board = %Foglet.Boards.Board{id: "b1", chat_storage_mode: :ephemeral, chat_enabled: true}

    assert {:error, :guest_not_allowed} = BoardChat.post(board, nil, "hello")
    assert :ok = Foglet.Sessions.BoardScreen.track("b1", nil, :chat)
    assert Foglet.Sessions.BoardScreen.count("b1") == 0
  end

  test "chat tab keeps guest transcript read-only without composer send affordances" do
    context =
      Context.new(
        current_user: nil,
        session_context: %{guest: true, guest_mode_enabled: true},
        terminal_size: {120, 40}
      )

    state = %ChatRoomState{board: %{id: "b1", chat_storage_mode: :ephemeral}, board_id: "b1"}

    refute Enum.any?(ChatRoom.keybar_groups(state, context), fn group ->
             Enum.any?(group.commands, &(&1.key == "Enter" and &1.label == "Send"))
           end)

    assert {^state, []} = ChatRoom.update({:key, %{key: :char, char: "h"}}, state, context)

    {^state, effects} = ChatRoom.update({:key, %{key: :enter}}, state, context)
    assert [%Effect{type: :modal, payload: {:open, modal}}] = effects
    assert modal.type == :error
  end

  defp unsafe_terminal_text?(text) do
    text
    |> String.to_charlist()
    |> Enum.any?(fn codepoint ->
      codepoint == 0x1B or codepoint == 0x07 or codepoint == 0x7F or
        codepoint in 0x00..0x08 or codepoint in 0x0B..0x0C or codepoint in 0x0E..0x1F or
        codepoint in 0x80..0x9F
    end)
  end
end

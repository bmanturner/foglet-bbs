# ---------------------------------------------------------------------------
# Fake domain adapters (defined outside test module per project convention)
# ---------------------------------------------------------------------------

defmodule Foglet.TUI.Screens.NewThreadTest.FakeBoards do
  def board_directory_for(user) do
    Process.put(:new_thread_board_loader_user, user)

    [
      %{
        category: %{name: "Public"},
        boards: [
          %{subscribed?: true, board: %{id: "b1", name: "General", unread_count: 0}},
          %{subscribed?: false, board: %{id: "b-hidden", name: "Hidden", unread_count: 0}}
        ]
      },
      %{
        category: %{name: "Ops"},
        boards: [
          %{subscribed?: true, board: %{id: "b2", name: "Announcements", unread_count: 0}}
        ]
      }
    ]
  end

  def list_subscribed_boards(_user) do
    [
      %{id: "b1", name: "General", unread_count: 0},
      %{id: "b2", name: "Announcements", unread_count: 0}
    ]
  end
end

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsOk do
  def create_thread(_board_id, _user_id, attrs) do
    Process.put(:new_thread_last_attrs, attrs)

    thread = %{
      id: "t-new",
      title: Map.get(attrs, :title, ""),
      sticky: false,
      last_post_at: DateTime.utc_now()
    }

    {:ok, %{thread: thread, post: %{id: "p-new"}}}
  end
end

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsMissing do
  # Does NOT export create_thread/3 — simulates unauthenticated user path.
end

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsError do
  def create_thread(_board_id, _user_id, %{title: "policy"}) do
    {:error, :posting_not_allowed}
  end

  def create_thread(_board_id, _user_id, _attrs) do
    {:error, "board is locked"}
  end
end

defmodule Foglet.TUI.Screens.NewThreadTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.NewThread
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Raxol.UI.Components.Input.MultiLineInput

  alias Foglet.TUI.Screens.NewThreadTest.FakeBoards
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsError
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsMissing
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsOk

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fresh_input(value \\ "") do
    {:ok, st} =
      MultiLineInput.init(%{
        value: value,
        placeholder: "Write your opening post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: false
      })

    st
  end

  defp base_state(overrides \\ %{}) do
    user = %{id: "u1", handle: "alice"}

    ss =
      State.new(
        boards: [
          %{id: "b1", name: "General", unread_count: 0},
          %{id: "b2", name: "Announcements", unread_count: 0}
        ],
        width: 80
      )

    state =
      %App{
        current_screen: :new_thread,
        current_user: user,
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsOk}},
        terminal_size: {80, 24},
        screen_state: %{new_thread: ss}
      }
      |> Map.from_struct()

    Map.merge(state, overrides)
  end

  defp context(overrides \\ []) do
    Context.new(
      current_user: Keyword.get(overrides, :current_user, %{id: "u1", handle: "alice"}),
      route: :new_thread,
      route_params: Keyword.get(overrides, :route_params, %{}),
      terminal_size: Keyword.get(overrides, :terminal_size, {80, 24}),
      session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsOk}}
    )
  end

  defp compose_state(board \\ %{id: "b1", name: "General"}) do
    body_input = fresh_input()

    ss =
      State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: ""),
        body_input_state: body_input
      )

    Map.put(base_state(), :screen_state, %{new_thread: ss})
  end

  defp get_ss(state), do: get_in(state, [:screen_state, :new_thread])
  defp title_value(state), do: get_ss(state).title_input_state.raxol_state.value

  defp render_screen(state) do
    render_screen(get_ss(state), context_from_state(state))
  end

  defp render_screen(%State{} = local_state, %Context{} = context) do
    NewThread.render(local_state, context)
  end

  defp handle_key_screen(key_event, state) do
    local_state = get_ss(state)
    context = context_from_state(state)
    {new_local_state, effects} = NewThread.update({:key, key_event}, local_state, context)

    state
    |> put_in([:screen_state, :new_thread], new_local_state)
    |> apply_screen_effects(new_local_state, context, effects)
  end

  defp context_from_state(state) do
    Context.new(
      current_user: Map.get(state, :current_user),
      route: :new_thread,
      route_params: Map.get(state, :route_params) || %{},
      terminal_size: Map.get(state, :terminal_size) || {80, 24},
      session_context: Map.get(state, :session_context) || %{}
    )
  end

  defp apply_screen_effects(state, local_state, context, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Foglet.TUI.Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, acc, cmds} ->
        board_id = params[:board_id] || params["board_id"]
        cmd = if screen == :thread_list and is_binary(board_id), do: {:load_threads, board_id}

        {:update,
         %{
           acc
           | current_screen: screen,
             route_params: params,
             screen_state: Map.delete(acc.screen_state || %{}, :new_thread)
         }, append_cmd(cmds, cmd)}

      %Foglet.TUI.Effect{type: :task, payload: %{op: :create_thread, fun: fun}},
      {:update, acc, cmds} ->
        result = fun.()

        {next_local_state, next_effects} =
          NewThread.update({:task_result, :create_thread, result}, local_state, context)

        acc = put_in(acc, [:screen_state, :new_thread], next_local_state)

        case next_effects do
          [] -> {:update, acc, cmds}
          _ -> apply_screen_effects(acc, next_local_state, context, next_effects)
        end

      _effect, result ->
        result
    end)
  end

  defp append_cmd(cmds, nil), do: cmds
  defp append_cmd(cmds, cmd), do: cmds ++ [cmd]

  defp put_title(state, title, max_length \\ 60) do
    title_input =
      Enum.reduce(String.graphemes(title), TextInput.init(max_length: max_length), fn ch, acc ->
        {next, _} = TextInput.handle_event(%{key: :char, char: ch}, acc)
        next
      end)

    put_in(state.screen_state.new_thread.title_input_state, title_input)
  end

  # ---------------------------------------------------------------------------
  # State.new/1
  # ---------------------------------------------------------------------------

  test "State.new/1 defaults to board step" do
    ss = State.new()
    assert %State{} = ss
    assert ss.step == :board
    assert ss.boards == nil
    assert ss.selected_board_index == 0
    assert ss.board == nil
    assert is_struct(ss.title_input_state, TextInput)
    assert ss.title_input_state.raxol_state.value == ""
    assert is_struct(ss.body_input_state, MultiLineInput)
    assert ss.focused == :title
    assert ss.error == nil
    assert ss.origin == :main_menu
    assert ss.load_status == :idle
    assert ss.submission_status == :idle
    assert ss.submit_result == nil
  end

  test "State.new/1 with boards pre-loaded stores them" do
    boards = [%{id: "b1", name: "General"}]
    ss = State.new(boards: boards)
    assert ss.boards == boards
  end

  test "NewThread.State.from_context/1 without routed board initializes board picker" do
    ctx = Context.new(route: :new_thread, route_params: %{})

    assert %State{
             step: :board,
             boards: nil,
             board: nil,
             selected_board_index: 0,
             origin: :main_menu,
             load_status: :idle,
             submission_status: :idle,
             submit_result: nil
           } = NewThread.State.from_context(ctx)
  end

  test "NewThread.State.from_context/1 stores origin without routed board" do
    ctx = Context.new(route: :new_thread, route_params: %{"origin" => :thread_list})

    assert %State{step: :board, origin: :thread_list, load_status: :idle} =
             NewThread.State.from_context(ctx)
  end

  test "NewThread.State.from_context/1 with routed board initializes compose step" do
    board = %{id: "b1", name: "General"}
    ctx = Context.new(route: :new_thread, route_params: %{origin: :thread_list, board: board})

    assert %State{
             step: :compose,
             board: ^board,
             boards: [^board],
             selected_board_index: 0,
             origin: :thread_list,
             load_status: :loaded
           } = NewThread.State.from_context(ctx)
  end

  test "NewThread.State.from_context/1 applies explicit board_id when board omits id" do
    board = %{"name" => "General"}
    ctx = Context.new(route: :new_thread, route_params: %{"board" => board, "board_id" => "b1"})

    assert %State{step: :compose, board: %{id: "b1"}, boards: [%{id: "b1"}]} =
             NewThread.State.from_context(ctx)
  end

  test "init/1 derives local state from route context" do
    board = %{id: "b1", name: "General"}
    ctx = context(route_params: %{origin: :thread_list, board: board})

    assert %State{step: :compose, board: ^board, origin: :thread_list} = NewThread.init(ctx)
  end

  test "NewThread.update(:load, state, context) emits board load task effect" do
    ctx = context()
    state = State.new(error: "stale")

    assert {%State{load_status: :loading, error: nil},
            [
              %Foglet.TUI.Effect{
                type: :task,
                payload: %{op: :load_boards_for_new_thread, screen_key: :new_thread, fun: fun}
              }
            ]} = NewThread.update(:load, state, ctx)

    assert is_function(fun, 0)
    assert {boards, 3} = fun.()
    assert Enum.map(boards, & &1.id) == ["b1", "b2"]
    assert Process.get(:new_thread_board_loader_user).id == "u1"
  end

  test "NewThread.update/3 stores loaded boards and active count" do
    state = State.new(load_status: :loading, selected_board_index: 4)
    boards = [%{id: "b1", name: "General"}]

    assert {%State{
              boards: ^boards,
              active_board_count: 2,
              selected_board_index: 0,
              load_status: :loaded,
              error: nil
            }, []} =
             NewThread.update(
               {:task_result, :load_boards_for_new_thread, {:ok, {boards, 2}}},
               state,
               context()
             )
  end

  test "NewThread.update/3 accepts legacy board list task result shape" do
    boards = [%{id: "b1", name: "General"}]

    assert {%State{boards: ^boards, active_board_count: nil, load_status: :loaded}, []} =
             NewThread.update(
               {:task_result, :load_boards_for_new_thread, {:ok, boards}},
               State.new(),
               context()
             )
  end

  test "NewThread.update/3 stores empty and error board load states" do
    assert {%State{boards: [], active_board_count: 0, load_status: :empty}, []} =
             NewThread.update(
               {:task_result, :load_boards_for_new_thread, {:ok, {[], 0}}},
               State.new(),
               context()
             )

    assert {%State{load_status: {:error, :boom}, error: ":boom"}, []} =
             NewThread.update(
               {:task_result, :load_boards_for_new_thread, {:error, :boom}},
               State.new(),
               context()
             )
  end

  test "NewThread.update/3 handles board picker navigation and selection" do
    boards = [%{id: "b1", name: "General"}, %{id: "b2", name: "Announcements"}]
    state = State.new(boards: boards, load_status: :loaded)

    {state, []} = NewThread.update({:key, %{key: :char, char: "j"}}, state, context())
    assert state.selected_board_index == 1

    {state, []} = NewThread.update({:key, %{key: :enter}}, state, context())
    assert state.step == :compose
    assert state.board.id == "b2"
  end

  test "NewThread.update/3 handles compose field focus, body preview, and cancel effects" do
    state = State.new(step: :compose, board: %{id: "b1"}, origin: :thread_list)

    {state, []} = NewThread.update({:key, %{key: :tab}}, state, context())
    assert state.focused == :body
    assert state.mode == :edit

    {state, []} = NewThread.update({:key, %{key: :tab}}, state, context())
    assert state.focused == :body
    assert state.mode == :preview

    assert {^state,
            [
              %Foglet.TUI.Effect{
                type: :navigate,
                payload: %{screen: :thread_list, params: %{}}
              }
            ]} = NewThread.update({:key, %{key: :escape}}, state, context())
  end

  test "NewThread.update/3 edits title and body local state" do
    state = State.new(step: :compose, board: %{id: "b1"})

    {state, []} = NewThread.update({:key, %{key: :char, char: "H"}}, state, context())
    assert state.title_input_state.raxol_state.value == "H"

    {state, []} = NewThread.update({:key, %{key: :tab}}, state, context())
    {state, []} = NewThread.update({:key, %{key: :char, char: "i"}}, state, context())
    assert state.body_input_state.value == "i"
  end

  test "NewThread.update/3 emits create_thread task for valid submit" do
    state =
      State.new(
        step: :compose,
        board: %{id: "b1", name: "General"},
        title_input_state: TextInput.init(value: "Task Title", max_length: 60),
        body_input_state: fresh_input("Task body"),
        focused: :body
      )

    assert {%State{submission_status: :submitting, error: nil},
            [
              %Foglet.TUI.Effect{
                type: :task,
                payload: %{op: :create_thread, screen_key: :new_thread, fun: fun}
              }
            ]} =
             NewThread.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context())

    assert {:ok, %{thread: %{id: "t-new"}}} = fun.()
    assert Process.get(:new_thread_last_attrs) == %{title: "Task Title", body: "Task body"}
  end

  test "NewThread.update/3 keeps submit validation local without task effects" do
    state =
      State.new(
        step: :compose,
        board: %{id: "b1", name: "General"},
        body_input_state: fresh_input("body"),
        focused: :body
      )

    assert {%State{error: "Title cannot be empty."}, []} =
             NewThread.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context())

    state = %{state | title_input_state: TextInput.init(value: "Title", max_length: 60)}
    state = %{state | body_input_state: fresh_input("")}

    assert {%State{error: "Post body cannot be empty."}, []} =
             NewThread.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context())

    ctx = context(current_user: nil)
    state = %{state | body_input_state: fresh_input("body")}

    assert {%State{error: "You must be logged in to create a thread."}, []} =
             NewThread.update({:key, %{key: :char, char: "s", ctrl: true}}, state, ctx)
  end

  test "NewThread.update/3 rejects too-long submit body without task effect" do
    state =
      State.new(
        step: :compose,
        board: %{id: "b1", name: "General"},
        title_input_state: TextInput.init(value: "Title", max_length: 60),
        body_input_state: fresh_input("123456"),
        focused: :body
      )

    ctx = context()
    ctx = %{ctx | session_context: Map.put(ctx.session_context, :max_post_length, 5)}

    assert {%State{error: "Post body exceeds maximum length of 5 characters."}, []} =
             NewThread.update({:key, %{key: :char, char: "s", ctrl: true}}, state, ctx)
  end

  test "NewThread.update/3 handles successful create_thread task result with ThreadList route params" do
    board = %{id: "b1", name: "General"}
    state = State.new(step: :compose, board: board, submission_status: :submitting)
    thread = %{id: "t-new", title: "Created"}
    result = %{thread: thread, post: %{id: "p-new"}}

    assert {%State{submission_status: :submitted, submit_result: ^result},
            [
              %Foglet.TUI.Effect{
                type: :navigate,
                payload: %{
                  screen: :thread_list,
                  params: %{board: ^board, board_id: "b1", select_thread_id: "t-new"}
                }
              }
            ]} =
             NewThread.update(
               {:task_result, :create_thread, {:ok, {:ok, result}}},
               state,
               context()
             )
  end

  test "NewThread.update/3 handles direct successful create_thread task result shape" do
    board = %{id: "b1", name: "General"}
    state = State.new(step: :compose, board: board, submission_status: :submitting)
    result = %{thread: %{id: "t-new"}}

    assert {%State{submission_status: :submitted, submit_result: ^result},
            [%Foglet.TUI.Effect{payload: %{params: %{select_thread_id: "t-new"}}}]} =
             NewThread.update({:task_result, :create_thread, {:ok, result}}, state, context())
  end

  test "NewThread.update/3 handles create_thread errors locally" do
    state = State.new(step: :compose, board: %{id: "b1"}, submission_status: :submitting)

    assert {%State{
              submission_status: {:error, :posting_not_allowed},
              error: "You are not allowed to post on this board."
            }, []} =
             NewThread.update(
               {:task_result, :create_thread, {:ok, {:error, :posting_not_allowed}}},
               state,
               context()
             )

    assert {%State{submission_status: {:error, "board is locked"}, error: "board is locked"}, []} =
             NewThread.update(
               {:task_result, :create_thread, {:error, "board is locked"}},
               state,
               context()
             )
  end

  test "render/2 renders board and compose states without App-shaped state" do
    ctx = context()

    assert _ =
             render_screen(
               State.new(boards: [%{id: "b1", name: "General"}], load_status: :loaded),
               ctx
             )

    assert _ =
             render_screen(
               State.new(step: :compose, board: %{id: "b1", name: "General"}),
               ctx
             )
  end

  # ---------------------------------------------------------------------------
  # Render — board step
  # ---------------------------------------------------------------------------

  test "render/1 board step does not crash" do
    state = base_state()
    assert _ = render_screen(state)
  end

  test "render/1 board step with nil boards does not crash" do
    ss = State.new(boards: nil)
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    assert _ = render_screen(state)
  end

  test "render/1 board step with no subscriptions points to Boards when active boards exist" do
    ss = State.new(boards: [], active_board_count: 2)
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Subscribe from Boards"
    refute text =~ "Ask your sysop"
  end

  test "render/1 board step with no active boards says none are available" do
    ss = State.new(boards: [], active_board_count: 0)
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "No active boards are available"
    refute text =~ "Ask your sysop"
  end

  # ---------------------------------------------------------------------------
  # Render — compose step
  # ---------------------------------------------------------------------------

  test "render/1 compose step does not crash" do
    state = compose_state()
    assert _ = render_screen(state)
  end

  test "render/1 compose step uses composer shell with board and title counter" do
    text =
      compose_state()
      |> render_screen()
      |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "General"
    assert text =~ "Title"
    assert text =~ "0 / 60 chars"
  end

  test "render/1 compose step shows title value when present" do
    text =
      compose_state()
      |> put_title("A Thread")
      |> render_screen()
      |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Title"
    assert text =~ "A Thread"
  end

  test "render/1 body-focused edit mode keeps body text and body counter in shell" do
    state =
      compose_state()
      |> put_title("Body Counter")

    ss = %{get_ss(state) | focused: :body, body_input_state: fresh_input("Hello body")}
    state = put_in(state.screen_state.new_thread, ss)

    text = state |> render_screen() |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "Hello body"
    assert text =~ "Body 10 /"
    assert text =~ "chars"
  end

  test "render/1 body-focused compact edit mode visually wraps body without mutating value" do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"

    state =
      compose_state()
      |> put_title("Wrapped Thread")

    ss = %{
      get_ss(state)
      | focused: :body,
        mode: :edit,
        body_input_state: fresh_input(long_body)
    }

    state = %{put_in(state.screen_state.new_thread, ss) | terminal_size: {64, 22}}
    text = state |> render_screen() |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Wrapped Thread"
    assert text =~ "alpha beta"
    assert text =~ "iota kappa"
    assert get_ss(state).body_input_state.value == long_body
    refute get_ss(state).body_input_state.value =~ "\n"
  end

  test "render/1 reflows new-thread body between 80x24 and 64x22 without changing value" do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"

    state =
      compose_state()
      |> put_title("Reflow Thread")

    ss = %{
      get_ss(state)
      | focused: :body,
        mode: :edit,
        body_input_state: fresh_input(long_body)
    }

    wide_state = %{put_in(state.screen_state.new_thread, ss) | terminal_size: {80, 24}}
    compact_state = %{wide_state | terminal_size: {64, 22}}

    wide_text = wide_state |> render_screen() |> Foglet.TUI.WidgetHelpers.flatten_text()
    compact_text = compact_state |> render_screen() |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert get_ss(wide_state).body_input_state.value == long_body
    assert get_ss(compact_state).body_input_state.value == long_body
    refute get_ss(compact_state).body_input_state.value =~ "\n"
    assert wide_text =~ long_body
    refute compact_text =~ long_body
    assert compact_text =~ "alpha beta"
    assert compact_text =~ "iota kappa"
  end

  test "render/1 preview mode keeps markdown preview inside composer shell" do
    state =
      compose_state()
      |> put_title("Preview Title")

    ss = %{
      get_ss(state)
      | focused: :body,
        mode: :preview,
        body_input_state: fresh_input("**bold body**")
    }

    state = put_in(state.screen_state.new_thread, ss)

    text = state |> render_screen() |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "bold body"
  end

  test "render/1 delegates compose breadcrumb formatting to shared chrome" do
    source =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("../../../../lib/foglet_bbs/tui/screens/new_thread.ex")
      |> Path.expand()
      |> File.read!()

    refute source =~ "New Thread —"
  end

  test "source preserves NewThread composer widget boundaries" do
    source =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("../../../../lib/foglet_bbs/tui/screens/new_thread.ex")
      |> Path.expand()
      |> File.read!()

    assert source =~ "EditorFrame.render"
    assert source =~ "TextInput.render"
    assert source =~ "TextInput.handle_event"
    refute source =~ "PostCard.render"
  end

  # ---------------------------------------------------------------------------
  # Board step navigation
  # ---------------------------------------------------------------------------

  test "Esc on board step navigates to :main_menu" do
    state = base_state()
    {:update, new_state, _cmds} = handle_key_screen(%{key: :escape}, state)
    assert new_state.current_screen == :main_menu
  end

  test "j moves board selection down" do
    state = base_state()
    assert get_ss(state).selected_board_index == 0

    {:update, new_state, _} = handle_key_screen(%{key: :char, char: "j"}, state)
    assert get_ss(new_state).selected_board_index == 1
  end

  test "down arrow moves board selection down" do
    state = base_state()
    {:update, new_state, _} = handle_key_screen(%{key: :down}, state)
    assert get_ss(new_state).selected_board_index == 1
  end

  test "j clamps at last board index" do
    state = base_state()
    # Move to last board (index 1 of 2)
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, state)
    assert get_ss(s1).selected_board_index == 1
    # Pressing j again should stay at 1
    {:update, s2, _} = handle_key_screen(%{key: :char, char: "j"}, s1)
    assert get_ss(s2).selected_board_index == 1
  end

  test "Enter on board step advances to compose step with selected board" do
    state = base_state()
    # Move to second board first
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :enter}, s1)

    ss = get_ss(s2)
    assert ss.step == :compose
    assert ss.board.id == "b2"
    assert ss.board.name == "Announcements"
  end

  test "Enter on board step with no boards is absorbed by the reducer" do
    ss = State.new(boards: [])
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    result = handle_key_screen(%{key: :enter}, state)
    assert {:update, new_state, []} = result
    assert get_ss(new_state) == ss
  end

  # ---------------------------------------------------------------------------
  # Compose step — navigation
  # ---------------------------------------------------------------------------

  test "Tab switches focus from :title to :body" do
    state = compose_state()
    assert get_ss(state).focused == :title

    {:update, new_state, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(new_state).focused == :body
  end

  test "Tab on :body toggles mode to :preview (Gap 4 — Test 8)" do
    state = compose_state()
    # Advance focus to :body first
    {:update, s1, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s1).focused == :body
    assert get_ss(s1).mode == :edit

    # Tab on body toggles mode, does NOT switch focus back to :title
    {:update, s2, _} = handle_key_screen(%{key: :tab}, s1)
    assert get_ss(s2).mode == :preview
    assert get_ss(s2).focused == :body
  end

  test "Tab on :body in :preview mode toggles back to :edit (Gap 4 — Test 9)" do
    state = compose_state()
    {:update, s1, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    # First Tab: :edit -> :preview
    {:update, s2, _} = handle_key_screen(%{key: :tab}, s1)
    assert get_ss(s2).mode == :preview

    # Second Tab: :preview -> :edit
    {:update, s3, _} = handle_key_screen(%{key: :tab}, s2)
    assert get_ss(s3).mode == :edit
    assert get_ss(s3).focused == :body
  end

  test "Tab on :title advances focus to :body and does NOT toggle mode (Gap 4 — Test 10)" do
    state = compose_state()
    assert get_ss(state).focused == :title
    assert get_ss(state).mode == :edit

    {:update, new_state, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(new_state).focused == :body
    assert get_ss(new_state).mode == :edit
  end

  test "Ctrl+C cancels from compose step to origin screen (default :main_menu)" do
    state = compose_state()
    {:update, new_state, _} = handle_key_screen(%{key: :char, char: "c", ctrl: true}, state)
    assert new_state.current_screen == :main_menu
  end

  # Regression: handle_compose_key/3 clause order is load-bearing. The
  # body-focused fallback forwards to MultiLineInput via Compose.translate_key,
  # which does NOT filter ctrl-modified char events — it produces {:input, ?s}
  # for `%{key: :char, char: "s", ctrl: true}`. If the Ctrl+S / Ctrl+C clauses
  # are moved below the body fallback, the body silently eats "s" / "c" and
  # Submit/Cancel break. The in-source comment at lines 281–288 of
  # screens/new_thread.ex warns about this; these tests enforce it.
  describe "compose-step handle_key/2 clause order regression (TODO #7)" do
    test "Ctrl+S on body-focused compose submits (does not insert 's' into body)" do
      state = compose_state()

      # Set a valid title so submit doesn't fail validation.
      state =
        put_in(
          state.screen_state.new_thread.title_input_state,
          TextInput.init(value: "Regression Title", max_length: 60)
        )

      # Tab to body, type some content.
      {:update, state, _} = handle_key_screen(%{key: :tab}, state)
      assert get_ss(state).focused == :body

      state =
        Enum.reduce(~w[H i], state, fn ch, acc ->
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
        end)

      assert get_ss(state).body_input_state.value == "Hi"

      {:update, after_save, cmds} =
        handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

      # Submit fired and routed to :thread_list with a load_threads command.
      # The body did NOT grow an "s" — i.e., the explicit clause intercepted
      # before falling through to MultiLineInput forwarding.
      assert after_save.current_screen == :thread_list
      assert Enum.any?(cmds, &match?({:load_threads, "b1"}, &1))
    end

    test "Ctrl+C on body-focused compose cancels (does not insert 'c' into body)" do
      state = compose_state()
      {:update, state, _} = handle_key_screen(%{key: :tab}, state)
      assert get_ss(state).focused == :body

      state =
        Enum.reduce(~w[H i], state, fn ch, acc ->
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
        end)

      assert get_ss(state).body_input_state.value == "Hi"

      {:update, after_cancel, _} =
        handle_key_screen(%{key: :char, char: "c", ctrl: true}, state)

      # Cancel routed to origin (default :main_menu) and the body did NOT
      # gain a "c" before transition (would still be "Hi" if it hadn't fired).
      assert after_cancel.current_screen == :main_menu
    end
  end

  test "Ctrl+C with origin: :thread_list routes back to :thread_list" do
    state = compose_state()
    s = put_in(state.screen_state.new_thread.origin, :thread_list)

    {:update, new_state, _} = handle_key_screen(%{key: :char, char: "c", ctrl: true}, s)
    assert new_state.current_screen == :thread_list
  end

  test "Esc cancels from compose step to origin screen (default :main_menu)" do
    state = compose_state()
    {:update, new_state, _} = handle_key_screen(%{key: :escape}, state)
    assert new_state.current_screen == :main_menu
  end

  test "Esc with origin: :thread_list routes back to :thread_list" do
    state = compose_state()
    s = put_in(state.screen_state.new_thread.origin, :thread_list)

    {:update, new_state, _} = handle_key_screen(%{key: :escape}, s)
    assert new_state.current_screen == :thread_list
  end

  # ---------------------------------------------------------------------------
  # Compose step — title input
  # ---------------------------------------------------------------------------

  test "typing characters updates title_input when focused on :title" do
    state = compose_state()
    assert get_ss(state).focused == :title

    {:update, s1, _} = handle_key_screen(%{key: :char, char: "H"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :char, char: "i"}, s1)

    assert title_value(s2) == "Hi"
  end

  test "spacebar appends a space to title" do
    state = compose_state()
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "H"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :char, char: " "}, s1)
    {:update, s3, _} = handle_key_screen(%{key: :char, char: "i"}, s2)

    assert title_value(s3) == "H i"
  end

  test "backspace removes the last character from title" do
    state = compose_state()

    s =
      Enum.reduce(~w[H e l l o], state, fn ch, acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = handle_key_screen(%{key: :backspace}, s)
    assert title_value(s) == "Hell"
  end

  test "backspace on empty title stays empty" do
    state = compose_state()
    {:update, new_state, _} = handle_key_screen(%{key: :backspace}, state)
    assert title_value(new_state) == ""
  end

  test "typing does NOT update title when focused on :body" do
    state = compose_state()
    # Switch to body
    {:update, s1, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    # Typing 'H' should go to body input, not title
    result = handle_key_screen(%{key: :char, char: "H"}, s1)

    case result do
      {:update, new_state, _} ->
        assert title_value(new_state) == ""

      :no_match ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Title length cap (D-13, D-14)
  # ---------------------------------------------------------------------------

  describe "title length cap (D-13, D-14)" do
    test "accepts characters below the cap" do
      s = compose_state() |> put_title("abc")

      {:update, new_state, []} = handle_key_screen(%{key: :char, char: "d"}, s)
      assert title_value(new_state) == "abcd"
    end

    test "rejects characters that would exceed the cap" do
      # 60-char title; next char must be rejected.
      long_title = String.duplicate("x", 60)
      s = compose_state() |> put_title(long_title)

      assert {:update, new_state, []} = handle_key_screen(%{key: :char, char: "y"}, s)
      assert title_value(new_state) == long_title
    end

    test "accepts the final allowed character at cap - 1" do
      title = String.duplicate("x", 59)
      s = compose_state() |> put_title(title)

      {:update, new_state, []} = handle_key_screen(%{key: :char, char: "y"}, s)
      assert String.length(title_value(new_state)) == 60
    end

    test "backspace still works at the cap" do
      s = compose_state() |> put_title(String.duplicate("x", 60))

      {:update, new_state, []} = handle_key_screen(%{key: :backspace}, s)
      assert String.length(title_value(new_state)) == 59
    end
  end

  # ---------------------------------------------------------------------------
  # Compose step — body input (forwarded to MultiLineInput)
  # ---------------------------------------------------------------------------

  test "typing appends to body when focused on :body" do
    state = compose_state()
    {:update, s1, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    {:update, s2, _} = handle_key_screen(%{key: :char, char: "h"}, s1)
    {:update, s3, _} = handle_key_screen(%{key: :char, char: "i"}, s2)

    body_value = get_ss(s3).body_input_state.value
    assert body_value == "hi"
  end

  test "multi-codepoint grapheme keys append intact to body when focused on :body" do
    state = compose_state()
    decomposed = "e\u0301"
    zwj_sequence = "👩\u200D💻"

    {:update, s1, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    {:update, s2, _} = handle_key_screen(%{key: :char, char: decomposed}, s1)
    {:update, s3, _} = handle_key_screen(%{key: :char, char: zwj_sequence}, s2)

    assert get_ss(s3).body_input_state.value == decomposed <> zwj_sequence
  end

  # ---------------------------------------------------------------------------
  # Submit — success path
  # ---------------------------------------------------------------------------

  test "Ctrl+S with valid title and body navigates to :thread_list and dispatches {:load_threads}" do
    state = compose_state()

    # Type title using :char events
    s =
      Enum.reduce(~w[M y   T h r e a d], state, fn ch, acc ->
        key =
          if ch == " " do
            %{key: :char, char: " "}
          else
            %{key: :char, char: ch}
          end

        {:update, next, _} = handle_key_screen(key, acc)
        next
      end)

    # Switch to body and type content
    {:update, s, _} = handle_key_screen(%{key: :tab}, s)

    s =
      Enum.reduce(~w[H e l l o], s, fn ch, acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, cmds} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :thread_list
    assert Enum.any?(cmds, &match?({:load_threads, "b1"}, &1))
  end

  test "Ctrl+S submits one-line new-thread body exactly after compact render" do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"

    state =
      compose_state()
      |> put_title("Wrapped Submit")

    ss = %{
      get_ss(state)
      | focused: :body,
        mode: :edit,
        body_input_state: fresh_input(long_body)
    }

    state = %{put_in(state.screen_state.new_thread, ss) | terminal_size: {64, 22}}

    _ = render_screen(state)
    {:update, final, cmds} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

    assert final.current_screen == :thread_list
    assert Enum.any?(cmds, &match?({:load_threads, "b1"}, &1))
    assert Process.get(:new_thread_last_attrs).body == long_body
    refute Process.get(:new_thread_last_attrs).body =~ "\n"
  end

  test "Ctrl+S with {:ok, %{thread: thread}} dispatches {:load_threads, board_id} from wizard" do
    state = compose_state(%{id: "b1", name: "General"})

    s =
      put_in(
        state.screen_state.new_thread.title_input_state,
        TextInput.init(value: "Test Thread", max_length: 60)
      )

    # Type body
    {:update, s, _} = handle_key_screen(%{key: :tab}, s)

    s =
      Enum.reduce(~w[H i], s, fn ch, acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, cmds} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_screen == :thread_list
    assert Enum.any?(cmds, &match?({:load_threads, "b1"}, &1))
  end

  # ---------------------------------------------------------------------------
  # Submit — error paths
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty title shows error, stays on compose" do
    state = compose_state()
    # Switch to body, type content, but leave title empty
    {:update, s, _} = handle_key_screen(%{key: :tab}, state)

    s =
      Enum.reduce(~w[H i], s, fn ch, acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_screen == :new_thread
    ss = get_ss(final)
    assert ss.error =~ "Title"
  end

  test "Ctrl+S with empty body shows error, stays on compose" do
    state = compose_state()
    # Set title but leave body empty
    s =
      put_in(
        state.screen_state.new_thread.title_input_state,
        TextInput.init(value: "Has Title", max_length: 60)
      )

    {:update, final, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_screen == :new_thread
    assert get_ss(final).error =~ "body"
  end

  test "Ctrl+S with body over max_post_length shows error and does not create thread" do
    state =
      compose_state()
      |> Map.put(:session_context, %{
        max_post_length: 5,
        domain: %{boards: FakeBoards, threads: FakeThreadsOk}
      })

    ss = %{
      get_ss(state)
      | title_input_state: TextInput.init(value: "Has Title", max_length: 60),
        body_input_state: fresh_input("too long")
    }

    state = put_in(state.screen_state.new_thread, ss)

    {:update, final, cmds} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

    assert final.current_screen == :new_thread
    assert get_ss(final).error =~ "maximum length"
    refute Enum.any?(cmds, &match?({:load_threads, _}, &1))
  end

  test "Ctrl+S on error from domain stays on compose with error set" do
    state =
      base_state(%{
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsError}}
      })

    board = %{id: "b1", name: "General"}

    ss =
      State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "My Thread", max_length: 60),
        body_input_state: fresh_input("Hello")
      )

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :new_thread
    assert get_ss(final).error != nil
  end

  test "Ctrl+S with posting-policy denial stays on compose with clear copy (POST-04)" do
    state =
      base_state(%{
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsError}}
      })

    board = %{id: "b1", name: "General"}

    ss =
      State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "policy", max_length: 60),
        body_input_state: fresh_input("Hello")
      )

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :new_thread
    assert Map.has_key?(final.screen_state, :new_thread)
    assert get_ss(final).error == "You are not allowed to post on this board."
  end

  test "Ctrl+S without current_user stores reducer error" do
    state =
      base_state(%{
        current_user: nil,
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsMissing}}
      })

    board = %{id: "b1", name: "General"}

    ss =
      State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "My Thread", max_length: 60),
        body_input_state: fresh_input("Hello")
      )

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

    assert get_ss(final).error =~ "logged in"
  end

  # ---------------------------------------------------------------------------
  # Preview mode — D-11 delegation to Post.MarkdownBody
  # ---------------------------------------------------------------------------

  test "Tab on body toggles to :preview mode" do
    state = compose_state()
    # Tab to body
    {:update, s, _} = handle_key_screen(%{key: :tab}, state)
    assert get_ss(s).focused == :body
    assert get_ss(s).mode == :edit

    # Tab on body toggles to preview
    {:update, s, _} = handle_key_screen(%{key: :tab}, s)
    assert get_ss(s).mode == :preview
    assert get_ss(s).focused == :body
  end

  test "render/1 in :compose step + :preview mode does not crash on markdown input" do
    {:ok, body_input} =
      MultiLineInput.init(%{
        value: "# Thread Title\n\nOpening post with **emphasis**.",
        placeholder: "Write your opening post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: false
      })

    board = %{id: "b1", name: "General"}

    ss =
      State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "Test Thread", max_length: 60),
        body_input_state: body_input,
        focused: :body,
        mode: :preview
      )

    state =
      Map.put(
        base_state(%{session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsOk}}}),
        :screen_state,
        %{new_thread: ss}
      )

    # render/1 is pure — calling it should not raise.
    assert render_screen(state) != nil
  end
end

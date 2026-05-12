defmodule Foglet.TUI.Screens.ThreadListTest.FakeThreads do
  @now ~U[2026-04-28 18:00:00Z]

  def list_threads(_board_id) do
    [
      %{
        id: "t3",
        title: "Brand new thread",
        sticky: false,
        locked: false,
        last_post_at: nil,
        post_count: 1,
        created_by: %{handle: "carol"}
      },
      %{
        id: "t2",
        title: "Recent non-sticky",
        sticky: false,
        locked: false,
        last_post_at: DateTime.add(@now, -60, :second),
        post_count: 3,
        created_by: %{handle: "bob"}
      },
      %{
        id: "t1",
        title: "Old but sticky",
        sticky: true,
        locked: true,
        last_post_at: DateTime.add(@now, -10_000, :second),
        post_count: 20,
        created_by: %{handle: "alice"}
      }
    ]
  end

  def list_threads(board_id, nil), do: list_threads(board_id)

  def list_threads(board_id, _user_id) do
    board_id
    |> list_threads()
    |> Enum.map(&Map.put(&1, :has_unread, &1.id == "t1"))
  end
end

defmodule Foglet.TUI.Screens.ThreadListTest.EmptyThreads do
  def list_threads(_board_id, _user_id), do: []
end

defmodule Foglet.TUI.Screens.ThreadListTest.OneArityOnly do
  def list_threads(_board_id) do
    [
      %{
        id: "legacy",
        title: "Legacy thread",
        sticky: false,
        last_post_at: ~U[2026-04-28 18:00:00Z],
        post_count: 1,
        created_by: %{handle: "ancient"}
      }
    ]
  end
end

defmodule Foglet.TUI.Screens.ThreadListTest.HandlelessThreads do
  def list_threads(_board_id, _user_id) do
    [
      %{
        id: "handleless",
        title: "Anonymous thread",
        sticky: false,
        locked: false,
        last_post_at: nil,
        post_count: 1,
        created_by: nil,
        has_unread: false
      }
    ]
  end
end

defmodule Foglet.TUI.Screens.ThreadListTest.FakeBoards do
  def board_directory_for(user), do: [%{category: %{name: "General"}, user_id: user && user.id}]
end

defmodule Foglet.TUI.Screens.ThreadListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.{Context, Effect, TextWidth}
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.Screens.ThreadList.State

  alias Foglet.TUI.Screens.ThreadListTest.{
    EmptyThreads,
    FakeBoards,
    FakeThreads,
    HandlelessThreads,
    OneArityOnly
  }

  @board %{id: "b1", name: "General", slug: "general"}
  @user %Foglet.Accounts.User{id: "u1", handle: "alice"}
  @active_user %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user, status: :active}

  defp context(overrides \\ []) do
    threads = Keyword.get(overrides, :threads, FakeThreads)
    route_params = Keyword.get(overrides, :route_params, %{board: @board, board_id: "b1"})

    Context.new(
      current_user: Keyword.get(overrides, :current_user, @user),
      route: :thread_list,
      route_params: route_params,
      terminal_size: Keyword.get(overrides, :terminal_size, {80, 24}),
      session_context: %{domain: %{threads: threads, boards: FakeBoards}}
    )
  end

  defp load_state(ctx \\ context()) do
    state = ThreadList.init(ctx)

    {loading_state, [%Effect{type: :task, payload: payload} = effect]} =
      ThreadList.update(:load, state, ctx)

    assert effect == Effect.task(:load_threads, :thread_list, payload.fun)
    rows = payload.fun.()

    {loaded_state, []} =
      ThreadList.update({:task_result, :load_threads, {:ok, rows}}, loading_state, ctx)

    loaded_state
  end

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

  defp find_type(%{type: type} = node, type), do: node

  defp find_type(%{children: children}, type) when is_list(children) do
    Enum.find_value(children, &find_type(&1, type))
  end

  defp find_type(children, type) when is_list(children),
    do: Enum.find_value(children, &find_type(&1, type))

  defp find_type(_node, _type), do: nil

  defp leading_cluster_for(flat, title) do
    case String.split(flat, title, parts: 2) do
      [before_title, _rest] ->
        before_title
        |> String.graphemes()
        |> Enum.take(-4)
        |> Enum.join()

      _ ->
        flunk("title #{inspect(title)} not found in render output: #{inspect(flat)}")
    end
  end

  test "ThreadList.State.from_context/1 stores board route params and selected index" do
    ctx = context(route_params: %{board: @board, board_id: "b1", select_thread_id: "t2"})

    assert %State{
             board: @board,
             board_id: "b1",
             threads: nil,
             selected_index: 0,
             select_thread_id: "t2",
             status: :loading
           } = ThreadList.State.from_context(ctx)
  end

  test "ThreadList.State.from_context/1 stores string select_thread_id route param" do
    ctx = context(route_params: %{"board" => @board, "select_thread_id" => "t2"})

    assert %State{select_thread_id: "t2"} = ThreadList.State.from_context(ctx)
  end

  test "init/1 derives board_id from board when the route omits board_id" do
    board = %{"id" => "b1", "name" => "General"}
    ctx = context(route_params: %{"board" => board})

    assert %State{board: ^board, board_id: "b1", selected_index: 0} = ThreadList.init(ctx)
  end

  test "ThreadList.update(:load, state, context) emits load_threads task effect" do
    ctx = context()
    state = ThreadList.init(ctx)

    assert {%State{status: :loading, last_op: :load_threads, last_error: nil},
            [
              %Effect{
                type: :task,
                payload: %{op: :load_threads, screen_key: :thread_list, fun: fun}
              }
            ]} =
             ThreadList.update(:load, state, ctx)

    assert is_function(fun, 0)
  end

  test "ThreadList.update(:load, state, context) without board_id records missing board error" do
    ctx = context(route_params: %{})
    state = ThreadList.init(ctx)

    assert {%State{status: {:error, :missing_board}, last_error: :missing_board}, []} =
             ThreadList.update(:load, state, ctx)
  end

  test "render/2 switches thread list to a structural list and preview split at enhanced size" do
    ctx = context(terminal_size: {120, 36})
    state = load_state(ctx)

    split = ThreadList.render(state, ctx) |> find_type(:split_pane)

    assert %{
             attrs: %{direction: :horizontal, ratio: {7, 5}},
             children: [_list_panel, _preview_panel]
           } =
             split

    rendered_text = ThreadList.render(state, ctx) |> flatten_text()

    assert rendered_text =~ "Old but sticky"
    assert rendered_text =~ "Preview"
    assert rendered_text =~ "Unread for you: yes"
  end

  test "render/2 preserves single-pane thread list below enhanced size" do
    ctx = context(terminal_size: {80, 24})
    state = load_state(ctx)

    refute ThreadList.render(state, ctx) |> find_type(:split_pane)
  end

  test "load task execution with FakeThreads stores 3 sorted rows" do
    state = load_state()

    assert %State{status: :loaded, threads: threads, selected_index: 0} = state
    assert Enum.map(threads, & &1.id) == ["t1", "t2", "t3"]
  end

  test "load success stores sticky first and non-sticky newest-first with nil times last" do
    assert %State{threads: [sticky, newest, nil_time]} = load_state()

    assert sticky.id == "t1"
    assert sticky.sticky == true
    assert newest.id == "t2"
    assert nil_time.id == "t3"
    assert nil_time.last_post_at == nil
  end

  test "load success selects matching select_thread_id after sorting and clears intent" do
    ctx = context()
    %State{} = state = ThreadList.init(ctx)
    state = %{state | select_thread_id: "t2"}

    {loading_state, [%Effect{payload: payload}]} = ThreadList.update(:load, state, ctx)

    assert {%State{selected_index: 1, select_thread_id: nil, threads: threads}, []} =
             ThreadList.update(
               {:task_result, :load_threads, {:ok, payload.fun.()}},
               loading_state,
               ctx
             )

    assert Enum.map(threads, & &1.id) == ["t1", "t2", "t3"]
  end

  test "load success without matching select_thread_id falls back to clamped existing selection" do
    ctx = context()
    %State{} = state = ThreadList.init(ctx)
    state = %{state | selected_index: 99, select_thread_id: "missing"}

    {loading_state, [%Effect{payload: payload}]} = ThreadList.update(:load, state, ctx)

    assert {%State{selected_index: 2, select_thread_id: nil}, []} =
             ThreadList.update(
               {:task_result, :load_threads, {:ok, payload.fun.()}},
               loading_state,
               ctx
             )
  end

  test "empty load success sets empty status and selected_index 0" do
    state = load_state(context(threads: EmptyThreads))

    assert %State{status: :empty, threads: [], selected_index: 0} = state
  end

  test "load failure sets error status while preserving loaded rows and clamping selection" do
    state = %{load_state() | selected_index: 99}

    assert {%State{
              status: {:error, :boom},
              last_error: :boom,
              selected_index: 2,
              threads: threads
            }, []} =
             ThreadList.update(
               {:task_result, :load_threads, {:error, :boom}},
               state,
               context()
             )

    assert Enum.map(threads, & &1.id) == ["t1", "t2", "t3"]
  end

  test "down/up key messages clamp selected_index" do
    state = load_state()

    {state, []} = ThreadList.update({:key, %{key: :down}}, state, context())
    assert state.selected_index == 1

    {state, []} = ThreadList.update({:key, %{key: :char, char: "j"}}, state, context())
    {state, []} = ThreadList.update({:key, %{key: :char, char: "j"}}, state, context())
    assert state.selected_index == 2

    {state, []} = ThreadList.update({:key, %{key: :up}}, state, context())
    {state, []} = ThreadList.update({:key, %{key: :char, char: "k"}}, state, context())
    {state, []} = ThreadList.update({:key, %{key: :char, char: "k"}}, state, context())
    assert state.selected_index == 0
  end

  test "Enter emits Effect.navigate(:post_reader, params) for the selected sorted thread" do
    state = load_state()

    assert {^state,
            [
              %Effect{
                type: :navigate,
                payload: %{
                  screen: :post_reader,
                  params: %{board: @board, board_id: "b1", thread: thread, thread_id: "t1"}
                }
              }
            ]} = ThreadList.update({:key, %{key: :enter}}, state, context())

    assert thread.id == "t1"

    assert Effect.navigate(:post_reader, %{
             board: @board,
             board_id: "b1",
             thread: thread,
             thread_id: "t1"
           })
  end

  test "Enter with no selected thread emits no effects" do
    state = State.new(board: @board, board_id: "b1", threads: [], status: :empty)

    assert {^state, []} = ThreadList.update({:key, %{key: :enter}}, state, context())
  end

  test "C emits Effect.navigate(:new_thread, origin and board params)" do
    state = load_state()

    assert {^state,
            [
              %Effect{
                type: :navigate,
                payload: %{
                  screen: :new_thread,
                  params: %{origin: :thread_list, board: @board, board_id: "b1"}
                }
              }
            ]} = ThreadList.update({:key, %{key: :char, char: "C"}}, state, context())

    assert Effect.navigate(:new_thread, %{origin: :thread_list, board: @board, board_id: "b1"})
  end

  test "lowercase c emits the same new_thread route params" do
    state = load_state()

    assert {^state,
            [
              %Effect{
                type: :navigate,
                payload: %{
                  screen: :new_thread,
                  params: %{origin: :thread_list, board: @board, board_id: "b1"}
                }
              }
            ]} = ThreadList.update({:key, %{key: :char, char: "c"}}, state, context())
  end

  test "C emits no navigation when board posting is disabled" do
    board = Map.merge(@board, %{archived: true, postable_by: :members})
    state = State.new(board: board, board_id: "b1", threads: [], status: :empty)
    ctx = context(current_user: @active_user, route_params: %{board: board, board_id: "b1"})

    assert {^state, []} = ThreadList.update({:key, %{key: :char, char: "C"}}, state, ctx)
  end

  test "Q emits board_list navigation plus BoardList-owned refresh task" do
    state = load_state()

    assert {^state,
            [
              %Effect{type: :navigate, payload: %{screen: :board_list, params: %{}}},
              %Effect{
                type: :task,
                payload: %{op: :load_boards, screen_key: :board_list, fun: fun}
              }
            ]} = ThreadList.update({:key, %{key: :char, char: "Q"}}, state, context())

    assert Effect.navigate(:board_list, %{})
    assert [%{category: %{name: "General"}, user_id: "u1"}] = fun.()
  end

  test "lowercase q returns through the BoardList refresh path" do
    state = load_state()

    assert {^state,
            [
              %Effect{type: :navigate, payload: %{screen: :board_list, params: %{}}},
              %Effect{type: :task, payload: %{op: :load_boards, screen_key: :board_list}}
            ]} = ThreadList.update({:key, %{key: :char, char: "q"}}, state, context())
  end

  test "one-arity thread loaders are annotated with has_unread false" do
    state = load_state(context(threads: OneArityOnly))

    assert [%{id: "legacy", has_unread: false}] = state.threads
  end

  test "render/2 has loading and empty smoke branches" do
    ctx = context()
    loading = ThreadList.init(ctx)
    empty = State.new(board: @board, board_id: "b1", threads: [], status: :empty)

    assert flatten_text(ThreadList.render(loading, ctx)) =~ "Loading…"
    assert flatten_text(ThreadList.render(empty, ctx)) =~ "No threads in this board yet"
  end

  test "render/2 preserves row metadata, glyphs, and fixed leading-cluster width" do
    ctx = context()
    state = load_state(ctx)
    flat = flatten_text(ThreadList.render(state, ctx))

    assert flat =~ "@alice"
    assert flat =~ "20 posts"
    assert flat =~ "1 post"
    assert flat =~ "ago"
    assert flat =~ "◆"
    assert flat =~ "●"
    assert flat =~ "⚿"
    refute flat =~ "[S] "

    active_cluster = leading_cluster_for(flat, "Recent non-sticky")
    sticky_locked_cluster = leading_cluster_for(flat, "Old but sticky")

    assert TextWidth.display_width(active_cluster) ==
             TextWidth.display_width(sticky_locked_cluster)
  end

  test "render/2 shows archived banner and suppresses compose command" do
    board = Map.merge(@board, %{archived: true, postable_by: :members})
    state = State.new(board: board, board_id: "b1", threads: [], status: :empty)
    ctx = context(current_user: @active_user, route_params: %{board: board, board_id: "b1"})
    flat = flatten_text(ThreadList.render(state, ctx))

    assert flat =~ "This board is archived. New threads and replies are disabled."
    refute flat =~ "CCompose"
    refute flat =~ "C Compose"
  end

  test "render/2 maps read-only and unsubscribed banners with documented precedence" do
    read_only_board = Map.merge(@board, %{archived: false, postable_by: :mods_only})

    read_only_state =
      State.new(board: read_only_board, board_id: "b1", threads: [], status: :empty)

    read_only_ctx =
      context(
        current_user: @active_user,
        route_params: %{board: read_only_board, board_id: "b1"}
      )

    read_only_flat = flatten_text(ThreadList.render(read_only_state, read_only_ctx))
    assert read_only_flat =~ "This board is read-only."

    unsubscribed_state =
      State.new(
        board: Map.merge(@board, %{archived: false, postable_by: :members}),
        board_id: "b1",
        subscribed?: false,
        threads: [],
        status: :empty
      )

    unsubscribed_flat = flatten_text(ThreadList.render(unsubscribed_state, read_only_ctx))

    assert unsubscribed_flat =~
             "You're not subscribed to this board. Press S on Boards to subscribe."

    archived_unsubscribed =
      State.new(
        board: Map.merge(@board, %{archived: true, postable_by: :mods_only}),
        board_id: "b1",
        subscribed?: false,
        threads: [],
        status: :empty
      )

    archived_flat = flatten_text(ThreadList.render(archived_unsubscribed, read_only_ctx))
    assert archived_flat =~ "This board is archived. New threads and replies are disabled."
    refute archived_flat =~ "This board is read-only."
    refute archived_flat =~ "You're not subscribed"
  end

  test "render/2 falls back to @unknown and new for handleless nil-time rows" do
    ctx = context(threads: HandlelessThreads)
    state = load_state(ctx)
    flat = flatten_text(ThreadList.render(state, ctx))

    assert flat =~ "@unknown"
    assert flat =~ "new"
  end

  describe "subscriptions/2 export (Phase 39 R6, D-08)" do
    test "returns board topic from local state" do
      state = %Foglet.TUI.Screens.ThreadList.State{board_id: "b-77"}
      ctx = %Foglet.TUI.Context{route_params: %{}}

      assert Foglet.TUI.Screens.ThreadList.subscriptions(state, ctx) == ["board:b-77"]
    end

    test "returns board topic from atom-key route params when local state is empty" do
      ctx = %Foglet.TUI.Context{route_params: %{board_id: "b-route"}}

      assert Foglet.TUI.Screens.ThreadList.subscriptions(nil, ctx) == ["board:b-route"]
    end

    test "returns board topic from string-key route params when local state is empty" do
      ctx = %Foglet.TUI.Context{route_params: %{"board_id" => "b-string"}}

      assert Foglet.TUI.Screens.ThreadList.subscriptions(nil, ctx) == ["board:b-string"]
    end

    test "returns [] when no board id is available" do
      ctx = %Foglet.TUI.Context{route_params: %{}}

      assert Foglet.TUI.Screens.ThreadList.subscriptions(nil, ctx) == []
    end
  end

  describe "update(:on_route_enter, …) — Phase 39 Plan 04" do
    # ThreadList's route-entry semantics today (app.ex:834-836) is unconditional:
    # always dispatch :load. The screen's :load clause has the missing-board
    # guard built in, so unconditional delegation is safe.

    test "delegates unconditionally to :load (parity with direct :load call)" do
      ctx = context()
      state = ThreadList.init(ctx)

      {state_via_on_enter, effects_via_on_enter} =
        ThreadList.update(:on_route_enter, state, ctx)

      {state_via_load, effects_via_load} =
        ThreadList.update(:load, state, ctx)

      assert state_via_on_enter == state_via_load
      assert effects_via_on_enter == effects_via_load

      assert state_via_on_enter.status == :loading

      assert [%Effect{type: :task, payload: %{op: :load_threads}}] = effects_via_on_enter
    end

    test "delegates to :load even with no current_user (parity with App's app.ex:834-836)" do
      # App's per-screen ThreadList clause has no user check today.
      ctx = context(current_user: nil)
      state = ThreadList.init(ctx)

      {state_via_on_enter, effects} = ThreadList.update(:on_route_enter, state, ctx)

      assert state_via_on_enter.status == :loading

      assert [%Effect{type: :task, payload: %{op: :load_threads}}] = effects
    end

    test "missing board_id falls through to :load's error guard (no crash)" do
      # ThreadList.update(:load, %State{}, ctx) (with no board_id) routes to
      # the second :load clause that returns {:error, :missing_board}. The
      # :on_route_enter clause must surface that same outcome rather than crash.
      ctx = context(route_params: %{})
      state = %State{}

      {new_state, effects} = ThreadList.update(:on_route_enter, state, ctx)

      assert new_state.status == {:error, :missing_board}
      assert effects == []
    end
  end
end

defmodule Foglet.TUI.Screens.BoardScreenTest.FakeBoards do
  @moduledoc false
  def board_directory_for(_user), do: []
end

defmodule Foglet.TUI.Screens.BoardScreenTest.FakeThreads do
  @moduledoc false
  def list_threads(_board_id), do: []
  def list_threads(_board_id, _user_id), do: []
end

defmodule Foglet.TUI.Screens.BoardScreenTest do
  use ExUnit.Case, async: false

  alias Foglet.PubSub, as: Topics
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardScreen
  alias Foglet.TUI.Screens.BoardScreen.State, as: WrapperState
  alias Foglet.TUI.Screens.ThreadList

  alias Foglet.TUI.Screens.BoardScreenTest.FakeBoards
  alias Foglet.TUI.Screens.BoardScreenTest.FakeThreads

  @user %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user, status: :active}

  defp board(opts) do
    %{
      id: Keyword.get(opts, :id, "b-" <> Ecto.UUID.generate()),
      name: Keyword.get(opts, :name, "General"),
      slug: "general",
      archived: false,
      postable_by: :members,
      chat_enabled: Keyword.get(opts, :chat_enabled, false)
    }
  end

  defp context(b) do
    Context.new(
      current_user: @user,
      route: :thread_list,
      route_params: %{board: b, board_id: b.id},
      terminal_size: {80, 24},
      session_context: %{domain: %{threads: FakeThreads, boards: FakeBoards}}
    )
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

  describe "init/1 — chat disabled" do
    test "returns a ThreadList.State and bypasses the wrapper" do
      ctx = context(board(chat_enabled: false))

      assert %ThreadList.State{} = BoardScreen.init(ctx)
    end

    test "render delegates byte-equivalently to ThreadList" do
      ctx = context(board(chat_enabled: false))
      state = BoardScreen.init(ctx)

      wrapper_text = BoardScreen.render(state, ctx) |> flatten_text()
      direct_text = ThreadList.render(state, ctx) |> flatten_text()

      assert wrapper_text == direct_text
      refute wrapper_text =~ "1 THREADS"
      refute wrapper_text =~ "CHAT"
    end

    test "subscriptions match ThreadList exactly" do
      ctx = context(board(chat_enabled: false))
      state = BoardScreen.init(ctx)

      assert BoardScreen.subscriptions(state, ctx) == ThreadList.subscriptions(state, ctx)
    end

    test "update delegates to ThreadList for thread loading" do
      ctx = context(board(chat_enabled: false))
      state = BoardScreen.init(ctx)

      {loading, [%Effect{type: :task, payload: %{op: :load_threads}}]} =
        BoardScreen.update(:load, state, ctx)

      assert %ThreadList.State{status: :loading} = loading
    end
  end

  describe "init/1 — chat enabled" do
    test "returns a wrapper state with current_tab :threads" do
      b = board(chat_enabled: true)
      ctx = context(b)

      assert %WrapperState{
               current_tab: :threads,
               presence_count: 0,
               presence_tracked?: false,
               board_id: id,
               user_id: "u1"
             } = BoardScreen.init(ctx)

      assert id == b.id
    end

    test "subscriptions include the board_screen presence topic" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)

      topics = BoardScreen.subscriptions(state, ctx)

      assert Topics.board_screen_topic(b.id) in topics
      assert Topics.board_topic(b.id) in topics
    end
  end

  describe "render/2 — chat enabled" do
    test "renders a tab strip with THREADS + CHAT (#)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)

      text = BoardScreen.render(state, ctx) |> flatten_text()

      assert text =~ "1 THREADS"
      assert text =~ "2 CHAT (0)"
      assert text =~ "▌"
    end

    test "tab strip CHAT count reflects FOG-250 presence count" do
      b = board(chat_enabled: true)
      ctx = context(b)

      task =
        Task.async(fn ->
          :ok = PresenceTracker.track(b.id, "remote-1", :chat)
          :ok = PresenceTracker.track(b.id, "remote-2", :chat)

          receive do
            :stop -> :ok
          end
        end)

      Stream.repeatedly(fn ->
        if PresenceTracker.count(b.id) >= 2, do: :ok, else: :wait
      end)
      |> Stream.take_while(&(&1 == :wait))
      |> Stream.run()

      state = BoardScreen.init(ctx)
      {state, _effects} = BoardScreen.update(:on_route_enter, state, ctx)

      text = BoardScreen.render(state, ctx) |> flatten_text()
      assert text =~ "2 CHAT (3)"

      send(task.pid, :stop)
      Task.await(task)

      :ok = PresenceTracker.untrack(b.id, "u1")
    end
  end

  describe "tab switching" do
    test "pressing 2 switches to the chat tab and updates presence" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)

      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)
      assert state.current_tab == :threads

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)
      assert state.current_tab == :chat

      assert PresenceTracker.list(b.id) == [%{user_id: "u1", tab: :chat}]

      text = BoardScreen.render(state, ctx) |> flatten_text()
      # FOG-254 C6 replaced the placeholder body with the real ChatRoom view.
      # The empty-state line is the cheapest signal that the chat tab body
      # is rendered instead of the threads list.
      assert text =~ "No messages yet"

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "left arrow from chat returns to threads (back-nav)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)
      assert state.current_tab == :chat

      {state, []} = BoardScreen.update({:key, %{key: :left}}, state, ctx)
      assert state.current_tab == :threads

      assert PresenceTracker.list(b.id) == [%{user_id: "u1", tab: :threads}]

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    # FOG-282: digit shortcuts on the chat tab fall through to the chat
    # composer so messages containing '1' or '2' are not truncated by the
    # tab-switch handler. Back-nav from chat is via ←/→ instead.
    test "digits in chat composer are typed, not consumed as tab switches (FOG-282)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)
      assert state.current_tab == :chat

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "h"}}, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "i"}}, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: " "}}, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "1"}}, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "3"}}, state, ctx)

      assert state.current_tab == :chat
      assert state.chat_room.composer == "hi 123"

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "right/left arrows cycle between threads and chat" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :right}}, state, ctx)
      assert state.current_tab == :chat

      {state, []} = BoardScreen.update({:key, %{key: :left}}, state, ctx)
      assert state.current_tab == :threads

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "Q untracks presence and delegates back-nav to ThreadList" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      assert PresenceTracker.count(b.id) == 1

      {_state, effects} = BoardScreen.update({:key, %{key: :char, char: "Q"}}, state, ctx)

      assert PresenceTracker.count(b.id) == 0

      assert Enum.any?(effects, fn
               %Effect{type: :navigate, payload: %{screen: :board_list}} -> true
               _ -> false
             end)
    end

    test "q from threads tab still triggers back-nav (FOG-279 regression guard)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)
      assert state.current_tab == :threads

      {_state, effects} = BoardScreen.update({:key, %{key: :char, char: "q"}}, state, ctx)

      assert PresenceTracker.count(b.id) == 0

      assert Enum.any?(effects, fn
               %Effect{type: :navigate, payload: %{screen: :board_list}} -> true
               _ -> false
             end)
    end

    test "q/Q in chat composer is typed, not consumed as back-nav (FOG-279)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)
      assert state.current_tab == :chat

      {state, e1} = BoardScreen.update({:key, %{key: :char, char: "q"}}, state, ctx)
      {state, e2} = BoardScreen.update({:key, %{key: :char, char: "a"}}, state, ctx)
      {state, e3} = BoardScreen.update({:key, %{key: :char, char: "b"}}, state, ctx)
      {state, e4} = BoardScreen.update({:key, %{key: :char, char: "c"}}, state, ctx)
      {state, e5} = BoardScreen.update({:key, %{key: :char, char: "Q"}}, state, ctx)

      assert state.current_tab == :chat
      assert state.chat_room.composer == "qabcQ"

      for effects <- [e1, e2, e3, e4, e5] do
        refute Enum.any?(effects, fn
                 %Effect{type: :navigate, payload: %{screen: :board_list}} -> true
                 _ -> false
               end)
      end

      :ok = PresenceTracker.untrack(b.id, "u1")
    end
  end

  describe "presence broadcasts" do
    test "{:board_screen, :join, _} refreshes the count" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      task =
        Task.async(fn ->
          :ok = PresenceTracker.track(b.id, "remote-1", :chat)

          receive do
            :stop -> :ok
          end
        end)

      Stream.repeatedly(fn ->
        if PresenceTracker.count(b.id) >= 2, do: :ok, else: :wait
      end)
      |> Stream.take_while(&(&1 == :wait))
      |> Stream.run()

      {state, []} =
        BoardScreen.update(
          {:board_screen, :join, %{board_id: b.id, user_id: "remote-1", tab: :chat}},
          state,
          ctx
        )

      assert state.presence_count == 2

      send(task.pid, :stop)
      Task.await(task)

      :ok = PresenceTracker.untrack(b.id, "u1")
    end
  end
end

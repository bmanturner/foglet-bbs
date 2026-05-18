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

  import Foglet.TUI.Test, only: [assert_screen: 2, sigil_B: 2]

  alias Foglet.PubSub, as: Topics
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardScreen
  alias Foglet.TUI.Screens.BoardScreen.State, as: WrapperState
  alias Foglet.TUI.Screens.BoardScreenTest.FakeBoards
  alias Foglet.TUI.Screens.BoardScreenTest.FakeThreads
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.TextWidth
  alias Raxol.UI.Layout.Engine

  @user %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user, status: :active}
  @sysop %Foglet.Accounts.User{id: "u2", handle: "root", role: :sysop, status: :active}

  defp board(opts) do
    %{
      id: Keyword.get(opts, :id, "b-" <> Ecto.UUID.generate()),
      name: Keyword.get(opts, :name, "General"),
      slug: "general",
      archived: false,
      postable_by: :members,
      chat_enabled: Keyword.get(opts, :chat_enabled, false),
      description: Keyword.get(opts, :description),
      news_enabled: Keyword.get(opts, :news_enabled, false)
    }
  end

  defp context(b, opts \\ []) do
    Context.new(
      current_user: Keyword.get(opts, :user, @user),
      route: :thread_list,
      route_params: %{board: b, board_id: b.id, news_enabled: b.news_enabled},
      terminal_size: Keyword.get(opts, :size, {80, 24}),
      session_context: %{
        clock_now: ~U[2026-01-01 17:43:00Z],
        domain: %{threads: FakeThreads, boards: FakeBoards}
      }
    )
  end

  defp render_buffer(state, ctx, {width, height} = size) do
    state
    |> BoardScreen.render(%{ctx | terminal_size: size})
    |> AsciiRenderer.render({width, height})
  end

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp positioned_text_elements(tree, width \\ 80, height \\ 24) do
    tree
    |> Engine.apply_layout(%{width: width, height: height})
    |> List.flatten()
    |> Enum.filter(fn el ->
      el.type == :text and is_binary(Map.get(el, :text, "")) and Map.get(el, :text, "") != ""
    end)
  end

  defp row_text(elements, text) do
    anchor = Enum.find(elements, &(&1.text == text))
    assert %{y: y} = anchor

    elements
    |> Enum.filter(&(&1.y == y))
    |> Enum.sort_by(& &1.x)
    |> Enum.map_join(& &1.text)
  end

  defp bottom_row_text(tree, width, height) do
    elements = positioned_text_elements(tree, width, height)
    bottom_y = elements |> Enum.map(& &1.y) |> Enum.max()

    elements
    |> Enum.filter(&(&1.y == bottom_y))
    |> Enum.sort_by(& &1.x)
    |> Enum.map_join(& &1.text)
  end

  defp text_element(elements, text) do
    Enum.find(elements, &(&1.text == text))
  end

  defp chat_message(index, board_id, user_id \\ "u1") do
    %{
      id: "m#{index}",
      board_id: board_id,
      user_id: user_id,
      body: "transcript row #{index} " <> String.duplicate("wrap ", 8),
      inserted_at: nil
    }
  end

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
    test "wraps no-chat boards when NEWS is enabled" do
      b = board(chat_enabled: false, news_enabled: true)
      ctx = context(b)

      assert %WrapperState{tabs: [:threads, :news], current_tab: :threads} = BoardScreen.init(ctx)
    end

    test "operator CONFIG appears after typical THREADS CHAT NEWS order" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b, user: @sysop)

      state = BoardScreen.init(ctx)

      assert %WrapperState{tabs: [:threads, :chat, :news, :config]} = state
      text = BoardScreen.render(state, ctx) |> flatten_text()
      assert text =~ "THREADS"
      assert text =~ "CHAT (0)"
      assert text =~ "NEWS"
      assert text =~ "CONFIG"
    end

    test "regular user does not see CONFIG" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b)

      assert %WrapperState{tabs: [:threads, :chat, :news]} = BoardScreen.init(ctx)
    end

    test "route-enter child load tasks target the active board screen" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b, user: @sysop)
      state = BoardScreen.init(ctx)

      {_state, effects} = BoardScreen.update(:on_route_enter, state, ctx)

      task_keys =
        effects
        |> Enum.filter(&match?(%Effect{type: :task}, &1))
        |> Enum.map(& &1.payload.screen_key)

      assert Effect.current_screen_key() in task_keys
      refute Enum.any?(task_keys, &match?({_, _}, &1))
    end

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

      %{topics: topics} = BoardScreen.subscriptions(state, ctx)

      assert Topics.board_screen_topic(b.id) in topics
      assert Topics.board_topic(b.id) in topics
    end
  end

  describe "render/2 — chat enabled" do
    test "threads tab default shell matches a full buffer snapshot" do
      b = board(id: "b-snapshot", chat_enabled: true)
      ctx = context(b, size: {64, 22})
      state = BoardScreen.init(ctx)

      assert_screen(render_buffer(state, ctx, {64, 22}), ~B"""
      ┌ Foglet ▸ General ───────────────────────── @alice | 05:43 PM ┐
      │▌ THREADS   CHAT (0)                                          │
      │⠋ Loading…                                                    │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      └ Q Back   C Compose   1 Threads*  2 Chat (0)   ↑/↓ Select ────┘
      """)
    end

    test "chat tab empty child surface matches a full buffer snapshot" do
      b = board(id: "b-snapshot", chat_enabled: true)
      ctx = context(b, size: {64, 22})
      state = BoardScreen.init(ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)

      assert_screen(render_buffer(state, ctx, {64, 22}), ~B"""
      ┌ Foglet ▸ General ───────────────────────── @alice | 05:43 PM ┐
      │THREADS   ▌ CHAT (1)                                          │
      │                                                              │
      │  No messages yet. Be the first to say hello.                 │
      │> ▎                                                           │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      │                                                              │
      └ ← Threads   Ctrl+B Show sidebar  Enter Send ─────────────────┘
      """)
    end

    test "renders a tab strip with THREADS + CHAT (#)" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)

      text = BoardScreen.render(state, ctx) |> flatten_text()

      assert text =~ "THREADS"
      assert text =~ "CHAT (0)"
      assert text =~ "▌"
    end

    test "threads tab renders one ThreadList board description below the tab strip" do
      b = board(chat_enabled: true, description: "Board-level context lives under the tabs.")
      ctx = context(b)
      state = BoardScreen.init(ctx)

      elements = BoardScreen.render(state, ctx) |> positioned_text_elements()
      tab = Enum.find(elements, &(&1.text == "THREADS"))

      description =
        Enum.find(elements, &(&1.text == "About: Board-level context lives under the tabs."))

      duplicate_descriptions =
        Enum.filter(elements, &String.contains?(&1.text, "Board-level context"))

      assert %{y: tab_y} = tab
      assert %{y: description_y} = description
      assert tab_y < description_y
      assert length(duplicate_descriptions) == 1
      assert row_text(elements, "About: Board-level context lives under the tabs.") =~ "About:"
      assert description.x + TextWidth.display_width(description.text) <= 80
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
        if PresenceTracker.chat_count(b.id) >= 2, do: :ok, else: :wait
      end)
      |> Stream.take_while(&(&1 == :wait))
      |> Stream.run()

      state = BoardScreen.init(ctx)
      {state, _effects} = BoardScreen.update(:on_route_enter, state, ctx)

      text = BoardScreen.render(state, ctx) |> flatten_text()
      assert text =~ "CHAT (3)"

      send(task.pid, :stop)
      Task.await(task)

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "chat tab keybar at 80x24 advertises left-arrow Threads and omits threads-only Q Back" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)
      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)

      assert state.current_tab == :chat

      keybar = BoardScreen.render(state, ctx) |> bottom_row_text(80, 24)

      assert keybar =~ "← Threads"
      assert keybar =~ "Enter Send"
      refute keybar =~ "Q Back"

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "chat transcript budget keeps composer and validation feedback inside viewport" do
      for {width, height} <- [{80, 24}, {64, 22}] do
        b = board(chat_enabled: true)
        ctx = context(b, size: {width, height})
        state = BoardScreen.init(ctx)
        {state, _} = BoardScreen.update(:on_route_enter, state, ctx)
        {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)

        state = %{
          state
          | chat_room: %{
              state.chat_room
              | messages: Enum.map(1..40, &chat_message(&1, b.id)),
                composer: "visible draft",
                last_error: :message_too_long
            }
        }

        elements = BoardScreen.render(state, ctx) |> positioned_text_elements(width, height)
        prompt = text_element(elements, "> ")
        error = text_element(elements, "  Message is too long (max 4000 characters).")
        bottom = text_element(elements, "└ ")

        assert %{y: prompt_y} = prompt
        assert %{y: error_y} = error
        assert %{y: bottom_y} = bottom
        assert prompt_y < bottom_y
        assert error_y < bottom_y
        assert prompt_y < height
        assert error_y < height

        :ok = PresenceTracker.untrack(b.id, "u1")
      end
    end

    test "threads tab keybar still advertises Q Back" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      assert state.current_tab == :threads

      keybar = BoardScreen.render(state, ctx) |> bottom_row_text(80, 24)

      assert keybar =~ "2 Chat (1)"
      assert keybar =~ "Q Back"

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

    test "digits in CONFIG add form are typed, not consumed as tab switches" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b, user: @sysop)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "4"}}, state, ctx)
      assert state.current_tab == :config

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "A"}}, state, ctx)

      state =
        Enum.reduce(String.graphemes("https://example.com/feed123.xml"), state, fn char, acc ->
          {next, []} = BoardScreen.update({:key, %{key: :char, char: char}}, acc, ctx)
          next
        end)

      assert state.current_tab == :config
      assert state.config.input == "https://example.com/feed123.xml"

      :ok = PresenceTracker.untrack(b.id, "u2")
    end

    test "NEWS Enter opens detail and Esc returns to list" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "3"}}, state, ctx)
      assert state.current_tab == :news

      items = [
        %{feed: %{title: "Source"}, title: "Item", summary: "Summary", url: "https://example.com"}
      ]

      state = %{state | news: %{state.news | status: :loaded, items: items}}
      {state, []} = BoardScreen.update({:key, %{key: :enter}}, state, ctx)
      assert state.news.view == :detail

      {state, []} = BoardScreen.update({:key, %{key: :escape}}, state, ctx)
      assert state.news.view == :list

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "NEWS task results unwrap BoardFeeds context return tuples before render" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "3"}}, state, ctx)
      assert state.current_tab == :news

      feeds = [
        %{title: "Example Feed", url: "https://example.com/feed.xml", last_success_at: nil}
      ]

      items = [
        %{
          feed: %{title: "Example Feed"},
          title: "Cached Item",
          summary: "Summary",
          url: "https://example.com/item"
        }
      ]

      {state, []} =
        BoardScreen.update(
          {:task_result, :load_board_news, {:ok, {{:ok, feeds}, {:ok, items}}}},
          state,
          ctx
        )

      assert state.news.feeds == feeds
      assert state.news.items == items

      rendered = flatten_text(BoardScreen.render(state, ctx))
      assert rendered =~ "Cached board news"
      assert rendered =~ "Example Feed"

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "CONFIG task results unwrap BoardFeeds context return tuples before render" do
      b = board(chat_enabled: true, news_enabled: true)
      ctx = context(b, user: @sysop)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "4"}}, state, ctx)
      assert state.current_tab == :config

      feeds = [
        %{
          id: "feed-1",
          title: "Example Feed",
          url: "https://example.com/feed.xml",
          cache_ttl_seconds: 3600
        }
      ]

      {state, []} =
        BoardScreen.update({:task_result, :load_board_feed_config, {:ok, feeds}}, state, ctx)

      assert state.config.feeds == feeds

      rendered = flatten_text(BoardScreen.render(state, ctx))
      assert rendered =~ "Feed CONFIG"
      assert rendered =~ "Example Feed"

      :ok = PresenceTracker.untrack(b.id, "u2")
    end

    test "right/left arrow aliases cycle between threads and chat" do
      for {right_key, left_key} <- [{:right, :left}, {:arrow_right, :arrow_left}] do
        b = board(chat_enabled: true)
        ctx = context(b)
        state = BoardScreen.init(ctx)
        {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

        {state, []} = BoardScreen.update({:key, %{key: right_key}}, state, ctx)
        assert state.current_tab == :chat

        {state, []} = BoardScreen.update({:key, %{key: left_key}}, state, ctx)
        assert state.current_tab == :threads

        :ok = PresenceTracker.untrack(b.id, "u1")
      end
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

  describe "off-tab chat flash" do
    test "same-board non-self chat received on THREADS starts and ticks CHAT flash without dropping transcript delivery" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} =
        BoardScreen.update(
          {:board_chat, :new_message, chat_message(1, b.id, "remote-1")},
          state,
          ctx
        )

      assert state.current_tab == :threads
      assert state.chat_alert? == true
      assert state.chat_flash_phase == :on
      assert Enum.map(state.chat_room.messages, & &1.id) == ["m1"]

      chat_label =
        state
        |> BoardScreen.render(ctx)
        |> positioned_text_elements()
        |> text_element("CHAT (1)")

      assert %{bg: bg, style: style} = chat_label
      assert is_binary(bg)
      assert style.bold == true

      {state, []} = BoardScreen.update(:board_chat_flash_tick, state, ctx)

      assert state.chat_alert? == true
      assert state.chat_flash_phase == :off

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "switching to CHAT clears an active off-tab flash" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} =
        BoardScreen.update(
          {:board_chat, :new_message, chat_message(1, b.id, "remote-1")},
          state,
          ctx
        )

      {state, []} = BoardScreen.update({:key, %{key: :char, char: "2"}}, state, ctx)

      assert state.current_tab == :chat
      assert state.chat_alert? == false
      assert state.chat_flash_phase == :off

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "leaving from THREADS clears an active off-tab flash before handoff to navigation" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} =
        BoardScreen.update(
          {:board_chat, :new_message, chat_message(1, b.id, "remote-1")},
          state,
          ctx
        )

      {state, effects} = BoardScreen.update({:key, %{key: :char, char: "Q"}}, state, ctx)

      assert state.chat_alert? == false
      assert state.chat_flash_phase == :off

      assert Enum.any?(effects, fn
               %Effect{type: :navigate, payload: %{screen: :board_list}} -> true
               _ -> false
             end)
    end

    test "self-sent and other-board chat messages do not start the off-tab flash" do
      b = board(chat_enabled: true)
      ctx = context(b)
      state = BoardScreen.init(ctx)
      {state, _} = BoardScreen.update(:on_route_enter, state, ctx)

      {state, []} =
        BoardScreen.update({:board_chat, :new_message, chat_message(1, b.id, "u1")}, state, ctx)

      refute state.chat_alert?

      {state, []} =
        BoardScreen.update(
          {:board_chat, :new_message, chat_message(2, "other-board", "remote-1")},
          state,
          ctx
        )

      refute state.chat_alert?
      assert Enum.map(state.chat_room.messages, & &1.id) == ["m1", "m2"]

      :ok = PresenceTracker.untrack(b.id, "u1")
    end

    test "chat-enabled board screen declares the flash tick interval at 64x22" do
      b = board(chat_enabled: true)
      ctx = context(b, size: {64, 22})
      state = BoardScreen.init(ctx)

      assert %{topics: topics, intervals: intervals} = BoardScreen.subscriptions(state, ctx)
      assert Topics.board_chat_topic(b.id) in topics
      assert {750, :board_chat_flash_tick} in intervals
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
        if PresenceTracker.chat_count(b.id) >= 1, do: :ok, else: :wait
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

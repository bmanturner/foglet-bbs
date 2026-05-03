defmodule Foglet.TUI.Screens.ChatRoomTest.FakeAccounts do
  @moduledoc false
  @users %{
    "u1" => %{id: "u1", handle: "alice"},
    "u2" => %{id: "u2", handle: "bob"},
    "u3" => %{id: "u3", handle: "carol"}
  }

  def get_user(id), do: Map.get(@users, id)
end

defmodule Foglet.TUI.Screens.ChatRoomTest do
  use ExUnit.Case, async: false

  alias Foglet.PubSub, as: Topics
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ChatRoom.State
  alias Foglet.TUI.Screens.ChatRoomTest.FakeAccounts

  @user %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user, status: :active}

  defp board(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, "b-" <> Ecto.UUID.generate()),
      name: Keyword.get(opts, :name, "General"),
      slug: "general",
      archived: false,
      postable_by: :members,
      chat_enabled: true,
      chat_storage_mode: Keyword.get(opts, :chat_storage_mode, :permanent)
    }
  end

  defp context(b, opts \\ []) do
    Context.new(
      current_user: @user,
      route: :thread_list,
      route_params: %{board: b, board_id: b.id},
      terminal_size: Keyword.get(opts, :size, {120, 40}),
      session_context: %{domain: %{accounts: FakeAccounts}}
    )
  end

  defp init_state(b, opts \\ []) do
    ctx = context(b, opts)
    {ChatRoom.init(ctx), ctx}
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

  defp render_chat_text(state, ctx, size) do
    state
    |> ChatRoom.render(ctx)
    |> AsciiRenderer.render(size)
  end

  defp first_line_containing(rendered, marker) do
    rendered
    |> String.split("\n")
    |> Enum.find(fn line -> String.contains?(line, marker) end)
  end

  defp column_of(line, marker) when is_binary(line) do
    case :binary.match(line, marker) do
      {byte_index, _length} ->
        line
        |> binary_part(0, byte_index)
        |> String.length()

      :nomatch ->
        nil
    end
  end

  defp sidebar_columns_for_body(body, size) do
    b = board()
    {state, ctx} = init_state(b, size: size)

    msg = %{id: "m1", board_id: b.id, user_id: "u2", body: body, inserted_at: nil}
    {state, []} = ChatRoom.update({:task_result, :load_chat_history, {:ok, [msg]}}, state, ctx)

    rendered = render_chat_text(state, ctx, size)
    sidebar_line = first_line_containing(rendered, "Online")

    {column_of(sidebar_line, "│"), column_of(sidebar_line, "Online"), sidebar_line}
  end

  defp append_message(state, ctx, msg) do
    {:board_chat, :new_message, msg}
    |> ChatRoom.update(state, ctx)
    |> elem(0)
  end

  describe "init/1" do
    test "captures board, board_id, and current user from context" do
      b = board()
      {state, _ctx} = init_state(b)

      assert %State{
               board: ^b,
               board_id: id,
               user_id: "u1",
               messages: [],
               composer: "",
               status: :idle,
               loaded?: false
             } = state

      assert id == b.id
    end
  end

  describe "render/2 — empty state" do
    test "renders the empty-transcript placeholder when no messages" do
      b = board()
      {state, ctx} = init_state(b)

      text = ChatRoom.render(state, ctx) |> flatten_text()

      assert text =~ "No messages yet"
      assert text =~ "Online"
    end

    test "renders ephemeral notice on ephemeral boards but not permanent" do
      eph = board(chat_storage_mode: :ephemeral)
      perm = board(chat_storage_mode: :permanent)

      {eph_state, eph_ctx} = init_state(eph)
      {perm_state, perm_ctx} = init_state(perm)

      eph_text = ChatRoom.render(eph_state, eph_ctx) |> flatten_text()
      perm_text = ChatRoom.render(perm_state, perm_ctx) |> flatten_text()

      assert eph_text =~ "Ephemeral chat"
      refute perm_text =~ "Ephemeral chat"
    end
  end

  describe "render/2 — with messages" do
    test "scroll keys move the transcript viewport without typing into the composer" do
      b = board()
      {state, ctx} = init_state(b, size: {80, 10})

      messages =
        for i <- 1..12 do
          %{id: "m#{i}", board_id: b.id, user_id: "u2", body: "message #{i}", inserted_at: nil}
        end

      {state, []} =
        ChatRoom.update({:task_result, :load_chat_history, {:ok, messages}}, state, ctx)

      assert state.autoscroll?
      assert state.scroll_offset == 0

      {state, []} = ChatRoom.update({:key, %{key: :page_up}}, state, ctx)

      refute state.autoscroll?
      assert state.scroll_offset > 0
      assert state.composer == ""

      text = ChatRoom.render(state, ctx) |> flatten_text()
      assert text =~ "message 1"
      refute text =~ "message 12"
    end

    test "new messages tail-follow only while transcript is at the tail" do
      b = board()
      {state, ctx} = init_state(b, size: {80, 10})

      messages =
        for i <- 1..8 do
          %{id: "m#{i}", board_id: b.id, user_id: "u2", body: "message #{i}", inserted_at: nil}
        end

      {state, []} =
        ChatRoom.update({:task_result, :load_chat_history, {:ok, messages}}, state, ctx)

      {state, []} =
        ChatRoom.update(
          {:board_chat, :new_message,
           %{id: "m9", board_id: b.id, user_id: "u2", body: "message 9", inserted_at: nil}},
          state,
          ctx
        )

      assert state.autoscroll?
      assert state.scroll_offset == 0
      assert ChatRoom.render(state, ctx) |> flatten_text() =~ "message 9"

      {state, []} = ChatRoom.update({:key, %{key: :up}}, state, ctx)
      scrolled_offset = state.scroll_offset
      refute state.autoscroll?

      {state, []} =
        ChatRoom.update(
          {:board_chat, :new_message,
           %{id: "m10", board_id: b.id, user_id: "u2", body: "message 10", inserted_at: nil}},
          state,
          ctx
        )

      assert state.scroll_offset == scrolled_offset
      refute ChatRoom.render(state, ctx) |> flatten_text() =~ "message 10"
    end

    test "renders one row per message with handle, body, and relative time" do
      b = board()
      {state, ctx} = init_state(b)

      msgs = [
        %{
          id: "m1",
          board_id: b.id,
          user_id: "u2",
          body: "hi from bob",
          inserted_at: DateTime.add(DateTime.utc_now(), -30, :second)
        },
        %{
          id: "m2",
          board_id: b.id,
          user_id: "u1",
          body: "hello bob",
          inserted_at: DateTime.add(DateTime.utc_now(), -5, :second)
        }
      ]

      {state, []} = ChatRoom.update({:task_result, :load_chat_history, {:ok, msgs}}, state, ctx)

      text = ChatRoom.render(state, ctx) |> flatten_text()

      assert text =~ "alice"
      assert text =~ "bob"
      assert text =~ "hi from bob"
      assert text =~ "hello bob"
    end
  end

  describe "responsive sidebar" do
    test "wide width (>= 80) shows sidebar by default" do
      b = board()
      {state, ctx} = init_state(b, size: {120, 40})

      assert ChatRoom.sidebar_visible?(state, 120) == true

      text = ChatRoom.render(state, ctx) |> flatten_text()
      assert text =~ "Online"
    end

    test "narrow width (60–79) collapses sidebar by default" do
      b = board()
      {state, ctx} = init_state(b, size: {70, 24})

      assert ChatRoom.sidebar_visible?(state, 70) == false

      text = ChatRoom.render(state, ctx) |> flatten_text()
      refute text =~ "Online"
    end

    test "very narrow width (< 60) suppresses sidebar even after toggle" do
      b = board()
      {state, _ctx} = init_state(b, size: {40, 20})

      {state, []} =
        ChatRoom.update(
          {:key, %{key: :char, char: "b", ctrl: true}},
          state,
          context(b, size: {40, 20})
        )

      assert ChatRoom.sidebar_visible?(state, 40) == false
    end

    test "Ctrl+B toggles sidebar visibility at narrow widths" do
      b = board()
      {state, ctx} = init_state(b, size: {70, 24})

      assert ChatRoom.sidebar_visible?(state, 70) == false

      {state, []} = ChatRoom.update({:key, %{key: :char, char: "b", ctrl: true}}, state, ctx)

      assert ChatRoom.sidebar_visible?(state, 70) == true

      text = ChatRoom.render(state, ctx) |> flatten_text()
      assert text =~ "Online"

      {state, []} = ChatRoom.update({:key, %{key: :char, char: "b", ctrl: true}}, state, ctx)
      assert ChatRoom.sidebar_visible?(state, 70) == false
    end

    test "Ctrl+B at wide width hides the sidebar" do
      b = board()
      {state, ctx} = init_state(b, size: {120, 40})

      assert ChatRoom.sidebar_visible?(state, 120) == true

      {state, []} = ChatRoom.update({:key, %{key: :char, char: "b", ctrl: true}}, state, ctx)

      assert ChatRoom.sidebar_visible?(state, 120) == false
    end

    test "keybar advertises sidebar toggle only when meaningful" do
      b = board()
      {state, ctx_wide} = init_state(b, size: {120, 40})

      [chat_group] = ChatRoom.keybar_groups(state, ctx_wide)
      labels = Enum.map(chat_group.commands, & &1.label)
      assert "Hide sidebar" in labels or "Show sidebar" in labels

      ctx_narrow = context(b, size: {40, 20})
      [chat_group] = ChatRoom.keybar_groups(state, ctx_narrow)
      labels = Enum.map(chat_group.commands, & &1.label)
      refute "Hide sidebar" in labels
      refute "Show sidebar" in labels
    end

    test "rendered sidebar column is stable for short, long, and wrapped messages" do
      short = "short"
      long_unbroken = String.duplicate("x", 120)
      wrapped = String.duplicate("word ", 40)

      for size <- [{80, 24}, {120, 30}] do
        {short_separator, short_online, _short_line} = sidebar_columns_for_body(short, size)
        {long_separator, long_online, long_line} = sidebar_columns_for_body(long_unbroken, size)

        {wrapped_separator, wrapped_online, wrapped_line} =
          sidebar_columns_for_body(wrapped, size)

        assert short_separator == long_separator
        assert short_separator == wrapped_separator
        assert short_online == long_online
        assert short_online == wrapped_online
        refute long_line =~ String.duplicate("x", 120)
        refute wrapped_line =~ wrapped
      end
    end

    test "rendered sidebar column remains stable as new messages arrive" do
      b = board()
      size = {80, 24}
      {state, ctx} = init_state(b, size: size)

      first = %{id: "m1", board_id: b.id, user_id: "u2", body: "short", inserted_at: nil}

      {state, []} =
        ChatRoom.update({:task_result, :load_chat_history, {:ok, [first]}}, state, ctx)

      before_line = state |> render_chat_text(ctx, size) |> first_line_containing("Online")
      before_separator = column_of(before_line, "│")
      before_online = column_of(before_line, "Online")

      state =
        append_message(state, ctx, %{
          id: "m2",
          board_id: b.id,
          user_id: "u2",
          body: String.duplicate("appended", 30),
          inserted_at: nil
        })

      after_line = state |> render_chat_text(ctx, size) |> first_line_containing("Online")

      assert column_of(after_line, "│") == before_separator
      assert column_of(after_line, "Online") == before_online
    end

    test "very narrow rendered layout suppresses sidebar instead of clipping it" do
      b = board()
      size = {50, 20}
      {state, ctx} = init_state(b, size: size)

      msg = %{
        id: "m1",
        board_id: b.id,
        user_id: "u2",
        body: String.duplicate("x", 120),
        inserted_at: nil
      }

      {state, []} = ChatRoom.update({:task_result, :load_chat_history, {:ok, [msg]}}, state, ctx)

      rendered = render_chat_text(state, ctx, size)

      assert first_line_containing(rendered, "Online") == nil
      assert first_line_containing(rendered, "│") == nil
    end
  end

  describe "composer" do
    test "printable chars accumulate in the composer" do
      b = board()
      {state, ctx} = init_state(b)

      {state, []} = ChatRoom.update({:key, %{key: :char, char: "h"}}, state, ctx)
      {state, []} = ChatRoom.update({:key, %{key: :char, char: "i"}}, state, ctx)

      assert state.composer == "hi"
    end

    test "ctrl-modified chars do not leak into the composer" do
      b = board()
      {state, ctx} = init_state(b)

      {state, []} =
        ChatRoom.update({:key, %{key: :char, char: "x", ctrl: true}}, state, ctx)

      assert state.composer == ""
    end

    test "backspace removes the last character" do
      b = board()
      {state, ctx} = init_state(b)

      state = %{state | composer: "abc"}
      {state, []} = ChatRoom.update({:key, %{key: :backspace}}, state, ctx)

      assert state.composer == "ab"
    end

    test "Enter on whitespace-only composer is a no-op (no effect emitted)" do
      b = board()
      {state, ctx} = init_state(b)

      state = %{state | composer: "   "}
      {state, effects} = ChatRoom.update({:key, %{key: :enter}}, state, ctx)

      assert state.composer == ""
      assert effects == []
    end

    test "Enter with text emits a :send_chat task and clears composer" do
      b = board()
      {state, ctx} = init_state(b)
      state = %{state | composer: "hello"}

      {state, [%Effect{type: :task, payload: %{op: :send_chat, fun: fun}}]} =
        ChatRoom.update({:key, %{key: :enter}}, state, ctx)

      assert state.composer == ""
      assert state.status == :sending

      assert is_function(fun, 0)
    end

    # FOG-277 regression — task results were dropped at routing because
    # ChatRoom dispatched with screen_key `:chat_room`, which is not a
    # known top-level screen. The task's screen_key must be the active
    # route so BoardScreen forwards `{:task_result, ...}` to ChatRoom.
    test "send_chat task uses the active route key, not :chat_room" do
      b = board()
      {state, ctx} = init_state(b)
      state = %{state | composer: "hello"}

      {_state, [%Effect{type: :task, payload: %{op: :send_chat, screen_key: key}}]} =
        ChatRoom.update({:key, %{key: :enter}}, state, ctx)

      assert key == :thread_list
    end
  end

  describe "live message ingest" do
    test "{:board_chat, :new_message, _} appends to the transcript" do
      b = board()
      {state, ctx} = init_state(b)

      msg = %{
        id: "m9",
        board_id: b.id,
        user_id: "u3",
        body: "drive-by",
        inserted_at: DateTime.utc_now()
      }

      {state, []} = ChatRoom.update({:board_chat, :new_message, msg}, state, ctx)

      assert [^msg] = state.messages
      text = ChatRoom.render(state, ctx) |> flatten_text()
      assert text =~ "drive-by"
      assert text =~ "carol"
    end
  end

  describe "presence sidebar" do
    test "sidebar lists online users with (you) label for current user" do
      b = board()
      ctx = context(b)
      :ok = PresenceTracker.track(b.id, "u1", :chat)

      task =
        Task.async(fn ->
          :ok = PresenceTracker.track(b.id, "u2", :chat)

          receive do
            :stop -> :ok
          end
        end)

      Stream.repeatedly(fn ->
        if PresenceTracker.count(b.id) >= 2, do: :ok, else: :wait
      end)
      |> Stream.take_while(&(&1 == :wait))
      |> Stream.run()

      state = ChatRoom.init(ctx)
      {state, _} = ChatRoom.load_effects(state, ctx)

      text = ChatRoom.render(state, ctx) |> flatten_text()

      assert text =~ "alice (you)"
      assert text =~ "bob"

      send(task.pid, :stop)
      Task.await(task)
      :ok = PresenceTracker.untrack(b.id, "u1")
    end
  end

  describe "subscriptions/2" do
    test "subscribes to chat + presence topics for the board" do
      b = board()
      {state, ctx} = init_state(b)

      topics = ChatRoom.subscriptions(state, ctx)

      assert Topics.board_chat_topic(b.id) in topics
      assert Topics.board_screen_topic(b.id) in topics
    end
  end

  describe "load_effects/2" do
    test "emits a :load_chat_history task and marks status :loading" do
      b = board()
      {state, ctx} = init_state(b)

      {state, [%Effect{type: :task, payload: %{op: :load_chat_history}}]} =
        ChatRoom.load_effects(state, ctx)

      assert state.status == :loading
    end

    # FOG-277 regression — see send_chat task screen_key test above.
    test "load_chat_history task uses the active route key, not :chat_room" do
      b = board()
      {state, ctx} = init_state(b)

      {_state, [%Effect{type: :task, payload: %{op: :load_chat_history, screen_key: key}}]} =
        ChatRoom.load_effects(state, ctx)

      assert key == :thread_list
    end

    # FOG-277 regression — the route param is a plain map (BoardList
    # produces it via `board_identity/1`); BoardChat.post / .recent
    # function-clause on `%Board{}`. The closure must coerce so the
    # task does not crash before reaching Repo / RoomServer.
    test "load_chat_history closure runs against a plain-map board (no FunctionClauseError)" do
      b = board()
      {state, ctx} = init_state(b)

      {_state, [%Effect{type: :task, payload: %{fun: fun}}]} =
        ChatRoom.load_effects(state, ctx)

      try do
        fun.()
      rescue
        FunctionClauseError ->
          flunk(
            "load_chat_history task raised FunctionClauseError — board was not coerced to %Board{}"
          )

        _ ->
          # Backend errors (DB unavailable, etc.) are acceptable for this
          # screen-shape regression; we only guard against the upstream
          # FunctionClauseError that drops results before they can be
          # routed back to the reducer.
          :ok
      catch
        _, _ -> :ok
      end
    end

    test "is idempotent after a successful load" do
      b = board()
      {state, ctx} = init_state(b)

      {state, [_]} = ChatRoom.load_effects(state, ctx)
      {state, []} = ChatRoom.update({:task_result, :load_chat_history, {:ok, []}}, state, ctx)
      {state, effects} = ChatRoom.load_effects(state, ctx)

      assert effects == []
      assert state.loaded? == true
    end
  end
end

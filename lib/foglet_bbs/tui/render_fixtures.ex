defmodule Foglet.TUI.RenderFixtures do
  @moduledoc """
  Synthetic, in-memory state builders for `Foglet.TUI.AsciiRenderer` and
  `mix foglet.tui.render`.

  Each `state_for/2` clause returns a `%Foglet.TUI.App{}` struct populated
  with just enough data for the requested screen to render meaningful
  content — no Repo, no SSH, no PubSub. The resulting state can be passed
  directly to `Foglet.TUI.App.view/1`, which routes through `SizeGate` and
  the chrome to produce a full-screen view tree.

  This is **not** a test fixture for end-to-end behaviour — it produces a
  stable visual snapshot of each screen for inspection. Don't lean on the
  shapes here for assertions about real screen behaviour; use the actual
  domain types from a `DataCase` test for that.
  """

  alias Foglet.Accounts.User
  alias Foglet.TUI.App
  alias Foglet.TUI.SessionContext
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.BoardTree

  alias Foglet.TUI.Screens.{
    Account,
    BoardList,
    Login,
    MainMenu,
    Moderation,
    NewThread,
    PostComposer,
    PostReader,
    Register,
    Sysop,
    ThreadList,
    Verify
  }

  alias Foglet.Threads.ThreadEntry

  @screens ~w(
    login register verify main_menu board_list thread_list
    post_reader post_composer new_thread account moderation sysop
  )a

  @typedoc "Screen identifier accepted by `state_for/2`."
  @type screen ::
          :login
          | :register
          | :verify
          | :main_menu
          | :board_list
          | :thread_list
          | :post_reader
          | :post_composer
          | :new_thread
          | :account
          | :moderation
          | :sysop

  @doc "All screens that can be rendered."
  @spec screens() :: [screen()]
  @dialyzer {:nowarn_function, screens: 0}
  def screens, do: @screens

  @doc """
  Build an `%App{}` state for `screen` at `terminal_size`.

  Unknown screens raise `ArgumentError`.
  """
  @spec state_for(screen() | atom(), {pos_integer(), pos_integer()}) :: App.t()
  def state_for(screen, terminal_size) when screen in @screens do
    base = base_state(screen, terminal_size)
    populate(screen, base, terminal_size)
  end

  def state_for(screen, _size) do
    raise ArgumentError,
          "unknown screen: #{inspect(screen)}. Known: #{inspect(@screens)}"
  end

  # --- base -----------------------------------------------------------------

  defp base_state(screen, terminal_size) do
    user = if screen in [:login, :register, :verify], do: nil, else: synthetic_user()

    %App{
      current_screen: screen,
      current_user: user,
      session_context: synthetic_session_context(user),
      terminal_size: terminal_size,
      screen_state: %{}
    }
  end

  defp synthetic_user do
    %User{
      id: "00000000-0000-0000-0000-000000000001",
      handle: "alice",
      email: "alice@example.com",
      role: :sysop,
      status: :active,
      timezone: "America/Chicago",
      theme: "gray",
      preferences: %{"time_format" => "24h"},
      post_count: 42,
      tagline: "Just here for the dot art.",
      location: "Chicago, IL",
      confirmed_at: ~U[2026-01-01 00:00:00.000000Z],
      inserted_at: ~U[2026-01-01 00:00:00.000000Z],
      updated_at: ~U[2026-04-01 00:00:00.000000Z]
    }
  end

  defp synthetic_session_context(user) do
    %SessionContext{
      user: user,
      user_id: user && user.id,
      session_pid: nil,
      pubkey_authenticated: not is_nil(user),
      registration_mode: "open",
      max_post_length: 65_535,
      timezone: (user && user.timezone) || "Etc/UTC",
      time_format: "24h",
      theme_id: "gray",
      theme: Theme.default()
    }
  end

  defp synthetic_oneliners do
    [
      %{
        id: "ol-1",
        body: "Welcome to Foglet BBS.",
        author_handle: "sysop",
        inserted_at: ~U[2026-04-27 12:00:00Z]
      },
      %{
        id: "ol-2",
        body: "New thread in /general — say hi!",
        author_handle: "alice",
        inserted_at: ~U[2026-04-27 12:30:00Z]
      }
    ]
  end

  # --- per-screen population -----------------------------------------------

  defp populate(:login, state, _size) do
    App.put_screen_state(state, :login, Login.init_screen_state([]))
  end

  defp populate(:register, state, _size) do
    App.put_screen_state(state, :register, Register.init_screen_state([]))
  end

  defp populate(:verify, state, _size) do
    App.put_screen_state(state, :verify, Verify.init_screen_state([]))
  end

  defp populate(:main_menu, state, _size) do
    local_state =
      state
      |> App.build_context()
      |> MainMenu.init()
      |> MainMenu.State.from_entries(synthetic_oneliners())

    App.put_screen_state(state, :main_menu, local_state)
  end

  defp populate(:board_list, state, _size) do
    directory = synthetic_directory()
    board_tree = BoardTree.init(directory: directory, id: "board-directory")

    App.put_screen_state(
      state,
      :board_list,
      BoardList.State.new(
        directory: directory,
        board_tree: board_tree,
        status: :loaded,
        feedback: nil
      )
    )
  end

  defp populate(:thread_list, state, _size) do
    board = hd(synthetic_boards())
    threads = synthetic_threads(board)

    %{state | route_params: %{board: board, board_id: board.id}}
    |> App.put_screen_state(
      :thread_list,
      ThreadList.State.new(
        board: board,
        board_id: board.id,
        threads: threads,
        selected_index: 0,
        status: :loaded
      )
    )
  end

  defp populate(:post_reader, state, _size) do
    board = hd(synthetic_boards())
    threads = synthetic_threads(board)
    thread = hd(threads)
    posts = synthetic_posts(thread)

    post_reader_state =
      PostReader.State.new(
        board: board,
        board_id: board.id,
        thread: thread,
        thread_id: thread.id,
        posts: posts,
        status: :loaded,
        selected_post_index: 0
      )

    %{
      state
      | route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id}
    }
    |> App.put_screen_state(:post_reader, post_reader_state)
  end

  defp populate(:post_composer, state, {w, _h}) do
    board = hd(synthetic_boards())
    [thread | _] = synthetic_threads(board)
    [reply_to | _] = synthetic_posts(thread)

    post_composer_state =
      PostComposer.State.new(
        board: board,
        board_id: board.id,
        thread: thread,
        thread_id: thread.id,
        reply_to: reply_to,
        origin: :post_reader,
        width: max(w - 4, 20),
        height: 10
      )

    %{
      state
      | route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id}
    }
    |> App.put_screen_state(:post_composer, post_composer_state)
  end

  defp populate(:new_thread, state, {w, _h}) do
    [board | _] = synthetic_boards()

    ss =
      NewThread.State.new(
        step: :compose,
        board: board,
        boards: [board],
        load_status: :loaded,
        origin: :thread_list,
        width: w
      )

    %{state | route_params: %{board: board, board_id: board.id}}
    |> App.put_screen_state(:new_thread, ss)
  end

  defp populate(:account, state, _size) do
    App.put_screen_state(state, :account, Account.init_screen_state([]))
  end

  defp populate(:moderation, state, _size) do
    App.put_screen_state(state, :moderation, Moderation.init_screen_state([]))
  end

  defp populate(:sysop, state, _size) do
    App.put_screen_state(state, :sysop, Sysop.init_screen_state([]))
  end

  # --- synthetic data shapes -----------------------------------------------

  # Directory shape used by `Foglet.Boards.board_directory_for/1` and
  # consumed by the BoardList screen / BoardTree widget.
  defp synthetic_directory do
    boards = synthetic_boards()
    category = %{id: "c-1", name: "main", display_order: 1}

    [
      %{
        category: category,
        boards:
          Enum.map(boards, fn board ->
            %{
              board: board,
              subscribed?: true,
              required_subscription?: false,
              unread_count: board.unread_count,
              last_post_at: ~U[2026-04-27 12:30:00Z]
            }
          end)
      }
    ]
  end

  defp synthetic_boards do
    [
      %{
        id: "b-1",
        name: "general",
        description: "Anything goes",
        display_order: 1,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 12,
        unread_count: 3
      },
      %{
        id: "b-2",
        name: "tech",
        description: "Computers, code, and curiosities",
        display_order: 2,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 7,
        unread_count: 0
      },
      %{
        id: "b-3",
        name: "lounge",
        description: "Off-topic chat",
        display_order: 3,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 4,
        unread_count: 1
      }
    ]
  end

  defp synthetic_threads(board) do
    [
      %ThreadEntry{
        id: "t-1",
        title: "Welcome — read me first",
        board_id: board.id,
        sticky: true,
        locked: false,
        post_count: 3,
        last_post_at: ~U[2026-04-27 11:00:00Z],
        inserted_at: ~U[2026-04-01 09:00:00Z],
        created_by_id: "u-sysop",
        has_unread: false,
        created_by: %{handle: "sysop"}
      },
      %ThreadEntry{
        id: "t-2",
        title: "What is everyone working on?",
        board_id: board.id,
        sticky: false,
        locked: false,
        post_count: 8,
        last_post_at: ~U[2026-04-27 12:30:00Z],
        inserted_at: ~U[2026-04-20 10:00:00Z],
        created_by_id: "u-alice",
        has_unread: true,
        created_by: %{handle: "alice"}
      },
      %ThreadEntry{
        id: "t-3",
        title: "Thread renderer ASCII tool",
        board_id: board.id,
        sticky: false,
        locked: false,
        post_count: 2,
        last_post_at: ~U[2026-04-27 13:00:00Z],
        inserted_at: ~U[2026-04-27 12:45:00Z],
        created_by_id: "u-alice",
        has_unread: true,
        created_by: %{handle: "alice"}
      }
    ]
  end

  defp synthetic_posts(thread) do
    [
      %{
        id: "p-1",
        thread_id: thread.id,
        message_number: 1,
        body: "Welcome — please read the rules in /general.",
        body_rendered: nil,
        upvote_count: 4,
        edit_count: 0,
        deleted_at: nil,
        inserted_at: ~U[2026-04-01 09:00:00Z],
        user: %{handle: "sysop"}
      },
      %{
        id: "p-2",
        thread_id: thread.id,
        message_number: 2,
        body: "Glad to be here. Foglet looks great so far.",
        body_rendered: nil,
        upvote_count: 1,
        edit_count: 0,
        deleted_at: nil,
        inserted_at: ~U[2026-04-02 10:00:00Z],
        user: %{handle: "alice"}
      }
    ]
  end
end

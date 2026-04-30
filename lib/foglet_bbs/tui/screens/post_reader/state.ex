defmodule Foglet.TUI.Screens.PostReader.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.PostReader`.

  This is the screen-owned boundary for routed board/thread identity, loaded
  posts, selected index, viewport/cache state, pending read data, load status,
  and read-pointer flush results.

  The app stores this struct at `state.screen_state[:post_reader]`.
  """

  alias Foglet.TUI.Context
  alias Raxol.UI.Components.Display.Viewport

  @type status :: :loading | :loaded | :empty | {:error, term()}

  @type t :: %__MODULE__{
          board: map() | nil,
          board_id: String.t() | nil,
          thread: map() | nil,
          thread_id: String.t() | nil,
          posts: [map()] | nil,
          status: status(),
          pending_read_positions: map(),
          selected_post_index: non_neg_integer(),
          window_first_message_number: pos_integer() | nil,
          window_last_message_number: pos_integer() | nil,
          window_has_previous?: boolean(),
          window_has_next?: boolean(),
          reader_window_limit: pos_integer(),
          viewport: map(),
          render_cache: map(),
          last_op: atom() | nil,
          last_error: term() | nil,
          load_intent: term()
        }

  defstruct board: nil,
            board_id: nil,
            thread: nil,
            thread_id: nil,
            posts: nil,
            status: :loading,
            pending_read_positions: %{},
            selected_post_index: 0,
            window_first_message_number: nil,
            window_last_message_number: nil,
            window_has_previous?: false,
            window_has_next?: false,
            reader_window_limit: 50,
            viewport: nil,
            render_cache: %{},
            last_op: nil,
            last_error: nil,
            load_intent: nil

  @doc """
  Builds a fresh PostReader screen state struct.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      board: Keyword.get(opts, :board),
      board_id: Keyword.get(opts, :board_id),
      thread: Keyword.get(opts, :thread),
      thread_id: Keyword.get(opts, :thread_id),
      posts: Keyword.get(opts, :posts),
      status: Keyword.get(opts, :status, :loading),
      pending_read_positions: Keyword.get(opts, :pending_read_positions, %{}),
      selected_post_index: Keyword.get(opts, :selected_post_index, 0),
      window_first_message_number: Keyword.get(opts, :window_first_message_number),
      window_last_message_number: Keyword.get(opts, :window_last_message_number),
      window_has_previous?: Keyword.get(opts, :window_has_previous?, false),
      window_has_next?: Keyword.get(opts, :window_has_next?, false),
      reader_window_limit: Keyword.get(opts, :reader_window_limit, 50),
      viewport: Keyword.get(opts, :viewport) || default_viewport(),
      render_cache: Keyword.get(opts, :render_cache) || %{},
      last_op: Keyword.get(opts, :last_op),
      last_error: Keyword.get(opts, :last_error),
      load_intent: Keyword.get(opts, :load_intent)
    }
  end

  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    params = context.route_params || %{}
    board = Map.get(params, :board) || Map.get(params, "board")
    thread = Map.get(params, :thread) || Map.get(params, "thread")

    new(
      board: board,
      board_id:
        Map.get(params, :board_id) || Map.get(params, "board_id") || board_id_from_board(board),
      thread: thread,
      thread_id:
        Map.get(params, :thread_id) || Map.get(params, "thread_id") ||
          thread_id_from_thread(thread),
      load_intent: Map.get(params, :load_intent) || Map.get(params, "load_intent")
    )
  end

  defp default_viewport do
    {:ok, viewport} =
      Viewport.init(%{
        id: "post_reader_vp",
        children: [],
        visible_height: 10,
        scroll_top: 0,
        show_scrollbar: false
      })

    viewport
  end

  defp board_id_from_board(%{} = board), do: Map.get(board, :id) || Map.get(board, "id")
  defp board_id_from_board(_board), do: nil

  defp thread_id_from_thread(%{} = thread), do: Map.get(thread, :id) || Map.get(thread, "id")
  defp thread_id_from_thread(_thread), do: nil
end

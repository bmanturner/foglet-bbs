defmodule Foglet.TUI.Screens.NewThread.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.NewThread`.

  This is the screen-owned boundary for board picker state, board-load
  results, compose drafts, validation, submit status/result, and cancel origin.

  The app stores this struct at `state.screen_state[:new_thread]`.
  Nested stateful widget state is held as first-class struct fields.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Raxol.UI.Components.Input.MultiLineInput

  @default_max_thread_title_length 60

  @type load_status :: :idle | :loading | :loaded | :empty | {:error, term()}
  @type submission_status :: :idle | :submitting | {:error, term()} | :submitted

  @type t :: %__MODULE__{
          step: :board | :compose,
          boards: list(map()) | nil,
          active_board_count: non_neg_integer() | nil,
          selected_board_index: non_neg_integer(),
          board: map() | nil,
          title_input_state: TextInput.t(),
          body_input_state: map(),
          focused: :title | :body,
          mode: :edit | :preview,
          error: String.t() | nil,
          origin: atom(),
          load_status: load_status(),
          submission_status: submission_status(),
          submit_result: term() | nil
        }

  defstruct step: :board,
            boards: nil,
            active_board_count: nil,
            selected_board_index: 0,
            board: nil,
            title_input_state: nil,
            body_input_state: nil,
            focused: :title,
            mode: :edit,
            error: nil,
            origin: :main_menu,
            load_status: :idle,
            submission_status: :idle,
            submit_result: nil

  @doc """
  Builds a fresh NewThread screen state struct.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 10)
    max_title_length = Keyword.get(opts, :max_title_length, @default_max_thread_title_length)

    {:ok, body_input_state} =
      MultiLineInput.init(%{
        value: Keyword.get(opts, :body_value, ""),
        placeholder: "Write your opening post…",
        width: max(width - 4, 20),
        height: height,
        wrap: :none,
        focused: false
      })

    %__MODULE__{
      step: Keyword.get(opts, :step, :board),
      boards: Keyword.get(opts, :boards, nil),
      active_board_count: Keyword.get(opts, :active_board_count, nil),
      selected_board_index: Keyword.get(opts, :selected_board_index, 0),
      board: Keyword.get(opts, :board, nil),
      title_input_state:
        Keyword.get(opts, :title_input_state) ||
          TextInput.init(
            value: Keyword.get(opts, :title_value, ""),
            max_length: max_title_length
          ),
      body_input_state: Keyword.get(opts, :body_input_state) || body_input_state,
      focused: Keyword.get(opts, :focused, :title),
      mode: Keyword.get(opts, :mode, :edit),
      error: Keyword.get(opts, :error, nil),
      origin: Keyword.get(opts, :origin, :main_menu),
      load_status: Keyword.get(opts, :load_status, :idle),
      submission_status: Keyword.get(opts, :submission_status, :idle),
      submit_result: Keyword.get(opts, :submit_result, nil)
    }
  end

  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    params = context.route_params || %{}
    origin = Map.get(params, :origin) || Map.get(params, "origin") || :main_menu
    board = Map.get(params, :board) || Map.get(params, "board")

    board_id =
      Map.get(params, :board_id) || Map.get(params, "board_id") || board_id_from_board(board)

    if board do
      board = normalize_board_id(board, board_id)

      new(
        step: :compose,
        board: board,
        boards: [board],
        selected_board_index: 0,
        origin: origin,
        load_status: :loaded
      )
    else
      new(step: :board, boards: nil, origin: origin, load_status: :idle)
    end
  end

  defp board_id_from_board(%{} = board), do: Map.get(board, :id) || Map.get(board, "id")
  defp board_id_from_board(_board), do: nil

  defp normalize_board_id(%{} = board, board_id) when not is_nil(board_id) do
    case board_id_from_board(board) do
      nil -> Map.put(board, :id, board_id)
      _id -> board
    end
  end

  defp normalize_board_id(board, _board_id), do: board
end

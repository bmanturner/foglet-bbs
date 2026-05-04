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
  alias Foglet.TUI.Widgets.List.SmartList
  alias Raxol.UI.Components.Input.MultiLineInput

  @default_max_post_length 8192
  @default_max_thread_title_length 60
  @board_picker_page_size 12

  @type load_status :: :idle | :loading | :loaded | :empty | {:error, term()}
  @type submission_status :: :idle | :submitting | {:error, term()} | :submitted

  @type t :: %__MODULE__{
          step: :board | :compose,
          boards: list(map()) | nil,
          active_board_count: non_neg_integer() | nil,
          selected_board_index: non_neg_integer(),
          board_picker: SmartList.t() | nil,
          board: map() | nil,
          title_input_state: TextInput.t(),
          body_input_state: map(),
          focused: :title | :body,
          mode: :edit | :preview,
          error: String.t() | nil,
          max_post_length: pos_integer(),
          max_thread_title_length: pos_integer(),
          origin: atom(),
          load_status: load_status(),
          submission_status: submission_status(),
          submit_result: term() | nil
        }

  defstruct step: :board,
            boards: nil,
            active_board_count: nil,
            selected_board_index: 0,
            board_picker: nil,
            board: nil,
            title_input_state: nil,
            body_input_state: nil,
            focused: :title,
            mode: :edit,
            error: nil,
            max_post_length: @default_max_post_length,
            max_thread_title_length: @default_max_thread_title_length,
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

    max_post_length =
      positive_integer(Keyword.get(opts, :max_post_length), @default_max_post_length)

    max_title_length =
      positive_integer(Keyword.get(opts, :max_title_length), @default_max_thread_title_length)

    {:ok, body_input_state} =
      MultiLineInput.init(%{
        value: Keyword.get(opts, :body_value, ""),
        placeholder: "Write your opening post…",
        width: max(width - 4, 20),
        height: height,
        wrap: :none,
        focused: false
      })

    boards_opt = Keyword.get(opts, :boards, nil)

    %__MODULE__{
      step: Keyword.get(opts, :step, :board),
      boards: boards_opt,
      active_board_count: Keyword.get(opts, :active_board_count, nil),
      selected_board_index: Keyword.get(opts, :selected_board_index, 0),
      board_picker: Keyword.get(opts, :board_picker) || build_board_picker(boards_opt),
      board: Keyword.get(opts, :board, nil),
      title_input_state:
        Keyword.get(opts, :title_input_state) ||
          TextInput.init(
            value: Keyword.get(opts, :title_value, ""),
            max_length: max_title_length,
            placeholder: "Thread title"
          ),
      body_input_state: Keyword.get(opts, :body_input_state) || body_input_state,
      focused: Keyword.get(opts, :focused, :title),
      mode: Keyword.get(opts, :mode, :edit),
      error: Keyword.get(opts, :error, nil),
      max_post_length: max_post_length,
      max_thread_title_length: max_title_length,
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
    opts = context_options(context, origin)

    case routed_board(params) do
      nil ->
        new(Keyword.merge(opts, step: :board, boards: nil, load_status: :idle))

      board ->
        new(
          Keyword.merge(opts,
            step: :compose,
            board: board,
            boards: [board],
            selected_board_index: 0,
            load_status: :loaded
          )
        )
    end
  end

  @doc """
  Builds the searchable SmartList picker over a list of (already-loaded,
  category-annotated) boards. Returns `nil` for nil/empty inputs so the
  render layer can fall back to load/empty messaging.
  """
  @spec build_board_picker(list(map()) | nil) :: SmartList.t() | nil
  def build_board_picker(nil), do: nil
  def build_board_picker([]), do: nil

  def build_board_picker(boards) when is_list(boards) do
    options = Enum.map(boards, fn board -> {board_picker_label(board), board} end)

    picker =
      SmartList.init(options: options, enable_search: true, page_size: @board_picker_page_size)

    %{picker | raxol_state: Map.put(picker.raxol_state, :is_search_focused, true)}
  end

  defp context_options(%Context{} = context, origin) do
    {w, _h} = context.terminal_size || {80, 24}
    session_context = context.session_context || %{}

    [
      width: w,
      max_post_length:
        positive_integer(Map.get(session_context, :max_post_length), @default_max_post_length),
      max_title_length:
        positive_integer(
          Map.get(session_context, :max_thread_title_length),
          @default_max_thread_title_length
        ),
      origin: origin
    ]
  end

  defp routed_board(params) do
    board = Map.get(params, :board) || Map.get(params, "board")

    board_id =
      Map.get(params, :board_id) || Map.get(params, "board_id") || board_id_from_board(board)

    if board, do: normalize_board_id(board, board_id)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp board_id_from_board(%{} = board), do: Map.get(board, :id) || Map.get(board, "id")
  defp board_id_from_board(_board), do: nil

  defp normalize_board_id(%{} = board, board_id) when not is_nil(board_id) do
    case board_id_from_board(board) do
      nil -> Map.put(board, :id, board_id)
      _id -> board
    end
  end

  defp normalize_board_id(board, _board_id), do: board

  defp board_picker_label(board) do
    name = board_field(board, :name) || "Unnamed"
    category = board_field(board, :category_name)
    description = board_field(board, :description)

    [
      category && "#{category} / ",
      name,
      description && " — #{description}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> IO.iodata_to_binary()
  end

  defp board_field(board, key) when is_map(board) do
    Map.get(board, key) || Map.get(board, Atom.to_string(key))
  end

  defp board_field(_board, _key), do: nil
end

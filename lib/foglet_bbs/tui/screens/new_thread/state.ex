defmodule Foglet.TUI.Screens.NewThread.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.NewThread`.

  The app stores this struct at `state.screen_state[:new_thread]`.
  Nested stateful widget state is held as first-class struct fields.
  """

  alias Foglet.TUI.Widgets.Input.TextInput
  alias Raxol.UI.Components.Input.MultiLineInput

  @default_max_thread_title_length 60

  @type t :: %__MODULE__{
          step: :board | :compose,
          boards: list(map()) | nil,
          selected_board_index: non_neg_integer(),
          board: map() | nil,
          title_input_state: TextInput.t(),
          body_input_state: map(),
          focused: :title | :body,
          mode: :edit | :preview,
          error: String.t() | nil,
          origin: atom()
        }

  defstruct step: :board,
            boards: nil,
            selected_board_index: 0,
            board: nil,
            title_input_state: nil,
            body_input_state: nil,
            focused: :title,
            mode: :edit,
            error: nil,
            origin: :main_menu

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
      origin: Keyword.get(opts, :origin, :main_menu)
    }
  end
end

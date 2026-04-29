defmodule Foglet.TUI.Screens.PostComposer.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.PostComposer`.

  This is the screen-owned boundary for draft input, preview mode,
  route/reply identity, validation, submit status/result, and cancel origin.

  The app stores this struct at `state.screen_state[:post_composer]`.
  Nested stateful widget state is held as a first-class struct field.
  """

  alias Foglet.TUI.Context
  alias Raxol.UI.Components.Input.MultiLineInput

  @type submission_status :: :idle | :submitting | {:error, term()} | :submitted

  @type t :: %__MODULE__{
          board: map() | nil,
          board_id: String.t() | nil,
          thread: map() | nil,
          thread_id: String.t() | nil,
          mode: :edit | :preview,
          reply_to: map() | nil,
          error: String.t() | nil,
          input_state: map(),
          origin: atom(),
          submission_status: submission_status(),
          submit_result: term()
        }

  defstruct board: nil,
            board_id: nil,
            thread: nil,
            thread_id: nil,
            mode: :edit,
            reply_to: nil,
            error: nil,
            input_state: nil,
            origin: :main_menu,
            submission_status: :idle,
            submit_result: nil

  @doc """
  Builds a fresh PostComposer screen state struct.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 10)

    {:ok, input_state} =
      MultiLineInput.init(%{
        value: Keyword.get(opts, :value, ""),
        placeholder: "Write your post…",
        width: width,
        height: height,
        wrap: :none,
        focused: true
      })

    %__MODULE__{
      board: Keyword.get(opts, :board, nil),
      board_id: Keyword.get(opts, :board_id, nil),
      thread: Keyword.get(opts, :thread, nil),
      thread_id: Keyword.get(opts, :thread_id, nil),
      mode: Keyword.get(opts, :mode, :edit),
      reply_to: Keyword.get(opts, :reply_to, nil),
      error: Keyword.get(opts, :error, nil),
      input_state: Keyword.get(opts, :input_state) || input_state,
      origin: Keyword.get(opts, :origin, :main_menu),
      submission_status: Keyword.get(opts, :submission_status, :idle),
      submit_result: Keyword.get(opts, :submit_result, nil)
    }
  end

  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    params = context.route_params || %{}
    board = route_param(params, :board)
    thread = route_param(params, :thread)
    {w, _h} = context.terminal_size || {80, 24}

    new(
      width: max(w - 4, 20),
      board: board,
      board_id: route_param(params, :board_id) || id_from(board),
      thread: thread,
      thread_id: route_param(params, :thread_id) || id_from(thread),
      reply_to: route_param(params, :reply_to),
      origin: route_param(params, :origin) || :post_reader
    )
  end

  defp route_param(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp id_from(%{} = value), do: Map.get(value, :id) || Map.get(value, "id")
  defp id_from(_value), do: nil
end

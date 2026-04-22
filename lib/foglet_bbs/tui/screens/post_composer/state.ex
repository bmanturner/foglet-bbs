defmodule Foglet.TUI.Screens.PostComposer.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.PostComposer`.

  The app stores this struct at `state.screen_state[:post_composer]`.
  Nested stateful widget state is held as a first-class struct field.
  """

  alias Raxol.UI.Components.Input.MultiLineInput

  @type t :: %__MODULE__{
          mode: :edit | :preview,
          reply_to: map() | nil,
          error: String.t() | nil,
          input_state: map(),
          origin: atom()
        }

  defstruct mode: :edit,
            reply_to: nil,
            error: nil,
            input_state: nil,
            origin: :main_menu

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
      mode: Keyword.get(opts, :mode, :edit),
      reply_to: Keyword.get(opts, :reply_to, nil),
      error: Keyword.get(opts, :error, nil),
      input_state: Keyword.get(opts, :input_state) || input_state,
      origin: Keyword.get(opts, :origin, :main_menu)
    }
  end
end

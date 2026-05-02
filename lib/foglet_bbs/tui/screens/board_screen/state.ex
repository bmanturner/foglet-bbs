defmodule Foglet.TUI.Screens.BoardScreen.State do
  @moduledoc """
  Screen-local state for the board screen wrapper introduced in C5 of
  FOG-242.

  When the active board has chat disabled the wrapper is a structural
  pass-through to `Foglet.TUI.Screens.ThreadList` and the screen-local
  state stored on the App is a `%Foglet.TUI.Screens.ThreadList.State{}`
  directly. This struct is only used when the board has `chat_enabled`
  set to `true`; in that case the wrapper owns tab focus and the live
  presence count rendered as `2 CHAT (#)`.
  """

  alias Foglet.TUI.Screens.ThreadList

  @type tab :: :threads | :chat

  @type t :: %__MODULE__{
          thread_list: ThreadList.State.t(),
          current_tab: tab(),
          presence_count: non_neg_integer(),
          presence_tracked?: boolean(),
          board: map() | nil,
          board_id: String.t() | nil,
          user_id: String.t() | nil
        }

  defstruct thread_list: %ThreadList.State{},
            current_tab: :threads,
            presence_count: 0,
            presence_tracked?: false,
            board: nil,
            board_id: nil,
            user_id: nil
end

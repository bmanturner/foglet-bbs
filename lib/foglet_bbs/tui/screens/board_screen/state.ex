defmodule Foglet.TUI.Screens.BoardScreen.State do
  @moduledoc """
  Screen-local state for the board screen wrapper.

  The wrapper is used whenever a board has more than the base THREADS surface:
  chat, cached news, or operator-only feed CONFIG.
  """

  alias Foglet.TUI.Screens.{BoardConfig, BoardNews, ChatRoom, ThreadList}

  @type tab :: :threads | :chat | :news | :config

  @type t :: %__MODULE__{
          thread_list: ThreadList.State.t(),
          chat_room: ChatRoom.State.t() | nil,
          news: BoardNews.State.t() | nil,
          config: BoardConfig.State.t() | nil,
          tabs: [tab()],
          current_tab: tab(),
          chat_alert?: boolean(),
          chat_flash_phase: :on | :off,
          presence_count: non_neg_integer(),
          presence_tracked?: boolean(),
          board: map() | nil,
          board_id: String.t() | nil,
          user_id: String.t() | nil
        }

  defstruct thread_list: %ThreadList.State{},
            chat_room: nil,
            news: nil,
            config: nil,
            tabs: [:threads],
            current_tab: :threads,
            chat_alert?: false,
            chat_flash_phase: :off,
            presence_count: 0,
            presence_tracked?: false,
            board: nil,
            board_id: nil,
            user_id: nil
end

defmodule Foglet.TUI.Screens.ChatRoom.State do
  @moduledoc """
  Screen-local state for the board ChatRoom view (FOG-254 C6 of FOG-242).

  The wrapper `Foglet.TUI.Screens.BoardScreen` owns one of these per
  chat-enabled board route and forwards messages to it while the `:chat`
  tab is active.
  """

  @type message :: %{
          required(:id) => binary(),
          required(:body) => String.t(),
          required(:user_id) => binary() | nil,
          optional(:inserted_at) => any(),
          optional(any()) => any()
        }

  @type online_entry :: %{user_id: binary(), tab: :threads | :chat}

  @type t :: %__MODULE__{
          board: map() | nil,
          board_id: String.t() | nil,
          user_id: String.t() | nil,
          messages: [message()],
          handles: %{optional(binary()) => map() | String.t()},
          online: [online_entry()],
          composer: String.t(),
          status: :idle | :loading | :sending,
          last_error: term() | nil,
          sidebar_user_pref: nil | :show | :hide,
          autoscroll?: boolean(),
          scroll_offset: non_neg_integer(),
          loaded?: boolean()
        }

  defstruct board: nil,
            board_id: nil,
            user_id: nil,
            messages: [],
            handles: %{},
            online: [],
            composer: "",
            status: :idle,
            last_error: nil,
            sidebar_user_pref: nil,
            autoscroll?: true,
            scroll_offset: 0,
            loaded?: false
end

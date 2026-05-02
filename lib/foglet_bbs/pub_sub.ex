defmodule Foglet.PubSub do
  @moduledoc """
  Canonical PubSub topic constructors.

  Centralises topic strings so producers and consumers cannot drift.
  See `Foglet.TUI.PubSubForwarder` for the consumer side of these topics.
  """

  @spec user_topic(binary()) :: String.t()
  def user_topic(user_id), do: "user:" <> user_id

  @spec board_topic(binary()) :: String.t()
  def board_topic(board_id), do: "board:" <> board_id

  @spec thread_topic(binary()) :: String.t()
  def thread_topic(thread_id), do: "thread:" <> thread_id

  @spec boards_aggregate() :: String.t()
  def boards_aggregate, do: "boards"

  @spec board_chat_topic(binary()) :: String.t()
  def board_chat_topic(board_id), do: "board_chat:" <> board_id

  @spec board_screen_topic(binary()) :: String.t()
  def board_screen_topic(board_id), do: "board_screen:" <> board_id
end

defmodule Foglet.TUI.Input do
  @moduledoc """
  Key-event translation helpers shared across TUI screens.
  """

  @doc """
  Translates a Raxol-native key event map into a `MultiLineInput.update/2` message.
  Returns `nil` for events that have no MultiLineInput equivalent.
  """
  @spec translate_key(map()) :: tuple() | nil
  def translate_key(%{key: :backspace}), do: {:backspace}
  def translate_key(%{key: :delete}), do: {:delete}
  def translate_key(%{key: :enter}), do: {:enter}
  def translate_key(%{key: :up}), do: {:move_cursor, :up}
  def translate_key(%{key: :down}), do: {:move_cursor, :down}
  def translate_key(%{key: :left}), do: {:move_cursor, :left}
  def translate_key(%{key: :right}), do: {:move_cursor, :right}
  def translate_key(%{key: :home}), do: {:move_cursor_line_start}
  def translate_key(%{key: :end}), do: {:move_cursor_line_end}
  def translate_key(%{key: :page_up}), do: {:move_cursor_page, :up}
  def translate_key(%{key: :page_down}), do: {:move_cursor_page, :down}

  # Spacebar arrives as char: " " naturally; emoji/unicode graphemes work too.
  def translate_key(%{key: :char, char: c}) do
    case String.to_charlist(c) do
      [cp | _] when cp >= 32 -> {:input, cp}
      _ -> nil
    end
  end

  def translate_key(_), do: nil
end

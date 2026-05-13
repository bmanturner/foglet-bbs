defmodule Foglet.TUI.CommandEntry.ParserTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.CommandEntry.Parser

  test "plain input defaults to trimmed search" do
    assert Parser.parse("  old modem noises  ") == {:ok, {:search, "old modem noises"}}
  end

  test "board slug and message number parse as direct post navigation" do
    assert Parser.parse("  General_Board-1:0042  ") ==
             {:ok, {:direct_post, "general_board-1", 42}}
  end

  test "leading slash is reserved for future slash commands" do
    assert Parser.parse("/help me") == {:ok, {:slash, "help", "me"}}
    assert Parser.parse("/") == {:error, :empty_slash_command}
  end

  test "malformed direct addresses are errors instead of searches" do
    assert Parser.parse("general:") == {:error, :malformed_direct_post}
    assert Parser.parse("general:abc") == {:error, :malformed_direct_post}
    assert Parser.parse("general:0") == {:error, :malformed_direct_post}
  end

  test "blank input is rejected" do
    assert Parser.parse(" \t ") == {:error, :blank}
  end
end

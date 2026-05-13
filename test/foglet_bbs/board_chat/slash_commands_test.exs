defmodule Foglet.BoardChat.SlashCommandsTest do
  use ExUnit.Case, async: true

  alias Foglet.BoardChat.SlashCommands

  describe "parse/1" do
    test "returns plain payload for normal text" do
      assert {:ok, %{kind: :text, body: "hello /me later", metadata: %{}}} =
               SlashCommands.parse("hello /me later")
    end

    test "recognizes /me at the start of trimmed input" do
      assert {:ok, %{kind: :action, body: "waves", metadata: %{"command" => "me"}}} =
               SlashCommands.parse("  /me waves  ")
    end

    test "recognizes /ME case-insensitively and canonicalizes metadata" do
      assert {:ok, %{kind: :action, body: "waves", metadata: %{"command" => "me"}}} =
               SlashCommands.parse("/ME waves")
    end

    test "rejects empty /me actions with UX copy" do
      assert {:error, {:command_validation, "Add an action after /me, e.g. /me waves."}} =
               SlashCommands.parse("/me   ")
    end

    test "rejects unknown slash commands with UX copy" do
      assert {:error, {:command_validation, "Unknown chat command: /meow. Supported: /me."}} =
               SlashCommands.parse("/meow waves")
    end
  end
end

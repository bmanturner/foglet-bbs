defmodule Foglet.Notifications.MentionsTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Notifications.Mentions

  describe "extract_handles/1" do
    test "returns unique conservative handles in first-seen order case-insensitively" do
      assert Mentions.extract_handles("Hi @Alice, @bob_2 and @ALICE plus mail x@y.test") == [
               "Alice",
               "bob_2"
             ]
    end

    test "ignores embedded, malformed, and overlong handles" do
      overlong = String.duplicate("a", 21)

      assert Mentions.extract_handles(
               "email a@b.test midwordx@y @-bad @#{overlong} ok @good-name"
             ) == [
               "good-name"
             ]
    end
  end
end

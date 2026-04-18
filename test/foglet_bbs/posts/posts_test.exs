defmodule Foglet.PostsTest do
  use FogletBbs.DataCase, async: true
  import FogletBbs.BoardsFixtures

  describe "create_reply/3 (BOARD-03)" do
    @tag :pending
    test "creates a post with message_number from Board Server" do
      flunk("Pending — Plan 03 implements Foglet.Posts.create_reply/3")
    end

    @tag :pending
    test "increments thread.post_count and sets thread.last_post_at" do
      flunk("Pending — Plan 03 implements thread counter bump in Board Server Multi")
    end

    @tag :pending
    test "increments user.post_count" do
      flunk("Pending — Plan 03 implements user counter bump in Board Server Multi")
    end

    @tag :pending
    test "reply_to_id is optional and does not affect ordering" do
      flunk("Pending — Plan 03 implements optional reply_to_id in creation_changeset")
    end
  end

  describe "edit_post/3 (BOARD-04)" do
    @tag :pending
    test "updates post.body and increments edit_count" do
      flunk("Pending — Plan 03 implements Foglet.Posts.edit_post/3")
    end

    @tag :pending
    test "creates a post_edits row with previous_body before update" do
      flunk("Pending — Plan 03 implements edit history in Ecto.Multi")
    end

    @tag :pending
    test "edit history contains all previous versions in order" do
      flunk("Pending — Plan 03 implements unbounded edit history")
    end
  end

  describe "delete_post/2 (BOARD-11)" do
    @tag :pending
    test "sets deleted_at; message_number is preserved (no gap filling)" do
      flunk("Pending — Plan 03 implements soft-delete on posts")
    end

    @tag :pending
    test "soft-deleted posts are invisible to list_posts/1 queries" do
      flunk("Pending — Plan 03 implements is_nil(deleted_at) filter in list queries")
    end
  end
end

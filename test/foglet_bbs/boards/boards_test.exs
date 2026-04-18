defmodule Foglet.BoardsTest do
  use FogletBbs.DataCase, async: true
  import FogletBbs.BoardsFixtures

  describe "create_category/1 (BOARD-01)" do
    @tag :pending
    test "creates a category with valid attrs" do
      flunk("Pending — Plan 03 implements Foglet.Boards.create_category/1")
    end

    @tag :pending
    test "rejects category with blank name" do
      flunk("Pending — Plan 03 implements category changeset validation")
    end
  end

  describe "create_board/2 (BOARD-01)" do
    @tag :pending
    test "creates a board in a category with valid attrs" do
      flunk("Pending — Plan 03 implements Foglet.Boards.create_board/2")
    end

    @tag :pending
    test "rejects board with duplicate slug" do
      flunk("Pending — Plan 03 implements Board.changeset unique_constraint(:slug)")
    end

    @tag :pending
    test "rejects board with invalid slug format" do
      flunk("Pending — Plan 03 implements slug format validation")
    end
  end

  describe "subscribe_to_defaults/1 (BOARD-07)" do
    @tag :pending
    test "inserts subscriptions for all boards with default_subscription: true" do
      flunk("Pending — Plan 03 implements Foglet.Boards.subscribe_to_defaults/1")
    end

    @tag :pending
    test "is idempotent — duplicate subscriptions not inserted (on_conflict: :nothing)" do
      flunk("Pending — Plan 03 implements subscribe_to_defaults/1 with upsert")
    end
  end

  describe "advance_board_read_pointer/3 (BOARD-08)" do
    @tag :pending
    test "inserts a read pointer on first call" do
      flunk("Pending — Plan 03 implements advance_board_read_pointer/3")
    end

    @tag :pending
    test "updates existing pointer on subsequent call (upsert)" do
      flunk("Pending — Plan 03 implements upsert on board_read_pointers")
    end
  end

  describe "unread_counts/1 (BOARD-10)" do
    @tag :pending
    test "returns map of board_id => unread post count for subscribed boards" do
      flunk("Pending — Plan 03 implements Foglet.Boards.unread_counts/1")
    end

    @tag :pending
    test "unread count is 0 for boards read up to current message number" do
      flunk("Pending — Plan 03 implements unread count query")
    end

    @tag :pending
    test "soft-deleted posts are not counted as unread" do
      flunk("Pending — Plan 03 filters deleted_at IS NULL in unread query")
    end
  end
end

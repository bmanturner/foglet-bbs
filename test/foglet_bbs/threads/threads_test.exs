defmodule Foglet.ThreadsTest do
  use FogletBbs.DataCase, async: true
  import FogletBbs.BoardsFixtures

  describe "create_thread/3 (BOARD-02)" do
    @tag :pending
    test "creates thread with first_post_id set and root post in DB" do
      flunk("Pending — Plan 03 implements Foglet.Threads.create_thread/3 with Ecto.Multi")
    end

    @tag :pending
    test "thread.post_count is 1 after creation" do
      flunk("Pending — Plan 03 implements thread creation with initial counters")
    end

    @tag :pending
    test "root post has message_number allocated by Board Server" do
      flunk("Pending — Plan 02+03 implement Board Server + create_thread integration")
    end
  end

  describe "advance_thread_read_pointer/3 (BOARD-09)" do
    @tag :pending
    test "inserts thread read pointer on first read" do
      flunk("Pending — Plan 03 implements Foglet.Threads.advance_read_pointer/3")
    end

    @tag :pending
    test "updates last_read_post_id on subsequent reads (upsert)" do
      flunk("Pending — Plan 03 implements upsert on thread_read_pointers")
    end
  end

  describe "lock_thread/1, sticky_thread/1 (BOARD-12)" do
    @tag :pending
    test "lock_thread/1 sets locked: true" do
      flunk("Pending — Plan 03 implements Foglet.Threads.lock_thread/1")
    end

    @tag :pending
    test "sticky_thread/1 sets sticky: true" do
      flunk("Pending — Plan 03 implements Foglet.Threads.sticky_thread/1")
    end
  end

  describe "move_thread/3 (BOARD-12)" do
    @tag :pending
    test "updates thread.board_id and all thread posts' board_id" do
      flunk("Pending — Plan 03 implements move_thread/3 with Ecto.Multi update_all")
    end
  end
end

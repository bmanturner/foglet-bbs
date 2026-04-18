defmodule Foglet.Boards.ServerTest do
  use FogletBbs.DataCase, async: false
  use ExUnitProperties

  describe "Board Server (BOARD-06)" do
    @tag :pending
    test "starts and registers via Registry under board_id" do
      flunk("Pending — Plan 02 implements Foglet.Boards.Server GenServer")
    end

    @tag :pending
    test "init loads next_message_number as MAX(message_number)+1 from DB (D-05)" do
      flunk("Pending — Plan 02 implements Server.init/1 with DB reload")
    end

    @tag :pending
    test "allocates sequential message numbers for posts in a single board" do
      flunk("Pending — Plan 02 implements allocate_and_insert call in Server")
    end

    @tag :pending
    test "does not advance counter when transaction fails" do
      flunk("Pending — Plan 02 implements rollback-safe counter in Server")
    end

    @tag :pending
    test "message numbers are per-board (two boards have independent sequences)" do
      flunk("Pending — Plan 02 implements per-board Server instances")
    end
  end

  describe "message-number monotonicity property (BOARD-06)" do
    @tag :pending
    property "message numbers are monotonically sequential under concurrent inserts" do
      flunk("Pending — Plan 02 implements Server; Plan 04 writes property test assertions")
    end
  end
end

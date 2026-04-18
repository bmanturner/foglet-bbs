defmodule Foglet.TUI.Screens.PostReaderTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.PostReader (SSH-07, SSH-08, SSH-09)" do
    @tag :pending
    test "render/1 displays post with ANSI-rendered Markdown body" do
      flunk("Pending — Plan 04 implements PostReader (calls Foglet.Markdown.render/1)")
    end

    @tag :pending
    test "page-down/page-up navigate between posts in thread" do
      flunk("Pending — Plan 04 implements pagination")
    end

    @tag :pending
    test "advances thread_read_pointer local state on next-post (SSH-09)" do
      flunk("Pending — Plan 04 implements read-pointer local state")
    end

    @tag :pending
    test "flush triggered on screen transition via Foglet.Threads.advance_read_pointer/3 (SSH-09)" do
      flunk("Pending — Plan 04 implements flush on leave")
    end

    @tag :pending
    test "'R' opens post_composer as reply to current post" do
      flunk("Pending — Plan 04 implements reply shortcut")
    end
  end
end

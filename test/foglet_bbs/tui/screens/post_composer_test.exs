defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.PostComposer (SSH-07, D-26..D-31)" do
    @tag :pending
    test "render/1 shows header, quote context, multi-line text input, key bar (D-27)" do
      flunk("Pending — Plan 04 implements PostComposer layout")
    end

    @tag :pending
    test "renders first 5 lines of reply-to post as dimmed quote context (D-27)" do
      flunk("Pending — Plan 04 implements quote context")
    end

    @tag :pending
    test "Tab toggles between edit mode and preview mode (D-28)" do
      flunk("Pending — Plan 04 implements Tab preview toggle")
    end

    @tag :pending
    test "Ctrl+S submits the post via Foglet.Posts.create_reply/3 (D-29)" do
      flunk("Pending — Plan 04 implements submit")
    end

    @tag :pending
    test "Ctrl+C cancels with no confirmation prompt (D-30)" do
      flunk("Pending — Plan 04 implements cancel")
    end

    @tag :pending
    test "enforces max_post_length from runtime config (D-31)" do
      flunk("Pending — Plan 04 enforces Foglet.Config.get!(\"max_post_length\")")
    end

    @tag :pending
    test "displays error when body exceeds max_post_length" do
      flunk("Pending — Plan 04 surfaces max-length error")
    end
  end
end

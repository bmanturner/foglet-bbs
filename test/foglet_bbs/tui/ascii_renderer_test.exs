defmodule Foglet.TUI.AsciiRendererTest do
  @moduledoc """
  Smoke coverage for the agent-facing TUI inspection tool.

  Each screen is rendered with `RenderFixtures` + `App.view/1` + `AsciiRenderer`
  and asserted to:
    1. Produce the requested terminal dimensions.
    2. Paint chrome without overflowing the requested grid.

  We're not screenshot-testing layout here (`layout_smoke_test.exs` already
  does that); we're guarding the `mix foglet.tui.render` public surface
  against silent regressions.
  """

  use ExUnit.Case, async: true

  alias Foglet.Config
  alias Foglet.TUI.App
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.RenderFixtures

  setup_all do
    # The renderer reads schematized config keys (registration_mode,
    # max_thread_title_length, …). Seed the cache with the schema's
    # declared defaults so tests don't depend on the Repo.
    Config.init_cache()

    Enum.each(Foglet.Config.Schema.defaults(), fn {key, value} ->
      :ets.insert(:foglet_config, {key, value})
    end)

    {:ok, _} = Application.ensure_all_started(:tzdata)
    :ok
  end

  @size {80, 24}

  describe "render/2" do
    test "produces a grid with the requested dimensions" do
      view = App.view(RenderFixtures.state_for(:login, @size))
      ascii = AsciiRenderer.render(view, @size)

      lines = String.split(ascii, "\n", trim: false)
      assert length(lines) == 24

      # `String.trim_trailing` strips trailing spaces, so we only check that
      # painted content fits within the requested width.
      Enum.each(lines, fn line ->
        assert String.length(line) <= 80
      end)
    end

    for screen <- RenderFixtures.screens() do
      test "renders the #{screen} screen with a chrome border" do
        view = App.view(RenderFixtures.state_for(unquote(screen), @size))
        ascii = AsciiRenderer.render(view, @size)

        # Top-left and bottom-left corners of the foglet screen frame.
        assert String.contains?(ascii, "┌"),
               "missing top-left chrome corner for #{unquote(screen)}:\n#{ascii}"

        assert String.contains?(ascii, "└"),
               "missing bottom-left chrome corner for #{unquote(screen)}:\n#{ascii}"
      end
    end

    test "respects custom width and height" do
      view = App.view(RenderFixtures.state_for(:login, {120, 30}))
      ascii = AsciiRenderer.render(view, {120, 30})

      lines = String.split(ascii, "\n")
      assert length(lines) == 30
    end
  end

  describe "RenderFixtures.state_for/2" do
    test "raises ArgumentError for unknown screens" do
      assert_raise ArgumentError, ~r/unknown screen/, fn ->
        RenderFixtures.state_for(:not_a_screen, @size)
      end
    end
  end
end

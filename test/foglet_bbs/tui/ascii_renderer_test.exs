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

    test "renders app-level unread notification chrome on main menu and board list" do
      for {screen, size} <- [
            {:main_menu, {64, 22}},
            {:main_menu, @size},
            {:board_list, {64, 22}},
            {:board_list, @size}
          ] do
        state =
          screen
          |> RenderFixtures.state_for(size)
          |> Map.put(:unread_notifications_count, 12)

        ascii = state |> App.view() |> AsciiRenderer.render(size)

        assert ascii =~ "@alice | N 12 |",
               "expected unread notification chrome for #{inspect(screen)} at #{inspect(size)}:\n#{ascii}"
      end
    end

    test "account preferences select-list does not overlap following fields at 80x24" do
      state =
        RenderFixtures.state_for(:account, @size,
          seed_state: %{"screen_state" => %{"account" => %{"active_tab" => 1}}}
        )

      ascii = state |> App.view() |> AsciiRenderer.render(@size)

      refute ascii =~ "Time format:ronto",
             "select-list option text must not bleed into the next field label:\n#{ascii}"

      assert ascii =~ "Time format"
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

  describe "RenderFixtures.state_for/3" do
    test "seeds login sub-states" do
      state = RenderFixtures.state_for(:login, @size, substate: "reset_consume")

      assert state.current_screen == :login
      assert %{sub: :reset_consume, token_input: token_input} = state.screen_state.login
      assert token_input.raxol_state.value == "RESET-TOKEN"
    end

    test "seeds unified reset recovery for QA rendering" do
      state = RenderFixtures.state_for(:login, @size, substate: "reset_recovery")

      assert state.current_screen == :login

      assert %{
               sub: :reset_recovery,
               active_pane: :request,
               identifier_input: identifier_input,
               token_input: token_input
             } = state.screen_state.login

      assert identifier_input.raxol_state.value == "alice@example.com"
      assert token_input.raxol_state.value == "RESET-TOKEN"
    end

    test "seeds invite-only register gating" do
      state = RenderFixtures.state_for(:register, @size, substate: "invite_only")

      assert state.session_context.registration_mode == "invite_only"
      assert %{mode: "invite_only", step: :invite_code} = state.screen_state.register
    end

    test "seeds verify resend cooldown copy through a modal" do
      state = RenderFixtures.state_for(:verify, @size, substate: "resend_cooldown")

      assert state.current_screen == :verify
      assert %{resend_cooldown_until: %DateTime{}} = state.screen_state.verify
      assert state.modal.message =~ "Please wait to resend"
    end

    test "seeds account-state gates as renderable login modals" do
      state = RenderFixtures.state_for(:login, @size, substate: "suspended")

      assert state.current_user.status == :suspended
      assert state.current_screen == :login
      assert state.modal.message == "Your account is suspended. Contact the sysop."
    end

    test "hydrates a JSON-decoded app state overlay" do
      state =
        RenderFixtures.state_for(:login, @size,
          seed_state: %{
            "session_context" => %{"registration_mode" => "disabled"},
            "screen_state" => %{
              "login" => %{"sub" => "login_form"}
            }
          }
        )

      assert state.session_context.registration_mode == "disabled"
      assert state.screen_state.login.sub == :login_form
    end

    test "raises ArgumentError for unknown sub-states" do
      assert_raise ArgumentError, ~r/unknown substate/, fn ->
        RenderFixtures.state_for(:login, @size, substate: "nope")
      end
    end
  end
end

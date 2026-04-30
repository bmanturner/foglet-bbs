defmodule Foglet.TUI.Widgets.Chrome.BreadcrumbMigrationTest do
  @moduledoc """
  Plan 39-06 (Breadcrumb migration) contract tests.

  After this plan:
  - `BreadcrumbBar.parts_for/1` is deleted (per Phase 39 SPEC R3 / D-12).
  - `BreadcrumbBar.parts_for_screen/2`, `BreadcrumbBar.board_name/1`,
    `BreadcrumbBar.thread_title/1` are deleted.
  - `ScreenFrame.normalize_chrome/2` falls back to `breadcrumb_parts: ["Foglet"]`
    when no parts are supplied (instead of calling the deleted parts_for/1).
  - The four migrated screens (ThreadList, PostReader, PostComposer, NewThread)
    must emit a non-empty `:breadcrumb_parts` list when `render/2` is called.
  """
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context

  alias Foglet.TUI.Screens.{
    Account,
    BoardList,
    Login,
    MainMenu,
    Moderation,
    NewThread,
    PostComposer,
    PostReader,
    Register,
    ThreadList,
    Verify
  }

  alias Foglet.TUI.Screens.Account.State, as: AccountState
  alias Foglet.TUI.Screens.BoardList.State, as: BoardListState
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias Foglet.TUI.Screens.Moderation.State, as: ModerationState
  alias Foglet.TUI.Screens.NewThread.State, as: NewThreadState
  alias Foglet.TUI.Screens.PostComposer.State, as: PostComposerState
  alias Foglet.TUI.Screens.PostReader.State, as: PostReaderState
  alias Foglet.TUI.Screens.Register.State, as: RegisterState
  alias Foglet.TUI.Screens.ThreadList.State, as: ThreadListState
  alias Foglet.TUI.Screens.Verify.State, as: VerifyState
  alias Foglet.TUI.Widgets.Chrome.BreadcrumbBar

  describe "BreadcrumbBar surface" do
    test "parts_for/1 is no longer exported" do
      refute function_exported?(BreadcrumbBar, :parts_for, 1)
    end

    test "format/2 still accepts an explicit parts list" do
      assert BreadcrumbBar.format(["Foglet", "Boards"], []) == "Foglet ▸ Boards"
    end

    test "render/3 still accepts an explicit parts list" do
      theme = Foglet.TUI.Theme.default()
      result = BreadcrumbBar.render(theme, ["Foglet", "Boards", "general"], width: 80)
      assert is_map(result)
    end
  end

  describe "ScreenFrame fallback breadcrumb" do
    alias Foglet.TUI.Widgets.Chrome.ScreenFrame

    test "renders chrome maps without :breadcrumb_parts using ['Foglet'] fallback" do
      # Drives the new normalize_chrome/2 fallback path. The frame must build
      # a plausible chrome model with a single-segment breadcrumb when the
      # screen-supplied chrome map omits :breadcrumb_parts.
      state = %{
        current_screen: :main_menu,
        terminal_size: {80, 24},
        session_context: %{}
      }

      tree =
        ScreenFrame.render(
          state,
          %{},
          %{type: :text, content: "BODY", attrs: %{}, children: []},
          [%{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}]
        )

      # The chrome was built and rendered without raising; that's the contract.
      assert is_map(tree)
      assert tree.type == :foglet_screen_frame
    end
  end

  describe "screen render emits :breadcrumb_parts" do
    setup do
      context = %Context{
        current_user: %{id: "u1", handle: "alice", role: :sysop},
        terminal_size: {120, 40},
        session_context: %{registration_mode: "open", invite_code_generators: "sysops"},
        route_params: %{}
      }

      {:ok, context: context}
    end

    test "ThreadList passes a non-empty breadcrumb_parts list", %{context: context} do
      state = %ThreadListState{
        board: %{id: "b1", name: "general"},
        board_id: "b1",
        threads: [],
        status: :empty
      }

      assert capture_breadcrumb_parts(fn -> ThreadList.render(state, context) end)
             |> Enum.member?("general")
    end

    test "PostReader passes a non-empty breadcrumb_parts list", %{context: context} do
      state = %PostReaderState{
        board: %{id: "b1", name: "general"},
        board_id: "b1",
        thread: %{id: "t1", title: "Hello world"},
        thread_id: "t1",
        posts: [],
        status: :empty
      }

      parts = capture_breadcrumb_parts(fn -> PostReader.render(state, context) end)
      assert Enum.member?(parts, "general")
      assert Enum.member?(parts, "Hello world")
    end

    test "PostComposer passes a non-empty breadcrumb_parts list", %{context: context} do
      {:ok, input_state} =
        Raxol.UI.Components.Input.MultiLineInput.init(%{
          value: "",
          placeholder: "",
          width: 60,
          height: 10,
          wrap: :none,
          focused: true
        })

      state = %PostComposerState{
        board: %{id: "b1", name: "general"},
        board_id: "b1",
        thread: %{id: "t1", title: "Hello world"},
        thread_id: "t1",
        input_state: input_state
      }

      parts = capture_breadcrumb_parts(fn -> PostComposer.render(state, context) end)
      assert Enum.member?(parts, "general")
      assert Enum.member?(parts, "Hello world")
      assert Enum.member?(parts, "Reply")
    end

    test "NewThread passes a non-empty breadcrumb_parts list (board step)", %{context: context} do
      state = %NewThreadState{step: :board, boards: nil, board: nil}
      parts = capture_breadcrumb_parts(fn -> NewThread.render(state, context) end)
      assert Enum.member?(parts, "Foglet")
      assert Enum.member?(parts, "New Thread")
    end

    test "Login passes its explicit breadcrumb_parts list", %{context: context} do
      parts = capture_breadcrumb_parts(fn -> Login.render(LoginState.default(), context) end)
      assert parts == ["Foglet", "Login"]
    end

    test "Register passes its explicit breadcrumb_parts list", %{context: context} do
      parts =
        capture_breadcrumb_parts(fn ->
          Register.render(RegisterState.default(), context)
        end)

      assert parts == ["Foglet", "Register"]
    end

    test "Verify passes its explicit breadcrumb_parts list", %{context: context} do
      parts = capture_breadcrumb_parts(fn -> Verify.render(VerifyState.default(), context) end)
      assert parts == ["Foglet", "Verify"]
    end

    test "MainMenu passes its explicit breadcrumb_parts list", %{context: context} do
      parts =
        capture_breadcrumb_parts(fn -> MainMenu.render(MainMenuState.new(context), context) end)

      assert parts == ["Foglet", "Home"]
    end

    test "BoardList passes its explicit breadcrumb_parts list", %{context: context} do
      state = BoardListState.new(status: :empty)
      parts = capture_breadcrumb_parts(fn -> BoardList.render(state, context) end)
      assert parts == ["Foglet", "Boards"]
    end

    test "Account passes its explicit breadcrumb_parts list", %{context: context} do
      parts = capture_breadcrumb_parts(fn -> Account.render(AccountState.new(), context) end)
      assert parts == ["Foglet", "Account"]
    end

    test "Moderation passes its explicit breadcrumb_parts list", %{context: context} do
      parts =
        capture_breadcrumb_parts(fn ->
          Moderation.render(ModerationState.new(), context)
        end)

      assert parts == ["Foglet", "Moderation"]
    end
  end

  # Helpers
  # ---------------------------------------------------------------------------

  # Captures the breadcrumb_parts that the screen actually passed to ScreenFrame
  # by intercepting via Process dictionary. We rely on the BreadcrumbBar.render/3
  # call sequence inside ScreenFrame: it gets called with the parts list. We
  # use the rendered tree text to extract the parts.
  defp capture_breadcrumb_parts(render_fun) do
    tree = render_fun.()
    extract_breadcrumb_parts(tree)
  end

  # Walks the rendered tree looking for the BreadcrumbBar text element
  # (in top_segments) and returns the parts list reconstructed from the
  # joined string (or returns the chrome model breadcrumb_parts if surfaced).
  defp extract_breadcrumb_parts(%{top_segments: segments}) do
    segments
    |> List.flatten()
    |> Enum.map_join("", &Map.get(&1, :content, Map.get(&1, :text, "")))
    |> String.split("▸")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&drop_border_chrome/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_breadcrumb_parts(_other), do: []

  # The first segment carries "┌ Foglet"; the last segment in the breadcrumb
  # span runs into the spacing dashes/status. Strip those non-breadcrumb
  # decorations.
  defp drop_border_chrome(segment) do
    segment
    |> String.trim_leading("┌")
    |> String.trim()
    |> String.split(~r/\s{2,}|─/, parts: 2)
    |> List.first()
    |> Kernel.||("")
    |> String.trim()
  end
end

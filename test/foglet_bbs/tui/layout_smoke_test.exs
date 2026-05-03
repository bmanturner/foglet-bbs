defmodule Foglet.TUI.LayoutSmokeTest do
  @moduledoc """
  End-to-end layout verification tests (#17).

  These tests drive each layout-intensive screen's render/1 through
  Raxol.UI.Layout.Engine.apply_layout/2 — the same pipeline the Raxol
  Lifecycle uses — and assert that text elements appear at DISTINCT y
  positions, proving children are vertically stacked.

  Before the block-DSL migration, the old box(children: [...]) produced
  %{type: :box} elements processed by process_element/3 in engine.ex lines
  253-281, which stacked all children at the same y (last child overwrote
  all previous ones). These tests would have failed on that old code.
  """

  use FogletBbs.DataCase, async: false

  import Raxol.Core.Renderer.View

  alias Foglet.Config
  alias Foglet.TUI.App
  alias Foglet.TUI.Context
  alias Foglet.TUI.RenderFixtures
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Widgets.List.BoardTree

  alias Foglet.TUI.Screens.{
    Account,
    BoardList,
    MainMenu,
    Moderation,
    NewThread,
    PostComposer,
    PostReader,
    Sysop,
    ThreadList
  }

  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.List.ListRow
  alias Foglet.TUI.Widgets.Modal
  alias Raxol.UI.Components.Input.MultiLineInput
  alias Raxol.UI.Layout.Engine

  @dimensions %{width: 80, height: 24}
  @phase_16_dimensions [{64, 22}, {80, 24}, {132, 50}]
  @large_screen_contract [
    %{
      screen: :post_reader,
      top_level_file: "lib/foglet_bbs/tui/screens/post_reader.ex",
      state_file: "lib/foglet_bbs/tui/screens/post_reader/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/post_reader/render.ex",
      top_level_module: PostReader,
      state_module: PostReader.State,
      render_module: PostReader.Render,
      render_arity: 2
    },
    %{
      screen: :sysop,
      top_level_file: "lib/foglet_bbs/tui/screens/sysop.ex",
      state_file: "lib/foglet_bbs/tui/screens/sysop/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/sysop/render.ex",
      top_level_module: Sysop,
      state_module: Sysop.State,
      render_module: Sysop.Render,
      render_arity: 1
    },
    %{
      screen: :login,
      top_level_file: "lib/foglet_bbs/tui/screens/login.ex",
      state_file: "lib/foglet_bbs/tui/screens/login/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/login/render.ex",
      top_level_module: Foglet.TUI.Screens.Login,
      state_module: Foglet.TUI.Screens.Login.State,
      render_module: Foglet.TUI.Screens.Login.Render,
      render_arity: 2
    },
    %{
      screen: :main_menu,
      top_level_file: "lib/foglet_bbs/tui/screens/main_menu.ex",
      state_file: "lib/foglet_bbs/tui/screens/main_menu/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/main_menu/render.ex",
      top_level_module: MainMenu,
      state_module: MainMenu.State,
      render_module: MainMenu.Render,
      render_arity: 2
    },
    %{
      screen: :new_thread,
      top_level_file: "lib/foglet_bbs/tui/screens/new_thread.ex",
      state_file: "lib/foglet_bbs/tui/screens/new_thread/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/new_thread/render.ex",
      top_level_module: NewThread,
      state_module: NewThread.State,
      render_module: NewThread.Render,
      render_arity: 2
    },
    %{
      screen: :account,
      top_level_file: "lib/foglet_bbs/tui/screens/account.ex",
      state_file: "lib/foglet_bbs/tui/screens/account/state.ex",
      render_file: "lib/foglet_bbs/tui/screens/account/render.ex",
      top_level_module: Account,
      state_module: Account.State,
      render_module: Account.Render,
      render_arity: 1
    }
  ]
  @render_forbidden_runtime_call_patterns [
    {"SiteForm.init", ~r/\bSiteForm\.init\(/},
    {"Effect.task", ~r/\bEffect\.task\(/},
    {"Effect.navigate", ~r/\bEffect\.navigate\(/},
    {"Repo", ~r/\bRepo\./},
    {"Config.get", ~r/\bConfig\.get\(/},
    {"Config.get!", ~r/\bConfig\.get!\(/},
    {"Config.fetch", ~r/\bConfig\.fetch\(/},
    {"PubSub", ~r/\bPubSub\b/},
    {"Config.put", ~r/\bConfig\.put!?\(/},
    {"start_supervised", ~r/\bstart_supervised!?\(/}
  ]

  # Seed the ETS config cache so render paths that call Config.get/2
  # (Login, Register, Verify screens) do not hit the DB.
  # Config.get/2 now only rescues Ecto.NoResultsError — other DB errors
  # propagate, so async tests without a DB checkout would fail without this.
  setup do
    Config.init_cache()
    :ets.insert(:foglet_config, {"registration_mode", "open"})
    :ets.insert(:foglet_config, {"email_verify_resend_cooldown_seconds", 60})
    :ok
  end

  # Extract all text-type elements with non-empty text from the positioned list.
  defp text_elements(positioned) do
    positioned
    |> List.flatten()
    |> Enum.filter(fn el ->
      el.type == :text and is_binary(Map.get(el, :text, "")) and
        String.length(Map.get(el, :text, "")) > 0
    end)
  end

  defp content_text_elements(positioned) do
    positioned
    |> text_elements()
    |> Enum.reject(&chrome_frame_element?/1)
  end

  defp text_rows(elements) do
    elements
    |> Enum.group_by(& &1.y)
    |> Map.new(fn {y, row_elements} ->
      row_text =
        row_elements
        |> Enum.sort_by(& &1.x)
        |> Enum.map_join(& &1.text)

      {y, row_text}
    end)
  end

  defp positioned_row_text(positioned, y) do
    positioned
    |> text_elements()
    |> Enum.filter(&(&1.y == y))
    |> Enum.sort_by(& &1.x)
    |> Enum.map_join(& &1.text)
  end

  defp bottom_row_text(positioned) do
    y =
      positioned
      |> text_elements()
      |> Enum.map(& &1.y)
      |> Enum.max()

    positioned_row_text(positioned, y)
  end

  defp chrome_frame_element?(element) do
    element |> Map.get(:attrs, %{}) |> Map.get(:chrome_frame?, false)
  end

  defp layout(tree), do: Engine.apply_layout(tree, @dimensions)

  defp apply_at_size(tree, {width, height}) do
    Engine.apply_layout(tree, %{width: width, height: height})
  end

  defp screen_context(screen, user, size, route_params \\ %{}) do
    Context.new(
      current_user: user,
      route: screen,
      route_params: route_params,
      terminal_size: size,
      session_context: %{theme: Foglet.TUI.Theme.default()}
    )
  end

  defp render_login(%App{} = state), do: App.view(%{state | current_screen: :login})
  defp render_register(%App{} = state), do: App.view(%{state | current_screen: :register})
  defp render_verify(%App{} = state), do: App.view(%{state | current_screen: :verify})

  defp render_main_menu(state) when is_map(state) do
    app = app_from_map(state)

    local_state =
      %MainMenu.State{}
      |> MainMenu.State.from_entries(Map.get(state, :recent_oneliners, []))
      |> MainMenu.State.select_index(Map.get(state, :selected_oneliner_index, 0))
      |> MainMenu.State.set_pending_hide(Map.get(state, :pending_hide_oneliner_id))

    app
    |> Map.put(:current_screen, :main_menu)
    |> App.put_screen_state(:main_menu, local_state)
    |> App.view()
  end

  defp app_from_map(%App{} = state), do: state

  defp app_from_map(state) when is_map(state) do
    struct!(App, Map.take(state, Map.keys(%App{})))
  end

  defp render_app_screen(screen_mod, key, state) when is_atom(screen_mod) and is_atom(key) do
    app = app_from_map(state)
    context = App.build_context(app)
    local_state = App.screen_state_for(app, key) || screen_mod.init(context)

    screen_mod.render(local_state, context)
  end

  defp render_app_screen(state, screen_mod, key) when is_map(state) and is_atom(screen_mod) do
    render_app_screen(screen_mod, key, state)
  end

  defp collect_text(tree), do: tree |> collect_text([]) |> Enum.reverse()

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = collect_node_text(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp collect_text(_other, acc), do: acc

  defp collect_node_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_node_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp collect_node_text(_node, acc), do: acc

  defp flatten_text(tree), do: tree |> collect_text() |> Enum.join("")

  defp repo_path(path) do
    Path.expand(Path.join([__DIR__, "../../..", path]))
  end

  defp assert_line_within_width!(label, line, width) do
    assert TextWidth.display_width(line) <= width,
           "#{label}: expected #{inspect(line)} to fit #{width} columns, got #{TextWidth.display_width(line)}"
  end

  defp unicode_compose_input(value, cursor_pos, width) do
    {:ok, input_st} =
      MultiLineInput.init(%{
        value: value,
        placeholder: "",
        width: width,
        height: 5,
        wrap: :none,
        focused: true
      })

    %{input_st | cursor_pos: cursor_pos}
  end

  # ---------------------------------------------------------------------------
  # Chrome V2 size contracts
  # ---------------------------------------------------------------------------

  describe "large screen decomposition source contract" do
    test "all six target screens expose reducer, state, and render files" do
      for contract <- @large_screen_contract do
        for key <- [:top_level_file, :state_file, :render_file] do
          path = repo_path(Map.fetch!(contract, key))

          assert File.regular?(path),
                 "#{contract.screen} expected #{key} at #{Map.fetch!(contract, key)}"
        end

        assert Code.ensure_loaded?(contract.top_level_module)
        assert Code.ensure_loaded?(contract.state_module)
        assert Code.ensure_loaded?(contract.render_module)
        assert function_exported?(contract.top_level_module, :init, 1)
        assert function_exported?(contract.top_level_module, :update, 3)
        assert function_exported?(contract.top_level_module, :render, 2)
        assert function_exported?(contract.render_module, :render, contract.render_arity)
      end
    end

    test "render entry point files do not contain forbidden runtime calls" do
      for contract <- @large_screen_contract do
        source = contract.render_file |> repo_path() |> File.read!()

        for {label, pattern} <- @render_forbidden_runtime_call_patterns do
          refute Regex.match?(pattern, source),
                 "#{contract.render_file} must not contain #{label} runtime calls"
        end
      end
    end
  end

  describe "Chrome V2 size contracts" do
    test "screen frame text stays positioned within required terminal widths" do
      alias Foglet.TUI.Widgets.Chrome.ScreenFrame

      user = %{
        id: "u1",
        handle: "alice",
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"}
      }

      for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
        state = %{
          current_screen: :thread_list,
          current_user: user,
          current_board: %{name: "general"},
          session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
          terminal_size: {width, height}
        }

        positioned =
          state
          |> ScreenFrame.render(
            %{breadcrumb_parts: ["Foglet", "Threads"]},
            text("BODY SENTINEL"),
            [
              %{
                label: "Navigate",
                commands: [
                  %{key: "J/K", label: "Navigate", priority: 10},
                  %{key: "Enter", label: "Open", priority: 10}
                ]
              },
              %{
                label: "System",
                commands: [%{key: "Q", label: "Back", priority: 0}]
              }
            ]
          )
          |> apply_at_size({width, height})

        elements = text_elements(positioned)

        assert elements != [],
               "expected positioned text elements for #{inspect({width, height})}"

        for element <- elements do
          text = Map.fetch!(element, :text)

          assert element.x >= 0
          assert element.y >= 0
          assert element.x + TextWidth.display_width(text) <= width
        end

        rows = text_rows(elements)
        top_row = Map.get(rows, 0, "")
        bottom_row = Map.get(rows, height - 1, "")
        breadcrumb = Enum.find(elements, &String.contains?(&1.text, "Foglet"))

        content =
          Enum.find(elements, fn element ->
            String.contains?(element.text, "BODY SENTINEL")
          end)

        command = Enum.find(elements, &(&1.y == height - 1 and &1.text in ["J/K", "Navigate"]))

        assert breadcrumb, "expected breadcrumb/status text at #{inspect({width, height})}"
        assert content, "expected body text at #{inspect({width, height})}"
        assert command, "expected command text at #{inspect({width, height})}"
        assert String.starts_with?(top_row, "┌")
        assert String.ends_with?(top_row, "┐")
        assert String.starts_with?(bottom_row, "└")
        assert String.ends_with?(bottom_row, "┘")
        assert breadcrumb.y == 0
        assert breadcrumb.y < content.y
        assert content.y < command.y
        assert command.y == height - 1
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 20 — ThreadList rich-row size contracts (RICHROW-01 / THREADS-01)
  # ---------------------------------------------------------------------------

  describe "thread_list — size contract" do
    setup do
      now = DateTime.utc_now()
      long_title = String.duplicate("x", 100)

      threads = [
        %Foglet.Threads.ThreadEntry{
          id: "t1",
          title: "Sticky " <> long_title,
          board_id: "b1",
          sticky: true,
          locked: false,
          has_unread: true,
          post_count: 5,
          last_post_at: now,
          created_by: %{handle: "alice"}
        },
        %Foglet.Threads.ThreadEntry{
          id: "t2",
          title: "Locked thread title",
          board_id: "b1",
          sticky: false,
          locked: true,
          has_unread: false,
          post_count: 3,
          last_post_at: DateTime.add(now, -3600, :second),
          created_by: %{handle: "alice"}
        },
        %Foglet.Threads.ThreadEntry{
          id: "t3",
          title: "Plain thread",
          board_id: "b1",
          sticky: false,
          locked: false,
          has_unread: false,
          post_count: 1,
          last_post_at: DateTime.add(now, -7200, :second),
          created_by: %{handle: "alice"}
        }
      ]

      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      %{threads: threads, user: user}
    end

    defp thread_row_elements(positioned, title_substring) do
      elements = text_elements(positioned)

      anchor =
        Enum.find(elements, fn el ->
          text = Map.get(el, :text, "")
          is_binary(text) and String.contains?(text, title_substring)
        end)

      case anchor do
        nil ->
          flunk(
            "could not find a text element containing #{inspect(title_substring)} " <>
              "in positioned render. text_elements=#{inspect(Enum.map(elements, & &1.text))}"
          )

        %{y: y} ->
          row =
            elements
            |> Enum.filter(fn el -> el.y == y end)
            |> Enum.sort_by(& &1.x)

          {y, row}
      end
    end

    defp row_text(elements) do
      Enum.map_join(elements, &Map.get(&1, :text, ""))
    end

    defp row_display_width(elements) do
      elements
      |> Enum.map(fn el ->
        el.x + TextWidth.display_width(Map.get(el, :text, ""))
      end)
      |> Enum.max(fn -> 0 end)
    end

    for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
      @width width
      @height height
      @tag :"thread_list — size contract"
      test "at #{width}x#{height} cluster, metadata visible; title truncates only when forced",
           %{threads: threads, user: user} do
        width = @width
        height = @height
        locked_glyph = "⚿"

        board = %{id: "b1", name: "General", slug: "general"}
        size = {width, height}

        state =
          ThreadList.State.new(
            board: board,
            board_id: board.id,
            threads: threads,
            selected_index: 0,
            status: :loaded
          )

        tree =
          ThreadList.render(
            state,
            screen_context(:thread_list, user, size, %{board_id: board.id})
          )

        positioned = apply_at_size(tree, {width, height})

        {_y_sticky, sticky_row} = thread_row_elements(positioned, "Sticky")
        sticky_text = row_text(sticky_row)

        assert sticky_text =~ "◆",
               "expected unread glyph in sticky row at #{width}x#{height}, got: #{inspect(sticky_text)}"

        assert sticky_text =~ "●",
               "expected sticky glyph in sticky row at #{width}x#{height}, got: #{inspect(sticky_text)}"

        assert sticky_text =~ "@alice"
        assert sticky_text =~ "·"

        if width <= 80 do
          assert sticky_text =~ "…",
                 "expected title truncation in sticky row at #{width}, got: #{inspect(sticky_text)}"
        end

        assert row_display_width(sticky_row) <= width,
               "sticky row width #{row_display_width(sticky_row)} > budget #{width}: #{inspect(sticky_text)}"

        {_y_locked, locked_row} = thread_row_elements(positioned, "Locked thread")
        locked_text = row_text(locked_row)

        assert locked_text =~ locked_glyph,
               "expected locked glyph in locked row at #{width}x#{height}, got: #{inspect(locked_text)}"

        assert locked_text =~ "@alice"
        assert row_display_width(locked_row) <= width

        {_y_plain, plain_row} = thread_row_elements(positioned, "Plain thread")
        plain_text = row_text(plain_row)

        refute plain_text =~ "◆", "plain row should not have ◆: #{inspect(plain_text)}"
        refute plain_text =~ "●", "plain row should not have ●: #{inspect(plain_text)}"

        refute plain_text =~ locked_glyph,
               "plain row should not have locked glyph: #{inspect(plain_text)}"

        assert plain_text =~ "@alice"
        assert row_display_width(plain_row) <= width

        for element <- text_elements(positioned) do
          text = Map.fetch!(element, :text)

          assert element.x >= 0
          assert element.y >= 0

          assert element.x + TextWidth.display_width(text) <= width,
                 "element #{inspect(text)} at x=#{element.x} exceeds width #{width}"
        end

        refute sticky_text =~ "[S] "
        refute locked_text =~ "[S] "
        refute plain_text =~ "[S] "
      end
    end

    test "closed board banners sit above threads and suppress compose", %{
      threads: threads
    } do
      size = {80, 24}
      user = %Foglet.Accounts.User{id: "u1", handle: "alice", status: :active, role: :user}

      cases = [
        {%{id: "b1", name: "Archived", slug: "archived", archived: true, postable_by: :members},
         true, "This board is archived. New threads and replies are disabled."},
        {%{id: "b2", name: "Mods", slug: "mods", archived: false, postable_by: :mods_only}, true,
         "This board is read-only."},
        {%{id: "b3", name: "Open", slug: "open", archived: false}, false,
         "You're not subscribed to this board. Press S on Boards to subscribe."}
      ]

      for {board, subscribed?, banner} <- cases do
        state =
          ThreadList.State.new(
            board: board,
            board_id: board.id,
            subscribed?: subscribed?,
            threads: threads,
            selected_index: 0,
            status: :loaded
          )

        tree =
          ThreadList.render(
            state,
            screen_context(:thread_list, user, size, %{board: board, board_id: board.id})
          )

        positioned = apply_at_size(tree, size)
        texts = content_text_elements(positioned)
        banner_element = Enum.find(texts, &(&1.text == banner))
        {first_thread_y, _row} = thread_row_elements(positioned, "Sticky")

        assert %{y: banner_y} = banner_element
        assert banner_y < first_thread_y
        refute bottom_row_text(positioned) =~ "C Compose"

        assert {^state, []} =
                 ThreadList.update(
                   {:key, %{key: :char, char: "C"}},
                   state,
                   screen_context(:thread_list, user, size)
                 )
      end
    end
  end

  describe "board_list — size contract" do
    setup do
      # Timestamps built at runtime to avoid wall-clock drift on slow CI runs.
      long_name = String.duplicate("a", 80)
      ten_min_ago = DateTime.add(DateTime.utc_now(), -600, :second)
      two_h_ago = DateTime.add(DateTime.utc_now(), -7200, :second)

      directory = [
        %{
          category: %{id: "c1", name: "Public"},
          boards: [
            %{
              board: %{id: "b1", name: long_name, slug: "long"},
              subscribed?: true,
              required_subscription?: true,
              unread_count: 7,
              last_post_at: ten_min_ago
            },
            %{
              board: %{id: "b2", name: "Subscribed Board", slug: "subscribed"},
              subscribed?: true,
              required_subscription?: false,
              unread_count: 0,
              last_post_at: two_h_ago
            },
            %{
              board: %{id: "b3", name: "Available Board", slug: "available"},
              subscribed?: false,
              required_subscription?: false,
              unread_count: nil,
              last_post_at: nil
            }
          ]
        }
      ]

      user = %{handle: "carol", id: "u2", status: :active, role: :user}
      %{directory: directory, long_name: long_name, user: user}
    end

    defp board_list_row_elements(positioned, title_substring) do
      elements = text_elements(positioned)

      anchor =
        Enum.find(elements, fn el ->
          text = Map.get(el, :text, "")
          is_binary(text) and String.contains?(text, title_substring)
        end)

      case anchor do
        nil ->
          flunk(
            "could not find a board row containing #{inspect(title_substring)} " <>
              "in positioned render. text_elements=#{inspect(Enum.map(elements, & &1.text))}"
          )

        %{y: y} ->
          elements
          |> Enum.filter(fn el -> el.y == y end)
          |> Enum.sort_by(& &1.x)
      end
    end

    defp board_list_row_text(elements) do
      Enum.map_join(elements, &Map.get(&1, :text, ""))
    end

    defp assert_board_list_no_row_overlap!(elements, size, label) do
      elements
      |> Enum.reject(&chrome_frame_element?/1)
      |> Enum.group_by(& &1.y)
      |> Enum.each(fn {_y, row_elements} ->
        row_elements
        |> Enum.sort_by(& &1.x)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [previous, current] ->
          previous_end = previous.x + TextWidth.display_width(previous.text)

          assert previous_end <= current.x,
                 "#{label} overlapping text at #{inspect(size)}: #{inspect(previous.text)} " <>
                   "ends at #{previous_end}, #{inspect(current.text)} starts at #{current.x}"
        end)
      end)
    end

    defp overlarge_board_directory(count) do
      boards =
        for index <- 1..count do
          %{
            board: %{
              id: "overlarge-#{index}",
              name: "Overlarge Board #{String.pad_leading(Integer.to_string(index), 2, "0")}",
              slug: "overlarge-#{index}"
            },
            subscribed?: true,
            required_subscription?: false,
            unread_count: rem(index, 6),
            last_post_at: DateTime.add(DateTime.utc_now(), -600, :second)
          }
        end

      [%{category: %{id: "overlarge", name: "Overlarge"}, boards: boards}]
    end

    # FOG-105: BoardList parks the initial cursor on the first board.
    # Tests that need the cursor parked on the parent category use this
    # helper to walk it back up `n` rows.
    defp walk_cursor_up(board_tree, n) do
      Enum.reduce(1..n, board_tree, fn _index, acc ->
        {next, _action} = BoardTree.handle_event(%{key: :up}, acc)
        next
      end)
    end

    for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
      @width width
      @height height
      @tag :"board_list — size contract"
      test "at #{width}x#{height} cluster cells, unread, age stay visible and rows do not overlap",
           %{directory: directory, long_name: long_name, user: user} do
        width = @width
        height = @height
        size = {width, height}

        state =
          BoardList.State.new(
            directory: directory,
            board_tree: BoardTree.init(directory: directory, id: "board-directory"),
            status: :loaded
          )

        positioned =
          state
          |> BoardList.render(screen_context(:board_list, user, size))
          |> apply_at_size(size)

        elements = text_elements(positioned)
        flat = Enum.map_join(elements, "", & &1.text)

        assert flat =~ "⚿"
        assert flat =~ "✓"
        assert flat =~ "+"
        assert flat =~ "◆"
        assert flat =~ "7 unread"
        assert flat =~ ~r/\d+(s|m|h|d|w|mo|y)\b/
        assert flat =~ "—"

        long_prefix = String.slice(long_name, 0, 12)
        long_row = board_list_row_elements(positioned, long_prefix)
        long_text = board_list_row_text(long_row)

        assert long_text =~ "⚿"
        assert long_text =~ "◆"
        assert long_text =~ "7 unread"
        assert long_text =~ ~r/\d+m\b/

        if width <= 80 do
          assert long_text =~ "…",
                 "expected long board name truncation at #{inspect(size)}, got: #{inspect(long_text)}"
        end

        subscribed_row = board_list_row_elements(positioned, "Subscribed Board")
        subscribed_text = board_list_row_text(subscribed_row)

        assert subscribed_text =~ "✓"
        assert subscribed_text =~ "all read"
        assert subscribed_text =~ ~r/\d+h\b/

        available_row = board_list_row_elements(positioned, "Available Board")
        available_text = board_list_row_text(available_row)

        assert available_text =~ "+"
        assert available_text =~ "—"

        for element <- elements do
          text = Map.fetch!(element, :text)

          assert element.x >= 0
          assert element.y >= 0
          assert element.x + TextWidth.display_width(text) <= width
          assert element.y < height
        end

        elements
        |> Enum.filter(fn el ->
          row_text = Map.get(el, :text, "")

          Enum.any?(
            [long_prefix, "Subscribed Board", "Available Board", "⚿", "✓", "+", "◆"],
            &String.contains?(row_text, &1)
          )
        end)
        |> assert_board_list_no_row_overlap!(size, "BoardList.render")
      end
    end

    test "at 64x22 overlarge directories stay inside frame height and width", %{user: user} do
      width = 64
      height = 22
      size = {width, height}

      directory = overlarge_board_directory(30)

      state =
        BoardList.State.new(
          directory: directory,
          board_tree: BoardTree.init(directory: directory, id: "board-directory"),
          status: :loaded
        )

      positioned =
        state
        |> BoardList.render(screen_context(:board_list, user, size))
        |> apply_at_size(size)

      elements = text_elements(positioned)
      flat = Enum.map_join(elements, "", & &1.text)

      visible_board_rows =
        Regex.scan(~r/Overlarge Board \d+/, flat)
        |> length()

      assert flat =~ "Overlarge"
      assert flat =~ "Overlarge Board 01"
      assert visible_board_rows >= 8
      refute flat =~ "Overlarge Board 30"

      for element <- elements do
        text = Map.fetch!(element, :text)

        assert element.x >= 0
        assert element.y >= 0
        assert element.y < height
        assert element.x + TextWidth.display_width(text) <= width
        assert TextWidth.display_width(text) <= 60
      end
    end

    test "at 64x22 the details strip occupies the last screen-body row and no inspector strip renders",
         %{
           user: user
         } do
      width = 64
      height = 22
      size = {width, height}

      directory = overlarge_board_directory(30)

      # FOG-105: BoardList parks the initial cursor on the first board
      # (Overlarge Board 01) so the detail strip reflects board details
      # by default. This test pins the strip to the category-summary
      # branch by walking the cursor back up to the parent category
      # before rendering — the y-position contract is what's under test.
      ctx = screen_context(:board_list, user, size)

      board_tree =
        BoardTree.init(directory: directory, id: "board-directory")
        |> walk_cursor_up(1)

      state =
        BoardList.State.new(
          directory: directory,
          board_tree: board_tree,
          status: :loaded
        )

      positioned =
        state
        |> BoardList.render(ctx)
        |> apply_at_size(size)

      elements = text_elements(positioned)

      detail_row =
        Enum.find(elements, fn element ->
          String.contains?(Map.get(element, :text, ""), "Overlarge • 30 boards •")
        end)

      assert detail_row, "expected category details strip in board list render"
      assert detail_row.y == height - 4

      refute Enum.any?(elements, fn element ->
               String.contains?(Map.get(element, :text, ""), "Inspector •")
             end)
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 23 — Composer size contracts (COMPOSER-01/02/03/04/05)
  # ---------------------------------------------------------------------------

  describe "composer — size contract" do
    @composer_sizes [{64, 22}, {80, 24}, {132, 50}]

    defp composer_user do
      %Foglet.Accounts.User{id: "u1", handle: "alice"}
    end

    defp reply_post do
      %{
        id: "p1",
        body:
          "Quoted reply context that can safely collapse at the minimum terminal size\nsecond quoted line",
        user: %{handle: "reader"}
      }
    end

    defp post_composer_state(width, height, mode) do
      board = %{id: "b1", name: "General"}
      thread = %{id: "t1", title: "Composer Contract", board_id: "b1"}

      %App{
        current_screen: :post_composer,
        current_user: composer_user(),
        route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id},
        session_context: %{theme: Foglet.TUI.Theme.default(), max_post_length: 1_000},
        terminal_size: {width, height},
        screen_state: %{
          post_composer:
            PostComposer.State.new(
              board: board,
              board_id: board.id,
              thread: thread,
              thread_id: thread.id,
              mode: mode,
              reply_to: reply_post(),
              value: "reply body smoke text",
              width: max(width - 4, 20),
              height: 10
            )
        }
      }
      |> Map.from_struct()
    end

    defp new_thread_state(width, height, mode) do
      board = %{id: "b1", name: "General"}

      %App{
        current_screen: :new_thread,
        current_user: composer_user(),
        route_params: %{board: board, board_id: board.id},
        session_context: %{theme: Foglet.TUI.Theme.default(), max_post_length: 1_000},
        terminal_size: {width, height},
        screen_state: %{
          new_thread:
            NewThread.State.new(
              step: :compose,
              board: board,
              boards: [board],
              title_value: "Smoke Title",
              body_value: "opening body smoke text",
              focused: :body,
              mode: mode,
              width: max(width - 4, 20),
              height: 10
            )
        }
      }
      |> Map.from_struct()
    end

    defp positioned_text(positioned) do
      positioned
      |> text_elements()
      |> Enum.sort_by(fn element -> {element.y, element.x} end)
    end

    defp joined_positioned_text(elements) do
      Enum.map_join(elements, "", & &1.text)
    end

    defp composer_content_elements(elements) do
      elements
      |> Enum.reject(fn element ->
        element.y == 0 or String.contains?(element.text, "Foglet")
      end)
    end

    defp assert_positioned_text_fits!(elements, {width, height}, label) do
      assert elements != [],
             "expected #{label} positioned text elements at #{inspect({width, height})}"

      for element <- elements do
        text = Map.fetch!(element, :text)

        assert element.x >= 0,
               "#{label} has negative x at #{inspect({width, height})}: #{inspect(element)}"

        assert element.y >= 0,
               "#{label} has negative y at #{inspect({width, height})}: #{inspect(element)}"

        assert element.x + TextWidth.display_width(text) <= width,
               "#{label} overflows width at #{inspect({width, height})}: #{inspect(element)}"

        assert element.y < height,
               "#{label} overflows height at #{inspect({width, height})}: #{inspect(element)}"
      end
    end

    defp assert_no_same_row_overlap!(elements, size, label) do
      elements
      |> Enum.reject(&chrome_frame_element?/1)
      |> Enum.group_by(& &1.y)
      |> Enum.each(fn {_y, row_elements} ->
        row_elements
        |> Enum.sort_by(& &1.x)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [previous, current] ->
          previous_end = previous.x + TextWidth.display_width(previous.text)

          assert previous_end <= current.x,
                 "#{label} overlapping text at #{inspect(size)}: #{inspect(previous.text)} " <>
                   "ends at #{previous_end}, #{inspect(current.text)} starts at #{current.x}"
        end)
      end)
    end

    test "post composer keeps mode controls, content, and body budget visible" do
      for {width, height} <- @composer_sizes, mode <- [:edit, :preview] do
        size = {width, height}

        elements =
          PostComposer.render(
            width
            |> post_composer_state(height, mode)
            |> Map.fetch!(:screen_state)
            |> Map.fetch!(:post_composer),
            screen_context(:post_composer, composer_user(), size)
          )
          |> apply_at_size(size)
          |> positioned_text()

        flat = joined_positioned_text(elements)

        assert flat =~ "Composer"
        assert flat =~ "Edit"
        assert flat =~ "Preview"
        assert flat =~ "/"
        assert flat =~ "reply body smoke text"

        assert_positioned_text_fits!(elements, size, "PostComposer.render #{mode}")

        elements
        |> composer_content_elements()
        |> assert_no_same_row_overlap!(size, "PostComposer.render #{mode}")
      end
    end

    test "new thread compose keeps title, mode controls, content, and budgets visible" do
      for {width, height} <- @composer_sizes, mode <- [:edit, :preview] do
        size = {width, height}

        elements =
          NewThread.render(
            width
            |> new_thread_state(height, mode)
            |> Map.fetch!(:screen_state)
            |> Map.fetch!(:new_thread),
            screen_context(:new_thread, composer_user(), size)
          )
          |> apply_at_size(size)
          |> positioned_text()

        flat = joined_positioned_text(elements)

        assert flat =~ "Composer"
        assert flat =~ "Edit"
        assert flat =~ "Preview"
        assert flat =~ "Title"
        assert flat =~ "60 chars"
        assert flat =~ "opening body smoke text"

        assert_positioned_text_fits!(elements, size, "NewThread.render #{mode}")

        elements
        |> composer_content_elements()
        |> assert_no_same_row_overlap!(size, "NewThread.render #{mode}")
      end
    end
  end

  describe "command bar — minimum width primary hints" do
    test "primary board, thread, reader, and composer actions survive at 64x22" do
      size = {64, 22}

      expectations = [
        {:board_list, ["Q Back", "Enter Open"]},
        {:thread_list, ["Q Back", "C Compose"]},
        {:post_reader, ["Q Back", "R Reply"]},
        {:new_thread, ["Ctrl+S Post", "Ctrl+C Cancel"]},
        {:post_composer, ["Ctrl+S Post", "Ctrl+C Cancel"]}
      ]

      for {screen, expected_hints} <- expectations do
        command_row =
          screen
          |> RenderFixtures.state_for(size)
          |> App.view()
          |> apply_at_size(size)
          |> bottom_row_text()

        for hint <- expected_hints do
          assert command_row =~ hint,
                 "expected #{inspect(screen)} command row at 64x22 to include #{inspect(hint)}, " <>
                   "got: #{inspect(command_row)}"
        end

        assert TextWidth.display_width(command_row) <= elem(size, 0),
               "#{inspect(screen)} command row exceeds 64 columns: #{inspect(command_row)}"
      end
    end

    test "archived thread_list fixture renders banner and suppresses compose" do
      size = {80, 24}

      positioned =
        :thread_list
        |> RenderFixtures.state_for(size, substate: :archived)
        |> App.view()
        |> apply_at_size(size)

      rows = text_rows(text_elements(positioned))

      assert Enum.any?(rows, fn {_y, row} ->
               String.contains?(
                 row,
                 "This board is archived. New threads and replies are disabled."
               )
             end)

      refute bottom_row_text(positioned) =~ "C Compose"
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 22 — PostReader size contracts (READER-01/02/03/04)
  # ---------------------------------------------------------------------------

  describe "Phase 22 PostReader size contracts" do
    defp phase_22_long_unbroken_body do
      "SelectedBodyNoBreak" <> String.duplicate("X", 100)
    end

    defp phase_22_long_handle do
      "mina-" <> String.duplicate("readerhandle", 12)
    end

    defp phase_22_posts do
      Enum.map(31..42, fn message_number ->
        body =
          if message_number == 33 do
            "Selected body sentinel\n\n#{phase_22_long_unbroken_body()}\n\nMore content here."
          else
            "Body text for message #{message_number}."
          end

        %{
          id: "p#{message_number}",
          body: body,
          inserted_at: ~U[2026-04-24 18:00:00Z],
          message_number: message_number,
          user: %{handle: if(message_number == 33, do: phase_22_long_handle(), else: "mina")}
        }
      end)
    end

    defp phase_22_state(width, height) do
      board = %{id: "b1", name: "General"}
      thread = %{id: "t1", title: "Reader Contract"}

      %Foglet.TUI.App{
        current_screen: :post_reader,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "reader"},
        route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id},
        screen_state: %{
          post_reader:
            PostReader.State.new(
              board: board,
              board_id: board.id,
              thread: thread,
              thread_id: thread.id,
              posts: phase_22_posts(),
              status: :loaded,
              selected_post_index: 2
            )
        },
        session_context: %{theme: Foglet.TUI.Theme.default()},
        terminal_size: {width, height}
      }
      |> Map.from_struct()
    end

    defp phase_22_text_element!(elements, text, size) do
      Enum.find(elements, &String.contains?(&1.text, text)) ||
        flunk("expected #{inspect(text)} in positioned PostReader text at #{inspect(size)}")
    end

    defp assert_no_phase_22_overlap!(elements, size) do
      elements
      |> Enum.reject(&chrome_frame_element?/1)
      |> Enum.group_by(& &1.y)
      |> Enum.each(fn {_y, row_elements} ->
        row_elements
        |> Enum.sort_by(& &1.x)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [previous, current] ->
          previous_end = previous.x + TextWidth.display_width(previous.text)

          assert previous_end <= current.x,
                 "overlapping text at #{inspect(size)}: #{inspect(previous.text)} ends at #{previous_end}, " <>
                   "#{inspect(current.text)} starts at #{current.x}"
        end)
      end)
    end

    test "post reader renders compact metadata, progress, body gutter, and commands at required sizes" do
      for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
        size = {width, height}

        app_state = phase_22_state(width, height)
        local_state = app_state.screen_state.post_reader

        context =
          screen_context(:post_reader, app_state.current_user, size, app_state.route_params)

        positioned =
          local_state
          |> PostReader.render(context)
          |> apply_at_size(size)

        elements = text_elements(positioned)

        assert elements != [],
               "expected positioned PostReader text elements at #{inspect(size)}"

        for element <- elements do
          text = Map.fetch!(element, :text)

          assert element.x >= 0,
                 "negative x at #{inspect(size)}: #{inspect(element)}"

          assert element.y >= 0,
                 "negative y at #{inspect(size)}: #{inspect(element)}"

          assert element.x + TextWidth.display_width(text) <= width,
                 "element overflows width at #{inspect(size)}: #{inspect(element)}"
        end

        flat = Enum.map_join(elements, "", & &1.text)

        assert flat =~ "Post 3 of 12"
        assert flat =~ "#33"
        assert flat =~ "@mina"
        assert flat =~ "Posts 3/12"
        assert flat =~ "Selected body sentinel"
        assert flat =~ String.slice(phase_22_long_unbroken_body(), 0, 20)
        assert flat =~ "│" or flat =~ "|"

        header = phase_22_text_element!(elements, "Post 3 of 12", size)
        progress = phase_22_text_element!(elements, "Posts 3/12", size)
        body = phase_22_text_element!(elements, "Selected body sentinel", size)

        long_body =
          phase_22_text_element!(
            elements,
            String.slice(phase_22_long_unbroken_body(), 0, 20),
            size
          )

        assert long_body.x + TextWidth.display_width(long_body.text) <= width,
               "long selected body text overflows at #{inspect(size)}: #{inspect(long_body)}"

        command_elements =
          Enum.filter(elements, fn element ->
            String.contains?(element.text, "Next") or String.contains?(element.text, "Prev") or
              String.contains?(element.text, "Back")
          end)

        assert command_elements != [],
               "expected command bar text containing Next, Prev, or Back at #{inspect(size)}"

        command_y =
          command_elements
          |> Enum.map(& &1.y)
          |> Enum.max()

        assert Enum.any?(command_elements, &(&1.y == command_y)),
               "expected command text on bottom-most occupied command row at #{inspect(size)}"

        assert header.y < body.y
        assert header.y < progress.y
        assert progress.y < command_y

        assert_no_phase_22_overlap!(elements, size)
      end
    end

    test "post_reader archived fixture renders the reply-closed banner and keybar state" do
      size = {80, 24}

      positioned =
        :post_reader
        |> RenderFixtures.state_for(size, substate: :archived)
        |> App.view()
        |> apply_at_size(size)

      rows = positioned |> content_text_elements() |> text_rows()

      {banner_y, _banner_text} =
        Enum.find(rows, fn {_y, row} ->
          String.contains?(row, "Archived board — replies are closed.")
        end)

      {post_y, _post_text} =
        Enum.find(rows, fn {_y, row} ->
          String.contains?(row, "Post 1 of")
        end)

      command_row = bottom_row_text(positioned)

      assert banner_y < post_y
      assert command_row =~ "R Reply (archived)"
      refute command_row =~ "R Reply (locked)"
      assert TextWidth.display_width(command_row) <= elem(size, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 16 size contracts
  # ---------------------------------------------------------------------------

  test "phase 16 representative row, modal, and compose paths fit terminal widths" do
    theme = Foglet.TUI.Theme.default()

    for {width, _height} <- @phase_16_dimensions do
      row =
        ListRow.render_with_metadata(
          "● ◆ ▸ ▾ ✓ × cafe\u0301 漢字 thread title with trailing detail",
          "@alice · ✓ subscribed",
          false,
          true,
          theme,
          width: width
        )
        |> flatten_text()

      assert row =~ "●"
      assert row =~ "@alice"
      assert_line_within_width!("ListRow #{width}", row, width)

      modal_lines =
        %Foglet.TUI.Modal{
          type: :info,
          message: "Unicode modal ● ◆ ▸ ▾ ✓ × cafe\u0301 漢字 stays inside wrapped display columns"
        }
        |> Modal.render(theme)
        |> collect_text()
        |> Enum.reject(fn text ->
          String.trim(text) in ["Info", "[Enter] OK"] or text == ""
        end)

      assert Enum.any?(modal_lines, &String.contains?(&1, "Unicode"))

      for line <- modal_lines do
        assert_line_within_width!("Modal #{width}", line, width)
      end

      compose =
        "● ◆ ▸ ▾ ✓ × cafe\u0301 漢字"
        |> unicode_compose_input({0, 6}, width)
        |> Compose.render_input(true, theme)
        |> flatten_text()

      assert compose =~ "█"
      assert compose =~ "●"
      assert_line_within_width!("Compose #{width}", compose, width)
    end
  end

  # ---------------------------------------------------------------------------
  # Login screen — menu sub-state
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Login screen — login form sub-state
  # ---------------------------------------------------------------------------

  test "login form renders handle and password fields at distinct y positions" do
    alias Foglet.TUI.Widgets.Input.TextInput, as: TI

    state = %App{
      screen_state: %{
        login: %{
          sub: :login_form,
          focused_field: :handle,
          handle_input: TI.init(value: "alice"),
          password_input: TI.init(value: "", mask_char: "*"),
          error: nil
        }
      },
      terminal_size: {80, 24}
    }

    tree = render_login(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Handle")),
           "expected 'Handle:' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Password")),
           "expected 'Password:' text, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 2,
           "expected at least 2 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
  end

  # ---------------------------------------------------------------------------
  # Main menu screen
  # ---------------------------------------------------------------------------

  test "main_menu renders Navigation and Oneliners panels at distinct y positions" do
    # Phase 19 / REVIEWS.md HIGH: use canonical `:user` role atom (was `:member`).
    user = %{handle: "bob", id: "u1", status: :active, role: :user}

    state =
      %App{current_user: user, screen_state: %{}, terminal_size: {80, 24}}
      |> Map.from_struct()
      |> Map.put(:recent_oneliners, [%{body: "hello", user: %{handle: "alice"}}])

    tree = render_main_menu(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    # D-11: no Welcome line.
    refute Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "Phase 19 D-11 removes the welcome line; got: #{inspect(texts)}"

    # Phase 32 / MENU-01: panel titles are embedded in the box top border via
    # Raxol's `:panel` element type. Panels.process emits the title as a
    # positioned :text element with text " Navigation " / " Oneliners "
    # (with surrounding spaces, see vendor/raxol panels.ex create_title_element).
    assert Enum.any?(texts, &(&1 == " Navigation ")),
           "expected embedded ' Navigation ' title (Panels.process overlay), got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == " Oneliners ")),
           "expected embedded ' Oneliners ' title (Panels.process overlay), got: #{inspect(texts)}"

    # Phase 32 / MENU-01: no bare 'Navigation'/'Oneliners' body-row title remains.
    refute Enum.any?(texts, &(&1 == "Navigation")),
           "Phase 32 MENU-01 removes the body-row 'Navigation' title; got: #{inspect(texts)}"

    refute Enum.any?(texts, &(&1 == "Oneliners")),
           "Phase 32 MENU-01 removes the body-row 'Oneliners' title; got: #{inspect(texts)}"

    # Phase 32 / MENU-03: nav rows compose multiple text nodes — primary-color
    # leading segment (glyph + label + right-align padding) and accent-color
    # bracketed-key segment "[X]". Each text node is its own positioned :text
    # element, so the leading segment and bracketed key appear as separate
    # entries in `texts`.
    assert Enum.any?(texts, &(&1 =~ ~r/●\s+Boards/)),
           "expected '● Boards ...' leading segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "[B]")),
           "expected '[B]' bracketed-key segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/↯\s+Logout/)),
           "expected '↯ Logout ...' leading segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "[Q]")),
           "expected '[Q]' bracketed-key segment, got: #{inspect(texts)}"

    # Existing oneliner row format unchanged.
    assert Enum.any?(texts, &String.contains?(&1, "@alice  hello")),
           "expected '@alice  hello' row, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 3,
           "expected at least 3 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
  end

  test "main_menu clips Unicode oneliners to display-width limits" do
    # Phase 19 / REVIEWS.md HIGH: use canonical `:user` role atom (was `:member`).
    user = %{handle: "bob", id: "u1", status: :active, role: :user}

    state =
      %App{current_user: user, screen_state: %{}, terminal_size: {80, 24}}
      |> Map.from_struct()
      |> Map.put(:recent_oneliners, [
        %{
          body: "● ◆ ▸ ▾ ✓ × 漢字漢字漢字漢字漢字漢字 trailing text",
          user: %{handle: "漢字漢字漢字漢字漢字漢字"}
        }
      ])

    tree = render_main_menu(state)
    positioned = layout(tree)

    row =
      positioned
      |> text_elements()
      |> Enum.map(& &1.text)
      |> Enum.find(&String.contains?(&1, "@漢字"))

    assert row, "expected Unicode oneliner row in positioned text"
    assert row =~ "●"
    assert TextWidth.display_width(row) <= 39
  end

  # ---------------------------------------------------------------------------
  # Phase 19 Main Menu size contracts (D-13, D-16)
  # ---------------------------------------------------------------------------

  describe "Phase 19 Main Menu size contracts" do
    test "main menu renders Navigation + Oneliners side-by-side without overlap at 64x22, 80x24, 132x50" do
      # Phase 19 / REVIEWS.md HIGH: canonical `role: :user` (was `:member`).
      user = %{
        id: "u1",
        handle: "alice",
        role: :user,
        status: :active,
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"}
      }

      for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
        state =
          %App{current_user: user, screen_state: %{}, terminal_size: {width, height}}
          |> Map.from_struct()
          |> Map.put(:session_context, %{clock_now: ~U[2026-04-24 18:05:00Z]})
          |> Map.put(:recent_oneliners, [
            %{body: "deploy notes are up", user: %{handle: "bea"}},
            %{body: "maintenance at 23:00", user: %{handle: "sys"}},
            %{body: "welcome new callers", user: %{handle: "mina"}}
          ])

        positioned =
          render_main_menu(state) |> apply_at_size({width, height})

        elements = text_elements(positioned)

        assert elements != [],
               "expected positioned text elements at #{inspect({width, height})}"

        # ── Viewport-bound: every element fits inside {width, height}. ──────
        for element <- elements do
          text = Map.fetch!(element, :text)

          assert element.x >= 0,
                 "negative x at #{inspect({width, height})}: #{inspect(element)}"

          assert element.y >= 0,
                 "negative y at #{inspect({width, height})}: #{inspect(element)}"

          assert element.x + TextWidth.display_width(text) <= width,
                 "element overflows width at #{inspect({width, height})}: #{inspect(element)}"
        end

        # ── Both panels present (split_pane has NOT collapsed/stacked). ─────
        # Phase 32 / MENU-01: panel titles are embedded in the box top border
        # via Raxol's `:panel` element type. Panels.process emits the title as
        # a positioned :text element with text " Navigation " / " Oneliners "
        # (with surrounding spaces, per panels.ex create_title_element).
        nav_header =
          Enum.find(elements, fn element -> element.text == " Navigation " end)

        oneliners_header =
          Enum.find(elements, fn element -> element.text == " Oneliners " end)

        assert nav_header,
               "expected ' Navigation ' embedded title at #{inspect({width, height})}; got: #{inspect(Enum.map(elements, & &1.text))}"

        assert oneliners_header,
               "expected ' Oneliners ' embedded title at #{inspect({width, height})}; got: #{inspect(Enum.map(elements, & &1.text))}"

        # ── Side-by-side: Navigation header LEFT of Oneliners header. ───────
        assert nav_header.x < oneliners_header.x,
               "expected Navigation.x (#{nav_header.x}) < Oneliners.x (#{oneliners_header.x}) at #{inspect({width, height})}"

        # ── Range overlap: per-y, sorted-by-x adjacent pairs do not overlap.
        #    REPLACES the prior identical-`{x, y}` check, which only caught
        #    elements starting at the same column. Range overlap catches
        #    elements whose display-width spans collide on the same y.
        elements_by_y =
          elements
          |> Enum.reject(&chrome_frame_element?/1)
          |> Enum.group_by(& &1.y)

        for {y, row_elements} <- elements_by_y do
          sorted = Enum.sort_by(row_elements, & &1.x)

          sorted
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.each(fn [prev, next] ->
            prev_right = prev.x + TextWidth.display_width(prev.text)

            assert prev_right <= next.x,
                   "elements overlap on y=#{y} at #{inspect({width, height})}: " <>
                     "prev=#{inspect(prev)} (right edge x=#{prev_right}) collides with " <>
                     "next=#{inspect(next)} (starts x=#{next.x})"
          end)
        end

        # ── Oneliner rows live inside the right (Oneliners) panel. ─────────
        #    Anchor: every oneliner row's `x` must be >= the Oneliners
        #    header's `x`. Catches stacking, panel collapse, AND any
        #    bleed of oneliner rows into the Navigation panel's column range.
        oneliner_rows =
          Enum.filter(elements, fn element ->
            String.starts_with?(element.text, "> @")
          end)

        # Phase 32 / MENU-01: the embedded title " Oneliners " sits at
        # x = panel_content_x + 1 (the title overlay is offset one column from
        # the panel's content-area left edge, see vendor/raxol panels.ex
        # create_title_element). Body-row content starts at panel_content_x,
        # which is `oneliners_header.x - 1`. We use that as the containment
        # lower bound.
        right_panel_content_left = oneliners_header.x - 1

        for row <- oneliner_rows do
          assert row.x >= right_panel_content_left,
                 "oneliner row bled out of right panel at #{inspect({width, height})}: " <>
                   "row.x=#{row.x} < right_panel_content_left=#{right_panel_content_left}; row=#{inspect(row)}"

          row_right = row.x + TextWidth.display_width(row.text) - 1
          right_panel_right_inner = width - 2

          assert row_right <= right_panel_right_inner,
                 "oneliner row overran right panel inner border at #{inspect({width, height})}: " <>
                   "row_right=#{row_right} > right_panel_right_inner=#{right_panel_right_inner}; row=#{inspect(row)}"
        end
      end
    end

    test "long-Unicode (CJK + combining-mark) oneliner rows clipped to fit inside the right panel at 64x22" do
      # Phase 19 / REVIEWS.md MEDIUM: real CJK + combining marks, not
      # ASCII repeated text. Exercises the Phase 16 TextWidth.display_width/1
      # guarantee the prior ASCII-only fixture did not.
      user = %{
        id: "u1",
        handle: "alice",
        role: :user,
        status: :active,
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"}
      }

      # CJK ideographs (each is double-width per TextWidth) + combining acute on `e`.
      cjk_segment = String.duplicate("界", 20)
      combining_segment = "café noir café noir"
      long_body = cjk_segment <> " " <> combining_segment
      long_handle = "alice" <> String.duplicate("界", 5)

      state =
        %App{current_user: user, screen_state: %{}, terminal_size: {64, 22}}
        |> Map.from_struct()
        |> Map.put(:session_context, %{clock_now: ~U[2026-04-24 18:05:00Z]})
        |> Map.put(:recent_oneliners, [
          %{body: long_body, user: %{handle: long_handle}}
        ])

      positioned = render_main_menu(state) |> apply_at_size({64, 22})
      elements = text_elements(positioned)

      # Every element fits inside 64-col viewport — even with double-width
      # CJK and combining marks, TextWidth.display_width must give the
      # truthful width and clipping must hold.
      for element <- elements do
        text = Map.fetch!(element, :text)

        assert element.x + TextWidth.display_width(text) <= 64,
               "long-Unicode oneliner overflows 64-wide viewport: #{inspect(element)}"
      end

      # Right-panel containment also holds for the CJK fixture.
      # Phase 32 / MENU-01: title is embedded in the box top border as
      # " Oneliners " (with surrounding spaces).
      oneliners_header =
        Enum.find(elements, fn element -> element.text == " Oneliners " end)

      assert oneliners_header,
             "expected ' Oneliners ' embedded title in CJK fixture render"

      oneliner_rows =
        Enum.filter(elements, fn element ->
          String.starts_with?(element.text, "> @")
        end)

      # Phase 32 / MENU-01: title overlay is offset one column right of the
      # content-area left edge (panels.ex create_title_element). Body-row
      # content starts at `oneliners_header.x - 1`.
      right_panel_content_left = oneliners_header.x - 1

      for row <- oneliner_rows do
        assert row.x >= right_panel_content_left,
               "CJK oneliner row bled out of right panel: row.x=#{row.x} < right_panel_content_left=#{right_panel_content_left}; row=#{inspect(row)}"

        row_right = row.x + TextWidth.display_width(row.text) - 1
        right_panel_right_inner = 64 - 2

        assert row_right <= right_panel_right_inner,
               "CJK oneliner row overran right panel inner border: " <>
                 "row_right=#{row_right} > right_panel_right_inner=#{right_panel_right_inner}; row=#{inspect(row)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Board list screen
  # ---------------------------------------------------------------------------

  test "board_list renders board rows at distinct y positions" do
    board_list = [
      %{
        category: %{id: "c1", name: "Public"},
        boards: [
          %{
            board: %{id: "b1", name: "General"},
            subscribed?: true,
            required_subscription?: false,
            unread_count: 3,
            last_post_at: DateTime.add(DateTime.utc_now(), -600, :second)
          },
          %{
            board: %{id: "b2", name: "Announcements"},
            subscribed?: false,
            required_subscription?: false,
            unread_count: 0,
            last_post_at: nil
          },
          %{
            board: %{id: "b3", name: "Off-topic"},
            subscribed?: true,
            required_subscription?: false,
            unread_count: 1,
            last_post_at: DateTime.add(DateTime.utc_now(), -3600, :second)
          }
        ]
      }
    ]

    user = %{handle: "carol", id: "u2", status: :active, role: :member}

    state =
      BoardList.State.new(
        directory: board_list,
        board_tree: BoardTree.init(directory: board_list, id: "board-directory"),
        status: :loaded
      )

    tree = BoardList.render(state, screen_context(:board_list, user, {80, 24}))
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "General")),
           "expected 'General' board name, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Announcements")),
           "expected 'Announcements' board name, got: #{inspect(texts)}"

    board_ys =
      elements
      |> Enum.filter(fn el ->
        Enum.any?(["General", "Announcements", "Off-topic"], &String.contains?(el.text, &1))
      end)
      |> Enum.map(& &1.y)
      |> Enum.uniq()

    assert length(board_ys) >= 2,
           "expected board rows at distinct y positions, got: #{inspect(board_ys)}"
  end

  # ---------------------------------------------------------------------------
  # Post reader screen
  # ---------------------------------------------------------------------------

  test "post_reader renders post content at distinct y positions" do
    thread = %{
      id: "t1",
      title: "Hello World",
      sticky: false,
      last_post_at: DateTime.utc_now()
    }

    posts = [
      %{
        id: "p1",
        body: "First post body here",
        inserted_at: DateTime.utc_now(),
        message_number: 1,
        user: %{handle: "dave"}
      },
      %{
        id: "p2",
        body: "Second post body here",
        inserted_at: DateTime.utc_now(),
        message_number: 2,
        user: %{handle: "eve"}
      }
    ]

    user = %{handle: "frank", id: "u3", status: :active, role: :member}

    context =
      screen_context(:post_reader, user, {80, 24}, %{thread: thread, thread_id: thread.id})

    state =
      PostReader.State.new(
        thread: thread,
        thread_id: thread.id,
        posts: posts,
        status: :loaded
      )

    tree = PostReader.render(state, context)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Post 1 of 2")),
           "expected 'Post 1 of 2', got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "dave")),
           "expected author 'dave', got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "First post body")),
           "expected post body, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 3,
           "expected at least 3 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
  end

  test "post_reader positions distinct empty-thread and end-of-thread guidance" do
    thread = %{id: "t1", title: "Reader Boundary"}
    user = %{handle: "frank", id: "u3", status: :active, role: :member}
    size = {80, 24}
    context = screen_context(:post_reader, user, size, %{thread: thread, thread_id: thread.id})

    empty_positioned =
      PostReader.State.new(thread: thread, thread_id: thread.id, posts: [], status: :empty)
      |> PostReader.render(context)
      |> apply_at_size(size)

    end_positioned =
      PostReader.State.new(
        thread: thread,
        thread_id: thread.id,
        posts: [
          %{
            id: "p1",
            body: "First post body here",
            inserted_at: DateTime.utc_now(),
            message_number: 1,
            user: %{handle: "dave"}
          }
        ],
        status: :loaded,
        selected_post_index: 1
      )
      |> PostReader.render(context)
      |> apply_at_size(size)

    empty_texts = empty_positioned |> content_text_elements() |> Enum.map(& &1.text)
    end_texts = end_positioned |> content_text_elements() |> Enum.map(& &1.text)

    assert "This thread has no readable posts." in empty_texts
    assert "You're at the end of this thread." in end_texts
    refute empty_texts == end_texts
  end

  # ---------------------------------------------------------------------------
  # Login form — plain-text input fix (Bug A)
  # ---------------------------------------------------------------------------

  test "login form with handle='alice' shows 'alice' in rendered text elements" do
    alias Foglet.TUI.Widgets.Input.TextInput, as: TI

    state = %App{
      screen_state: %{
        login: %{
          sub: :login_form,
          focused_field: :handle,
          handle_input: TI.init(value: "alice"),
          password_input: TI.init(value: "", mask_char: "*"),
          error: nil
        }
      },
      terminal_size: {80, 24}
    }

    tree = render_login(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "alice")),
           "expected 'alice' to appear in rendered text, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 2,
           "expected handle and password fields at distinct y positions, got: #{inspect(ys)}"
  end

  # ---------------------------------------------------------------------------
  # Register wizard — plain-text input fix (Bug A)
  # ---------------------------------------------------------------------------

  test "register wizard on :handle step with current_input='bob' shows 'bob'" do
    alias Foglet.TUI.Widgets.Input.TextInput, as: TI

    state = %App{
      current_screen: :register,
      terminal_size: {80, 24},
      screen_state: %{
        register: %{
          mode: "open",
          step: :combined,
          focused_field: :handle,
          invite_code_input: TI.init([]),
          handle_input: TI.init(value: "bob"),
          email_input: TI.init([]),
          password_input: TI.init(mask_char: "*"),
          confirm_input: TI.init(mask_char: "*"),
          collected: %{},
          error: nil
        }
      }
    }

    tree = render_register(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "bob")),
           "expected 'bob' to appear in rendered text, got: #{inspect(texts)}"
  end

  # ---------------------------------------------------------------------------
  # Verify screen — plain-text input fix (Bug A)
  # ---------------------------------------------------------------------------

  test "verify screen with buffer='XK7' shows 'XK7' in the displayed frame" do
    state = %App{
      current_screen: :verify,
      current_user: %{id: "u1", handle: "alice"},
      terminal_size: {80, 24},
      screen_state: %{
        verify: %{
          buffer: "XK7",
          attempts: 0,
          cooldown_until: nil,
          resend_cooldown_until: nil
        }
      }
    }

    tree = render_verify(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "XK7")),
           "expected 'XK7' to appear in rendered text, got: #{inspect(texts)}"
  end

  # ---------------------------------------------------------------------------
  # PostComposer — MultiLineInput.render bypass (Bug B)
  # ---------------------------------------------------------------------------

  test "composer with non-empty input_state.value does not crash and value appears" do
    {:ok, input_st} =
      MultiLineInput.init(%{
        value: "Hello world",
        placeholder: "Write your post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: true
      })

    user = %{id: "u1", handle: "alice"}
    context = screen_context(:post_composer, user, {80, 24}, %{thread_id: "t1"})

    state = PostComposer.State.new(thread_id: "t1", input_state: input_st)

    tree = PostComposer.render(state, context)

    # apply_layout must not raise — this is the primary Bug B assertion
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Hello world")),
           "expected 'Hello world' to appear in rendered text, got: #{inspect(texts)}"
  end

  # ---------------------------------------------------------------------------
  # Modal overlay smoke tests (task #6)
  # ---------------------------------------------------------------------------

  test "with-modal: view/1 with :info modal renders title and message through layout engine" do
    state = %App{
      screen_state: %{},
      terminal_size: {80, 24},
      modal: %Foglet.TUI.Modal{type: :info, message: "Your draft was saved."}
    }

    tree = App.view(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Info")),
           "expected modal title 'Info' in positioned elements, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Your draft was saved.")),
           "expected modal message in positioned elements, got: #{inspect(texts)}"

    # The outer box with border: :double should appear in the flat element list
    box_elements =
      positioned
      |> List.flatten()
      |> Enum.filter(fn el ->
        el.type == :box and
          get_in(el, [:attrs, :border]) == :double
      end)

    assert box_elements != [],
           "expected a :box element with border: :double, got: #{inspect(List.flatten(positioned))}"
  end

  test "with-modal: content is vertically centered (y around terminal mid-point)" do
    h = 24

    state = %App{
      screen_state: %{},
      terminal_size: {80, h},
      modal: %Foglet.TUI.Modal{type: :info, message: "Centered?"}
    }

    tree = App.view(state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    ys = Enum.map(elements, & &1.y)

    # All text elements must be non-negative (no negative y coordinates)
    assert Enum.all?(ys, &(&1 >= 0)),
           "expected all y positions >= 0, got: #{inspect(ys)}"

    # At least one text element should be in the middle half of the terminal
    # (y between h/4 and 3*h/4) — verifying the justify: :center effect
    mid_elements = Enum.filter(elements, fn el -> el.y >= div(h, 4) and el.y <= 3 * div(h, 4) end)

    assert mid_elements != [],
           "expected modal text near vertical centre (rows #{div(h, 4)}..#{3 * div(h, 4)}), " <>
             "got elements at y positions: #{inspect(ys)}"
  end

  # ---------------------------------------------------------------------------
  # Height check — all four screens fit within 24 rows
  # ---------------------------------------------------------------------------

  test "all four screens fit within height=24" do
    {:ok, input_st} =
      MultiLineInput.init(%{
        value: "test body",
        placeholder: "Write your post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: true
      })

    screens = [
      {"login form",
       render_login(%App{
         screen_state: %{
           login: %{
             sub: :login_form,
             focused_field: :handle,
             handle_input: Foglet.TUI.Widgets.Input.TextInput.init(value: "alice"),
             password_input: Foglet.TUI.Widgets.Input.TextInput.init(value: "", mask_char: "*"),
             error: nil
           }
         },
         terminal_size: {80, 24}
       })},
      {"register wizard",
       render_register(%App{
         current_screen: :register,
         terminal_size: {80, 24},
         screen_state: %{
           register: %{
             mode: "open",
             step: :combined,
             focused_field: :handle,
             invite_code_input: Foglet.TUI.Widgets.Input.TextInput.init([]),
             handle_input: Foglet.TUI.Widgets.Input.TextInput.init(value: "bob"),
             email_input: Foglet.TUI.Widgets.Input.TextInput.init([]),
             password_input: Foglet.TUI.Widgets.Input.TextInput.init(mask_char: "*"),
             confirm_input: Foglet.TUI.Widgets.Input.TextInput.init(mask_char: "*"),
             collected: %{},
             error: nil
           }
         }
       })},
      {"verify screen",
       render_verify(%App{
         current_screen: :verify,
         current_user: %{id: "u1", handle: "alice"},
         terminal_size: {80, 24},
         screen_state: %{
           verify: %{
             buffer: "XK7",
             attempts: 0,
             cooldown_until: nil,
             resend_cooldown_until: nil
           }
         }
       })},
      {"composer",
       PostComposer.render(
         PostComposer.State.new(
           input_state: input_st,
           thread: %{id: "t1", title: "Hello"}
         ),
         screen_context(:post_composer, %{id: "u1", handle: "alice"}, {80, 24})
       )}
    ]

    for {name, tree} <- screens do
      positioned = layout(tree)
      elements = text_elements(positioned)

      max_y =
        elements
        |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
        |> Enum.max(fn -> 0 end)

      assert max_y <= 24,
             "#{name}: total height #{max_y} exceeds 24 rows. Elements: #{inspect(elements)}"
    end
  end

  # ---------------------------------------------------------------------------
  # NewThread screen — Audit #9 smoke tests
  # ---------------------------------------------------------------------------

  test "new_thread board step with 2 boards — both board names appear in positioned text" do
    boards = [
      %{id: "b1", name: "General", unread_count: 0},
      %{id: "b2", name: "Announcements", unread_count: 2}
    ]

    ss = NewThread.State.new(boards: boards, width: 80, load_status: :loaded)

    state = %App{
      current_screen: :new_thread,
      current_user: %{id: "u1", handle: "alice"},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{new_thread: ss}
    }

    tree = NewThread.render(ss, screen_context(:new_thread, state.current_user, {80, 24}))
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "General")),
           "expected 'General' board name in positioned text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Announcements")),
           "expected 'Announcements' board name in positioned text, got: #{inspect(texts)}"

    board_ys =
      elements
      |> Enum.filter(fn el ->
        Enum.any?(["General", "Announcements"], &String.contains?(el.text, &1))
      end)
      |> Enum.map(& &1.y)
      |> Enum.uniq()

    assert length(board_ys) >= 2,
           "expected board names at distinct y positions, got: #{inspect(board_ys)}"

    max_y =
      elements
      |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
      |> Enum.max(fn -> 0 end)

    assert max_y <= 24,
           "new_thread board step: total height #{max_y} exceeds 24 rows"
  end

  # ---------------------------------------------------------------------------
  # Phase 0 shell smoke tests
  # ---------------------------------------------------------------------------

  test "account shell renders PROFILE/PREFS tab labels at distinct x positions within height=24" do
    user = %{id: "u1", handle: "alice", role: :user, status: :active}

    state = %App{
      current_screen: :account,
      current_user: user,
      screen_state: %{account: Account.State.new(current_user: user)},
      terminal_size: {80, 24}
    }

    tree = render_app_screen(Account, :account, state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "PROFILE")),
           "expected 'PROFILE' tab label, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "PREFS")),
           "expected 'PREFS' tab label, got: #{inspect(texts)}"

    max_y =
      elements
      |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
      |> Enum.max(fn -> 0 end)

    assert max_y <= 24,
           "account shell: total height #{max_y} exceeds 24 rows"
  end

  test "account shell clamps tab row to 64-column framed content budget" do
    user = %{
      id: "u1",
      handle: "alice",
      role: :user,
      status: :active,
      timezone: "Etc/UTC",
      preferences: %{"time_format" => "12h"}
    }

    state = %App{
      current_screen: :account,
      current_user: user,
      session_context: %{invite_code_generators: "users"},
      screen_state: %{account: Account.State.new(current_user: user, invites_visible?: true)},
      terminal_size: {64, 22}
    }

    positioned = state |> render_app_screen(Account, :account) |> apply_at_size({64, 22})

    tab_row =
      positioned
      |> content_text_elements()
      |> Enum.group_by(& &1.y)
      |> Map.values()
      |> Enum.find([], fn row ->
        Enum.any?(row, &String.contains?(&1.text, "PROFILE")) and
          Enum.any?(row, &String.contains?(&1.text, "PREFS"))
      end)
      |> Enum.sort_by(& &1.x)
      |> Enum.map_join(& &1.text)

    assert TextWidth.display_width(tab_row) <= 60
    assert tab_row =~ "PROFILE"
    refute tab_row =~ "┐"
    refute tab_row =~ "│"
  end

  test "sysop shell clamps tab row to 64-column framed content budget without inner border glyphs" do
    user = %{
      id: "u2",
      handle: "root",
      role: :sysop,
      status: :active,
      timezone: "Etc/UTC",
      preferences: %{"time_format" => "12h"}
    }

    state = %App{
      current_screen: :sysop,
      current_user: user,
      screen_state: %{sysop: Sysop.State.new(current_user: user, invites_visible?: true)},
      terminal_size: {64, 22}
    }

    positioned = state |> render_app_screen(Sysop, :sysop) |> apply_at_size({64, 22})

    tab_row =
      positioned
      |> content_text_elements()
      |> Enum.group_by(& &1.y)
      |> Map.values()
      |> Enum.find([], fn row ->
        Enum.any?(row, &String.contains?(&1.text, "BOARDS")) and
          Enum.any?(row, &String.contains?(&1.text, "LIMITS"))
      end)
      |> Enum.sort_by(& &1.x)
      |> Enum.map_join(& &1.text)

    assert TextWidth.display_width(tab_row) <= 60
    assert tab_row =~ "SITE"
    refute tab_row =~ "┐"
    refute tab_row =~ "│"
  end

  test "moderation shell renders all five tab labels within height=24" do
    user = %{id: "u2", handle: "alice", role: :mod, status: :active}

    state = %App{
      current_screen: :moderation,
      current_user: user,
      screen_state: %{moderation: Moderation.State.new()},
      terminal_size: {80, 24}
    }

    tree = render_app_screen(Moderation, :moderation, state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    for tab <- ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"] do
      assert Enum.any?(texts, &String.contains?(&1, tab)),
             "expected '#{tab}' tab label in moderation shell, got: #{inspect(texts)}"
    end

    max_y =
      elements
      |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
      |> Enum.max(fn -> 0 end)

    assert max_y <= 24,
           "moderation shell: total height #{max_y} exceeds 24 rows"
  end

  test "sysop shell renders all five tab labels within height=24" do
    user = %{id: "u3", handle: "alice", role: :sysop, status: :active}

    state = %App{
      current_screen: :sysop,
      current_user: user,
      screen_state: %{sysop: Sysop.State.new(current_user: user)},
      terminal_size: {80, 24}
    }

    tree = render_app_screen(Sysop, :sysop, state)
    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    for tab <- ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"] do
      assert Enum.any?(texts, &String.contains?(&1, tab)),
             "expected '#{tab}' tab label in sysop shell, got: #{inspect(texts)}"
    end

    max_y =
      elements
      |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
      |> Enum.max(fn -> 0 end)

    assert max_y <= 24,
           "sysop shell: total height #{max_y} exceeds 24 rows"
  end

  test "new_thread compose step with title_input='Hello' and body — both appear in positioned text" do
    {:ok, body_input_st} =
      MultiLineInput.init(%{
        value: "This is my opening post.",
        placeholder: "Write your opening post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: false
      })

    board = %{id: "b1", name: "General"}

    ss =
      NewThread.State.new(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "Hello", max_length: 60),
        body_input_state: body_input_st
      )

    state = %App{
      current_screen: :new_thread,
      current_user: %{id: "u1", handle: "alice"},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{new_thread: ss}
    }

    tree =
      NewThread.render(
        ss,
        screen_context(:new_thread, state.current_user, {80, 24}, %{
          board: board,
          board_id: board.id
        })
      )

    positioned = layout(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Hello")),
           "expected title 'Hello' in positioned text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "This is my opening post.")),
           "expected body text in positioned text, got: #{inspect(texts)}"

    max_y =
      elements
      |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
      |> Enum.max(fn -> 0 end)

    assert max_y <= 24,
           "new_thread compose step: total height #{max_y} exceeds 24 rows"
  end

  # ---------------------------------------------------------------------------
  # Phase 25 per-tab size-contract registry (D-09, D-11, Codex Concern 3)
  # Plans 02/03/04 add blocks to the per-screen helper modules below, NOT here.
  # ---------------------------------------------------------------------------

  require Foglet.TUI.LayoutSmoke.AccountHelper
  require Foglet.TUI.LayoutSmoke.ModerationHelper
  require Foglet.TUI.LayoutSmoke.SysopHelper

  Foglet.TUI.LayoutSmoke.AccountHelper.register_account_size_contracts()
  Foglet.TUI.LayoutSmoke.ModerationHelper.register_moderation_size_contracts()
  Foglet.TUI.LayoutSmoke.SysopHelper.register_sysop_size_contracts()

  # ---------------------------------------------------------------------------
  # Phase 27 cursor surfaces (CURSOR-01)
  # ---------------------------------------------------------------------------

  describe "Phase 27 cursor surfaces (CURSOR-01)" do
    @cursor_sizes [{64, 22}, {80, 24}]

    defp login_form_fixture do
      %App{
        current_screen: :login,
        terminal_size: {80, 24},
        screen_state: %{
          login: %{
            sub: :login_form,
            focused_field: :handle,
            handle_input: TextInput.init(value: "alice"),
            password_input: TextInput.init(mask_char: "*"),
            error: nil
          }
        }
      }
    end

    defp register_fixture do
      %App{
        current_screen: :register,
        terminal_size: {80, 24},
        screen_state: %{
          register: %{
            mode: "open",
            step: :combined,
            focused_field: :handle,
            invite_code_input: TextInput.init([]),
            handle_input: TextInput.init(value: "bob"),
            email_input: TextInput.init([]),
            password_input: TextInput.init(mask_char: "*"),
            confirm_input: TextInput.init(mask_char: "*"),
            collected: %{},
            error: nil
          }
        }
      }
    end

    defp forgot_password_fixture do
      %App{
        current_screen: :login,
        terminal_size: {80, 24},
        screen_state: %{
          login: %{
            sub: :reset_request,
            focused_field: :identifier,
            identifier_input: TextInput.init([]),
            message: nil
          }
        }
      }
    end

    defp collect_cursor_markers(positioned) do
      positioned
      |> text_elements()
      |> Enum.filter(&String.contains?(&1.text, "▌"))
    end

    test "Login form renders exactly one focused cursor marker at 64x22 and 80x24" do
      for {width, height} <- @cursor_sizes do
        state = %{login_form_fixture() | terminal_size: {width, height}}
        positioned = state |> render_login() |> apply_at_size({width, height})
        cursors = collect_cursor_markers(positioned)

        assert length(cursors) == 1,
               "Login form at #{width}x#{height}: expected exactly 1 cursor marker, " <>
                 "got #{length(cursors)}: #{inspect(Enum.map(cursors, & &1.text))}"
      end
    end

    test "Register combined form renders exactly one focused cursor marker at 64x22 and 80x24" do
      for {width, height} <- @cursor_sizes do
        state = %{register_fixture() | terminal_size: {width, height}}
        positioned = state |> render_register() |> apply_at_size({width, height})
        cursors = collect_cursor_markers(positioned)

        assert length(cursors) == 1,
               "Register at #{width}x#{height}: expected exactly 1 cursor marker, " <>
                 "got #{length(cursors)}: #{inspect(Enum.map(cursors, & &1.text))}"
      end
    end

    test "Forgot Password form renders exactly one focused cursor marker at 64x22 and 80x24" do
      for {width, height} <- @cursor_sizes do
        state = %{forgot_password_fixture() | terminal_size: {width, height}}
        positioned = state |> render_login() |> apply_at_size({width, height})
        cursors = collect_cursor_markers(positioned)

        assert length(cursors) == 1,
               "Forgot Password at #{width}x#{height}: expected exactly 1 cursor marker, " <>
                 "got #{length(cursors)}: #{inspect(Enum.map(cursors, & &1.text))}"
      end
    end

    test "cursor marker ▌ appears after typed value after 5 chars then 2 backspaces" do
      input = TextInput.init([])

      input =
        Enum.reduce(~w[a b c d e], input, fn char, acc ->
          {updated, _action} = TextInput.handle_event(%{key: :char, char: char}, acc)
          updated
        end)

      input =
        Enum.reduce(1..2, input, fn _i, acc ->
          {updated, _action} = TextInput.handle_event(%{key: :backspace}, acc)
          updated
        end)

      theme = Foglet.TUI.Theme.default()
      rendered = TextInput.render(input, focused: true, theme: theme)
      positioned = Engine.apply_layout(rendered, %{width: 80, height: 1})
      elements = text_elements(positioned)
      flat = Enum.map_join(elements, "", & &1.text)

      assert String.contains?(flat, "▌"),
             "expected cursor marker ▌ after typing 5 chars and 2 backspaces, got: #{inspect(flat)}"

      assert String.contains?(flat, "abc"),
             "expected 'abc' to remain after 5 chars then 2 backspaces, got: #{inspect(flat)}"
    end

    test "Verify renders existing slot-buffer surface without TextInput (slot-buffer coverage)" do
      # Verify is a custom slot-buffer surface, deliberately not converted to TextInput.
      # This test asserts the buffer text is visible and NO TextInput cursor marker appears,
      # confirming Phase 27 scope: Verify covered as custom surface without TextInput conversion.
      for {width, height} <- @cursor_sizes do
        state = %App{
          current_screen: :verify,
          current_user: %{id: "u1", handle: "alice"},
          terminal_size: {width, height},
          screen_state: %{
            verify: %{
              buffer: "XK7",
              attempts: 0,
              cooldown_until: nil,
              resend_cooldown_until: nil
            }
          }
        }

        positioned = state |> render_verify() |> apply_at_size({width, height})
        elements = text_elements(positioned)
        flat = Enum.map_join(elements, "", & &1.text)

        assert String.contains?(flat, "XK7"),
               "Verify slot-buffer at #{width}x#{height}: expected 'XK7' in render, " <>
                 "got: #{inspect(flat)}"

        cursors = collect_cursor_markers(positioned)

        assert cursors == [],
               "Verify at #{width}x#{height}: expected no TextInput cursor marker, " <>
                 "got: #{inspect(Enum.map(cursors, & &1.text))}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 27 auth breadcrumbs (BREAD-01)
  # ---------------------------------------------------------------------------

  describe "Phase 27 auth breadcrumbs (BREAD-01)" do
    @breadcrumb_sizes [{64, 22}, {80, 24}]

    test "reset_consume Login state uses explicit Login breadcrumb without leaking token" do
      for {width, height} <- @breadcrumb_sizes do
        state = reset_consume_state_with_token("RESET-TOKEN-SENTINEL", {width, height})
        positioned = state |> render_login() |> apply_at_size({width, height})
        top_row = positioned_row_text(positioned, 0)

        assert String.contains?(top_row, "Foglet ▸ Login")
        refute String.contains?(top_row, "RESET-TOKEN-SENTINEL")
      end
    end

    test "Login menu state uses explicit Login breadcrumb without reset sub-paths" do
      for {width, height} <- @breadcrumb_sizes do
        state = %App{
          current_screen: :login,
          session_context: %{registration_mode: "open"},
          terminal_size: {width, height},
          screen_state: %{login: %{sub: :menu}}
        }

        positioned = state |> render_login() |> apply_at_size({width, height})
        top_row = positioned_row_text(positioned, 0)

        assert String.contains?(top_row, "Foglet ▸ Login")
        refute String.contains?(top_row, "Forgot Password")
        refute String.contains?(top_row, "Enter Token")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 29 1-N Jump consistency (D-26, D-27, SYSOP-07)
  # ---------------------------------------------------------------------------

  describe "Phase 29 1-N Jump consistency (D-26, D-27, SYSOP-07)" do
    @phase_29_dimensions [{64, 22}, {80, 24}]

    defp phase_29_collect_text(tree), do: do_collect_text(tree, []) |> Enum.reverse()

    defp do_collect_text(nil, acc), do: acc

    defp do_collect_text(list, acc) when is_list(list),
      do: Enum.reduce(list, acc, &do_collect_text/2)

    defp do_collect_text(%{children: children} = node, acc) do
      acc = collect_node_content(node, acc)
      do_collect_text(children, acc)
    end

    defp do_collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
    defp do_collect_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
    defp do_collect_text(_other, acc), do: acc

    defp collect_node_content(%{content: content}, acc) when is_binary(content),
      do: [content | acc]

    defp collect_node_content(%{text: text}, acc) when is_binary(text), do: [text | acc]
    defp collect_node_content(_node, acc), do: acc

    test "Account command bar contains '1-3 Jump' at 64x22 and 80x24 (INVITES hidden)" do
      for {width, height} <- @phase_29_dimensions do
        # INVITES hidden: role :user with policy :sysop_only — InvitesSurface.visible?
        # returns false. Account tabs become 3: PROFILE, PREFS, SSH KEYS.
        user = %Foglet.Accounts.User{
          id: "00000000-0000-0000-0000-000000000001",
          handle: "alice",
          role: :user,
          status: :active,
          location: "Mist Harbor",
          tagline: "low clouds",
          real_name: "Alice Example",
          timezone: "Etc/UTC",
          preferences: %{"time_format" => "12h"},
          theme: "gray"
        }

        state = %App{
          current_screen: :account,
          current_user: user,
          session_context: %{
            theme: Foglet.TUI.Theme.resolve(:gray),
            theme_id: "gray",
            invite_code_generators: "sysop_only"
          },
          terminal_size: {width, height},
          screen_state: %{}
        }

        flat = state |> render_app_screen(Account, :account) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "Jump"),
               "Account at #{width}x#{height}: expected 'Jump' substring; flat=#{inspect(flat)}"

        assert String.contains?(joined, "1-3"),
               "Account at #{width}x#{height} (INVITES hidden): expected '1-3' substring; flat=#{inspect(flat)}"
      end
    end

    test "Account command bar contains '1-4 Jump' at 64x22 and 80x24 (INVITES visible)" do
      for {width, height} <- @phase_29_dimensions do
        # INVITES visible: role :sysop. Account tabs become 4 with INVITES.
        user = %Foglet.Accounts.User{
          id: "00000000-0000-0000-0000-000000000002",
          handle: "alice",
          role: :sysop,
          status: :active,
          location: "Mist Harbor",
          tagline: "low clouds",
          real_name: "Alice Example",
          timezone: "Etc/UTC",
          preferences: %{"time_format" => "12h"},
          theme: "gray"
        }

        state = %App{
          current_screen: :account,
          current_user: user,
          session_context: %{
            theme: Foglet.TUI.Theme.resolve(:gray),
            theme_id: "gray"
          },
          terminal_size: {width, height},
          screen_state: %{}
        }

        flat = state |> render_app_screen(Account, :account) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "1-4"),
               "Account at #{width}x#{height} (INVITES visible): expected '1-4' substring; flat=#{inspect(flat)}"
      end
    end

    test "Moderation command bar contains '1-5 Jump' at 64x22 and 80x24, INVITES hidden" do
      for {width, height} <- @phase_29_dimensions do
        # INVITES hidden: role :sysop on Moderation does NOT add INVITES (only
        # role :mod with policy 'mods' adds it). Mod with sysop_only also hidden.
        user = %Foglet.Accounts.User{id: "u1", handle: "mod", role: :mod, status: :active}

        state = %App{
          current_screen: :moderation,
          current_user: user,
          session_context: %{invite_code_generators: "sysop_only"},
          terminal_size: {width, height},
          screen_state: %{moderation: Moderation.State.new()}
        }

        flat = state |> render_app_screen(Moderation, :moderation) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "Jump"),
               "Moderation at #{width}x#{height}: expected 'Jump' substring; flat=#{inspect(flat)}"

        assert String.contains?(joined, "1-5"),
               "Moderation at #{width}x#{height} (INVITES hidden): expected '1-5' substring; flat=#{inspect(flat)}"

        refute String.contains?(joined, "1-6"),
               "Moderation at #{width}x#{height} (INVITES hidden): should NOT contain '1-6'; flat=#{inspect(flat)}"
      end
    end

    test "Moderation command bar contains '1-6 Jump' at 64x22 and 80x24, INVITES visible" do
      for {width, height} <- @phase_29_dimensions do
        # INVITES visible: role :mod with policy 'mods'.
        user = %Foglet.Accounts.User{id: "u1", handle: "mod", role: :mod, status: :active}

        state = %App{
          current_screen: :moderation,
          current_user: user,
          session_context: %{invite_code_generators: "mods"},
          terminal_size: {width, height},
          screen_state: %{moderation: Moderation.State.new(invites_visible?: true)}
        }

        flat = state |> render_app_screen(Moderation, :moderation) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "1-6"),
               "Moderation at #{width}x#{height} (INVITES visible): expected '1-6' substring; flat=#{inspect(flat)}"
      end
    end

    test "Sysop command bar contains '1-5 Jump' at 64x22 and 80x24, INVITES hidden" do
      for {width, height} <- @phase_29_dimensions do
        # Sysop INVITES is gated by ShellVisibility — `sysop_only` policy makes
        # INVITES hidden for non-sysops, but for sysop role it's always visible.
        # Use role :sysop with default screen_state (no :invites_visible? flag).
        user = %Foglet.Accounts.User{id: "u3", handle: "alice", role: :sysop, status: :active}

        state = %App{
          current_screen: :sysop,
          current_user: user,
          session_context: %{invite_code_generators: "sysop_only"},
          terminal_size: {width, height},
          screen_state: %{sysop: Sysop.State.new(current_user: user)}
        }

        flat = state |> render_app_screen(Sysop, :sysop) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "1-5") or String.contains?(joined, "1-6"),
               "Sysop at #{width}x#{height}: expected '1-N' substring; flat=#{inspect(flat)}"
      end
    end

    test "Sysop command bar contains '1-6 Jump' at 64x22 and 80x24, INVITES visible" do
      for {width, height} <- @phase_29_dimensions do
        # INVITES visible: explicitly seeded into screen state.
        user = %Foglet.Accounts.User{id: "u3", handle: "alice", role: :sysop, status: :active}

        state = %App{
          current_screen: :sysop,
          current_user: user,
          session_context: %{invite_code_generators: "sysop_only"},
          terminal_size: {width, height},
          screen_state: %{sysop: Sysop.State.new(current_user: user, invites_visible?: true)}
        }

        flat = state |> render_app_screen(Sysop, :sysop) |> phase_29_collect_text()
        joined = Enum.join(flat, " ")

        assert String.contains?(joined, "1-6"),
               "Sysop at #{width}x#{height} (INVITES visible): expected '1-6' substring; flat=#{inspect(flat)}"
      end
    end

    # ---------------------------------------------------------------------------
    # Module-attribute removal grep guards (D-26)
    # ---------------------------------------------------------------------------

    test ~s|no hardcoded {"1-6", "Jump"} literal in moderation.ex| do
      contents = File.read!("lib/foglet_bbs/tui/screens/moderation.ex")

      refute String.contains?(contents, ~s|{"1-6", "Jump"}|),
             "moderation.ex must not contain a hardcoded {\"1-6\", \"Jump\"} literal (D-26)"
    end

    test ~s|no hardcoded {"1-6", "Jump"} literal in account.ex| do
      contents = File.read!("lib/foglet_bbs/tui/screens/account.ex")

      refute String.contains?(contents, ~s|{"1-6", "Jump"}|),
             "account.ex must not contain a hardcoded {\"1-6\", \"Jump\"} literal (D-26)"
    end

    test "Sysop jump_hint computes 1-N from tab count (no INVITES special-case)" do
      contents = File.read!("lib/foglet_bbs/tui/screens/sysop/render.ex")

      refute String.contains?(contents, ~s|if "INVITES" in State.tab_labels|),
             "sysop/render.ex jump_hint must not gate on INVITES visibility (D-26)"

      expected = ~S|"1-#{length(State.tab_labels(ss))}"|

      assert String.contains?(contents, expected),
             "sysop/render.ex must compute jump_hint as 1-N from State.tab_labels(ss) (D-26)"
    end

    test "Account.@key_bar module attribute removed (D-26)" do
      top_level_contents = File.read!("lib/foglet_bbs/tui/screens/account.ex")
      render_contents = File.read!("lib/foglet_bbs/tui/screens/account/render.ex")

      refute String.contains?(top_level_contents, "@key_bar ["),
             "account.ex must not define a @key_bar module attribute (D-26)"

      assert String.contains?(render_contents, "defp key_bar(ss)"),
             "account/render.ex must define a render-time key_bar/1 function (D-26)"
    end

    test "Moderation.@key_list module attribute removed (D-26)" do
      contents = File.read!("lib/foglet_bbs/tui/screens/moderation.ex")

      refute String.contains?(contents, "@key_list ["),
             "moderation.ex must not define a @key_list module attribute (D-26)"

      assert String.contains?(contents, "defp key_list(ss)"),
             "moderation.ex must define a render-time key_list/1 function (D-26)"
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 31 reset copy compact rendering (D-12, D-14, D-18, AUTH-02, AUTH-03)
  # ---------------------------------------------------------------------------

  describe "Phase 31 reset copy compact rendering (D-12, D-14, D-18)" do
    @reset_compact_size {64, 22}

    setup do
      original_delivery_mode = Config.get("delivery_mode", "no_email")

      on_exit(fn ->
        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
      end)

      :ok
    end

    defp reset_request_state_at(identifier, {width, height}) do
      input = Foglet.TUI.Widgets.Input.TextInput.init(value: identifier)
      {input_end, _} = Foglet.TUI.Widgets.Input.TextInput.handle_event(%{key: :end}, input)

      %App{
        current_screen: :login,
        session_context: %{registration_mode: "open"},
        terminal_size: {width, height},
        screen_state: %{
          login: %{
            sub: :reset_request,
            focused_field: :identifier,
            identifier_input: input_end,
            error: nil,
            message: nil,
            message_category: nil
          }
        }
      }
    end

    defp submit_reset_request_at(%App{} = state) do
      {pending_state, [%Raxol.Core.Runtime.Command{type: :task, data: task}]} =
        App.update({:key, %{key: :enter}}, state)

      App.update(task.(), pending_state)
    end

    defp message_text_rows(state, size) do
      positioned = state |> render_login() |> apply_at_size(size)

      message_text = get_in(state.screen_state, [:login, :message])

      message_first_line =
        case message_text do
          nil ->
            ""

          text ->
            text
            |> TextWidth.wrap(elem(size, 0) - 2)
            |> List.first()
            |> Kernel.||("")
        end

      content = content_text_elements(positioned)

      first_y =
        content
        |> Enum.find(fn el ->
          message_first_line != "" and String.contains?(el.text, message_first_line)
        end)
        |> case do
          nil -> nil
          el -> el.y
        end

      message_rows =
        case first_y do
          nil ->
            []

          y0 ->
            content
            |> Enum.filter(&(&1.y >= y0))
            |> Enum.group_by(& &1.y)
            |> Enum.sort_by(fn {y, _} -> y end)
            |> Enum.map(fn {y, els} ->
              row_text = els |> Enum.sort_by(& &1.x) |> Enum.map_join(& &1.text)
              {y, row_text}
            end)
        end

      message_rows
    end

    test "valid email submission produces multi-row reset confirmation copy at 64x22 (D-12, AUTH-02)" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state_at("anybody@example.test", @reset_compact_size)
      {new_state, []} = submit_reset_request_at(state)

      message = get_in(new_state.screen_state, [:login, :message])
      assert is_binary(message)

      rows = message_text_rows(new_state, @reset_compact_size)

      # Multi-row property: reset confirmation copy must wrap into >=2 rows at
      # 64x22 so a single overflowing text node never silently truncates.
      distinct_ys = rows |> Enum.map(fn {y, _} -> y end) |> Enum.uniq()

      assert length(distinct_ys) >= 2,
             "expected reset confirmation copy to span >=2 rows at 64x22, got: #{inspect(rows)}"

      # Width property: every content row at 64x22 fits the terminal width.
      for {y, row_text} <- rows do
        assert TextWidth.display_width(row_text) <= 64,
               "row at y=#{y} exceeded 64 cols: #{inspect(row_text)} " <>
                 "(display_width=#{TextWidth.display_width(row_text)})"
      end
    end

    test "no_email reset confirmation lists active sysop emails comma-separated at 64x22 (D-14, AUTH-03)" do
      Config.put!("delivery_mode", "no_email")

      sysop_a =
        FogletBbs.AccountsFixtures.user_fixture(%{
          handle: "sysopa",
          email: "sysopa@example.test"
        })
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()

      sysop_b =
        FogletBbs.AccountsFixtures.user_fixture(%{
          handle: "sysopb",
          email: "sysopb@example.test"
        })
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()

      {:ok, _} = Foglet.Accounts.confirm_user(sysop_a)
      {:ok, _} = Foglet.Accounts.confirm_user(sysop_b)

      # Negative-presence fixtures: deleted sysop, non-active sysop, non-sysop user.
      _deleted_sysop =
        FogletBbs.AccountsFixtures.user_fixture(%{
          handle: "sysopdel",
          email: "deletedsysop@example.test"
        })
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()
        |> then(fn u ->
          {:ok, confirmed} = Foglet.Accounts.confirm_user(u)
          confirmed
        end)
        |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
        |> FogletBbs.Repo.update!()

      _pending_sysop =
        FogletBbs.AccountsFixtures.user_fixture(%{
          handle: "sysoppen",
          email: "pendingsysop@example.test"
        })
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()
        |> Ecto.Changeset.change(status: :pending)
        |> FogletBbs.Repo.update!()

      _non_sysop =
        FogletBbs.AccountsFixtures.user_fixture(%{
          handle: "civilian",
          email: "civilian@example.test"
        })
        |> then(fn u ->
          {:ok, confirmed} = Foglet.Accounts.confirm_user(u)
          confirmed
        end)

      state = reset_request_state_at("anybody@example.test", @reset_compact_size)
      {new_state, []} = submit_reset_request_at(state)

      positioned = new_state |> render_login() |> apply_at_size(@reset_compact_size)
      content_rows = positioned |> content_text_elements() |> text_rows()
      joined = content_rows |> Map.values() |> Enum.join(" | ")

      # Active sysop emails are listed.
      assert String.contains?(joined, "sysopa@example.test"),
             "expected sysopa@example.test in rendered no-email copy at 64x22, " <>
               "got rows: #{inspect(content_rows)}"

      assert String.contains?(joined, "sysopb@example.test"),
             "expected sysopb@example.test in rendered no-email copy at 64x22, " <>
               "got rows: #{inspect(content_rows)}"

      # Comma-separated rendering: at least one of the two emails appears
      # adjacent to a comma.
      assert joined =~ ~r/sysopa@example\.test\s*,|,\s*sysopa@example\.test/,
             "expected sysopa@example.test next to a comma in no-email copy, got: #{inspect(joined)}"

      # Negative-presence: deleted, pending (non-active), and non-sysop emails
      # never appear.
      refute String.contains?(joined, "deletedsysop@example.test"),
             "deleted sysop email leaked into no-email copy: #{inspect(content_rows)}"

      refute String.contains?(joined, "pendingsysop@example.test"),
             "non-active sysop email leaked into no-email copy: #{inspect(content_rows)}"

      refute String.contains?(joined, "civilian@example.test"),
             "non-sysop email leaked into no-email copy: #{inspect(content_rows)}"

      # Every content row stays within 64 cols.
      for {y, row_text} <- content_rows do
        assert TextWidth.display_width(row_text) <= 64,
               "no-email row at y=#{y} exceeded 64 cols: #{inspect(row_text)}"
      end
    end

    test "no_email reset confirmation falls back to sysop/operator copy without forbidden URLs at 64x22 (D-14, AUTH-03)" do
      Config.put!("delivery_mode", "no_email")

      state = reset_request_state_at("anybody@example.test", @reset_compact_size)
      {new_state, []} = submit_reset_request_at(state)

      positioned = new_state |> render_login() |> apply_at_size(@reset_compact_size)
      content_rows = positioned |> content_text_elements() |> text_rows()
      joined = content_rows |> Map.values() |> Enum.join(" | ")

      assert joined =~ ~r/sysop|operator/i,
             "no-sysop fallback at 64x22 must mention 'sysop' or 'operator', got: #{inspect(content_rows)}"

      refute String.contains?(joined, "unavailable"),
             "no-email copy must not say 'unavailable': #{inspect(content_rows)}"

      refute String.contains?(joined, "http://"),
             "no-email copy must not include 'http://': #{inspect(content_rows)}"

      refute String.contains?(joined, "https://"),
             "no-email copy must not include 'https://': #{inspect(content_rows)}"

      refute String.contains?(joined, "/users/reset_password"),
             "no-email copy must not include '/users/reset_password': #{inspect(content_rows)}"

      # Wrap to multiple rows at 64x22 to prove width-aware rendering.
      message_rows = message_text_rows(new_state, @reset_compact_size)
      distinct_ys = message_rows |> Enum.map(fn {y, _} -> y end) |> Enum.uniq()

      assert length(distinct_ys) >= 2,
             "expected no-email copy to span >=2 rows at 64x22, got: #{inspect(message_rows)}"

      for {y, row_text} <- message_rows do
        assert TextWidth.display_width(row_text) <= 64,
               "no-email message row at y=#{y} exceeded 64 cols: #{inspect(row_text)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 31 raw reset token non-leak (D-11, D-18, AUTH-04)
  # ---------------------------------------------------------------------------

  describe "Phase 31 raw reset token non-leak (D-11, D-18)" do
    @reset_consume_sentinel "RAW-RESET-TOKEN-SHOULD-NOT-LEAK"
    @reset_consume_sizes [{64, 22}, {80, 24}]

    defp reset_consume_state_with_token(token, {width, height}) do
      token_input = Foglet.TUI.Widgets.Input.TextInput.init(value: token)

      {token_input_end, _} =
        Foglet.TUI.Widgets.Input.TextInput.handle_event(%{key: :end}, token_input)

      %App{
        current_screen: :login,
        session_context: %{registration_mode: "open"},
        terminal_size: {width, height},
        screen_state: %{
          login: %{
            sub: :reset_consume,
            focused_field: :token,
            token_input: token_input_end,
            password_input: Foglet.TUI.Widgets.Input.TextInput.init(value: "", mask_char: "*"),
            password_confirmation_input:
              Foglet.TUI.Widgets.Input.TextInput.init(value: "", mask_char: "*"),
            error: nil
          }
        }
      }
    end

    test "raw reset token is absent from chrome frame elements at 64x22 and 80x24" do
      for {width, height} <- @reset_consume_sizes do
        state = reset_consume_state_with_token(@reset_consume_sentinel, {width, height})
        positioned = state |> render_login() |> apply_at_size({width, height})

        chrome_elements =
          positioned
          |> List.flatten()
          |> Enum.filter(fn el ->
            el.type == :text and is_binary(Map.get(el, :text, "")) and
              Map.get(el, :attrs, %{}) |> Map.get(:chrome_frame?, false)
          end)

        for el <- chrome_elements do
          refute String.contains?(el.text, @reset_consume_sentinel),
                 ":reset_consume sentinel leaked into chrome frame at #{width}x#{height}: " <>
                   "y=#{el.y} text=#{inspect(el.text)}"
        end
      end
    end

    test "raw reset token appears only on the focused token input row at 64x22" do
      state = reset_consume_state_with_token(@reset_consume_sentinel, {64, 22})
      positioned = state |> render_login() |> apply_at_size({64, 22})

      sentinel_elements =
        positioned
        |> text_elements()
        |> Enum.filter(&String.contains?(&1.text, @reset_consume_sentinel))

      assert sentinel_elements != [],
             "expected at least one rendered text element to contain the sentinel " <>
               "(the focused token input field), got none"

      sentinel_ys = sentinel_elements |> Enum.map(& &1.y) |> Enum.uniq()

      assert length(sentinel_ys) == 1,
             "expected sentinel on exactly one row (the token field), got rows: " <>
               inspect(sentinel_ys)

      [token_y] = sentinel_ys

      # The token field row never co-occurs with chrome rows, by construction:
      # chrome top is y=0 and chrome bottom is y=height-1.
      refute token_y == 0,
             "sentinel landed on chrome top row (y=0) at 64x22"

      refute token_y == 22 - 1,
             "sentinel landed on chrome bottom (command) row (y=21) at 64x22"
    end

    test "breadcrumb parts for :reset_consume stay explicit and never include the raw token" do
      for {width, height} <- @reset_consume_sizes do
        state = reset_consume_state_with_token(@reset_consume_sentinel, {width, height})
        positioned = state |> render_login() |> apply_at_size({width, height})
        top_row = positioned_row_text(positioned, 0)

        assert String.contains?(top_row, "Foglet ▸ Login")
        refute String.contains?(top_row, @reset_consume_sentinel)
      end
    end

    test "command bar (key hints) row does not include the raw token at 64x22 and 80x24" do
      for {width, height} <- @reset_consume_sizes do
        state = reset_consume_state_with_token(@reset_consume_sentinel, {width, height})
        positioned = state |> render_login() |> apply_at_size({width, height})

        bottom_row_text =
          positioned
          |> text_elements()
          |> Enum.filter(&(&1.y == height - 1))
          |> Enum.sort_by(& &1.x)
          |> Enum.map_join(& &1.text)

        refute String.contains?(bottom_row_text, @reset_consume_sentinel),
               "raw reset token leaked into command bar at #{width}x#{height}: " <>
                 inspect(bottom_row_text)
      end
    end

    test "error message row never includes the raw token even when the error is set" do
      # Trigger a generic error path and ensure the sentinel does not appear in
      # the inline error rows. Use the password mismatch error path because it
      # is reachable from screen state without a DB round-trip.
      token_input =
        Foglet.TUI.Widgets.Input.TextInput.init(value: @reset_consume_sentinel)

      {token_input_end, _} =
        Foglet.TUI.Widgets.Input.TextInput.handle_event(%{key: :end}, token_input)

      password_input =
        Foglet.TUI.Widgets.Input.TextInput.init(value: "alpha", mask_char: "*")

      {password_input_end, _} =
        Foglet.TUI.Widgets.Input.TextInput.handle_event(%{key: :end}, password_input)

      confirmation_input =
        Foglet.TUI.Widgets.Input.TextInput.init(value: "beta", mask_char: "*")

      {confirmation_input_end, _} =
        Foglet.TUI.Widgets.Input.TextInput.handle_event(%{key: :end}, confirmation_input)

      state = %App{
        current_screen: :login,
        session_context: %{registration_mode: "open"},
        terminal_size: {64, 22},
        screen_state: %{
          login: %{
            sub: :reset_consume,
            focused_field: :password_confirmation,
            token_input: token_input_end,
            password_input: password_input_end,
            password_confirmation_input: confirmation_input_end,
            error: nil
          }
        }
      }

      {after_submit, []} = App.update({:key, %{key: :enter}}, state)

      error = get_in(after_submit.screen_state, [:login, :error])
      assert is_binary(error)

      refute String.contains?(error, @reset_consume_sentinel),
             "error copy must never include the raw token: #{inspect(error)}"

      # And the rendered tree must not place the sentinel anywhere outside the
      # focused token input row.
      positioned = after_submit |> render_login() |> apply_at_size({64, 22})

      sentinel_elements =
        positioned
        |> text_elements()
        |> Enum.filter(&String.contains?(&1.text, @reset_consume_sentinel))

      sentinel_ys = sentinel_elements |> Enum.map(& &1.y) |> Enum.uniq()

      assert length(sentinel_ys) == 1,
             "post-error render expected sentinel on exactly one row " <>
               "(the token field), got rows: #{inspect(sentinel_ys)}"
    end
  end
end

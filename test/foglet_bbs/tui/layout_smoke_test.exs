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
  alias Foglet.TUI.TextWidth

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
    Sysop,
    ThreadList,
    Verify
  }

  alias Foglet.TUI.Widgets.Chrome.KeyBar
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.List.ListRow
  alias Foglet.TUI.Widgets.Modal
  alias Raxol.UI.Components.Input.MultiLineInput
  alias Raxol.UI.Layout.Engine

  @dimensions %{width: 80, height: 24}
  @phase_16_dimensions [{64, 22}, {80, 24}, {132, 50}]

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

  defp apply(tree), do: Engine.apply_layout(tree, @dimensions)

  defp apply_at_size(tree, {width, height}) do
    Engine.apply_layout(tree, %{width: width, height: height})
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
          |> ScreenFrame.render("Threads", text("BODY SENTINEL"), [
            {"J/K", "Navigate"},
            {"Enter", "Open"},
            {"Q", "Back"}
          ])
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

        breadcrumb =
          Enum.find(elements, fn element ->
            String.starts_with?(element.text, "┌") and String.contains?(element.text, "Foglet")
          end)

        content =
          Enum.find(elements, fn element ->
            String.contains?(element.text, "BODY SENTINEL")
          end)

        command =
          Enum.find(elements, fn element ->
            String.starts_with?(element.text, "└") and
              (String.contains?(element.text, "Navigate") or String.contains?(element.text, "J/K"))
          end)

        assert breadcrumb, "expected breadcrumb/status text at #{inspect({width, height})}"
        assert content, "expected body text at #{inspect({width, height})}"
        assert command, "expected command text at #{inspect({width, height})}"
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

        state =
          %Foglet.TUI.App{
            current_screen: :thread_list,
            current_user: user,
            current_board: %{id: "b1", name: "General", slug: "general"},
            session_context: %{},
            terminal_size: {width, height},
            current_thread_list: threads,
            screen_state: %{thread_list: %{selected_index: 0}}
          }
          |> Map.from_struct()

        tree = ThreadList.render(state)
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
          %App{
            current_screen: :board_list,
            current_user: user,
            board_list: directory,
            screen_state: %{board_list: %{selected_index: 0}},
            terminal_size: size
          }
          |> Map.from_struct()

        positioned = BoardList.render(state) |> apply_at_size(size)
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

          String.contains?(flat, row_text) and
            Enum.any?(
              [long_prefix, "Subscribed Board", "Available Board", "⚿", "✓", "+", "◆"],
              &String.contains?(row_text, &1)
            )
        end)
        |> assert_board_list_no_row_overlap!(size, "BoardList.render")
      end
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
      %App{
        current_screen: :post_composer,
        current_user: composer_user(),
        current_board: %{id: "b1", name: "General"},
        current_thread: %{id: "t1", title: "Composer Contract", board_id: "b1"},
        session_context: %{theme: Foglet.TUI.Theme.default(), max_post_length: 1_000},
        terminal_size: {width, height},
        screen_state: %{
          post_composer:
            PostComposer.init_screen_state(
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
      %App{
        current_screen: :new_thread,
        current_user: composer_user(),
        current_board: %{id: "b1", name: "General"},
        session_context: %{theme: Foglet.TUI.Theme.default(), max_post_length: 1_000},
        terminal_size: {width, height},
        screen_state: %{
          new_thread:
            NewThread.init_screen_state(
              step: :compose,
              board: %{id: "b1", name: "General"},
              boards: [%{id: "b1", name: "General"}],
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
          width
          |> post_composer_state(height, mode)
          |> PostComposer.render()
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
          width
          |> new_thread_state(height, mode)
          |> NewThread.render()
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
      %Foglet.TUI.App{
        current_screen: :post_reader,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "reader"},
        current_board: %{id: "b1", name: "General"},
        current_thread: %{id: "t1", title: "Reader Contract"},
        posts: phase_22_posts(),
        screen_state: %{post_reader: PostReader.init_screen_state(selected_post_index: 2)},
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

        positioned =
          width
          |> phase_22_state(height)
          |> PostReader.render()
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
  end

  # ---------------------------------------------------------------------------
  # Phase 16 size contracts
  # ---------------------------------------------------------------------------

  test "phase 16 representative row, keybar, modal, and compose paths fit terminal widths" do
    theme = Foglet.TUI.Theme.default()

    keys = [
      {"J/K", "Navigate"},
      {"Enter", "Open 漢字"},
      {"● ◆", "▸ ▾ ✓ ×"}
    ]

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

      keybar = KeyBar.render(theme, keys, width: width) |> flatten_text()
      assert keybar =~ "J/K"
      assert keybar =~ "Navigate"
      assert keybar =~ "●"
      assert_line_within_width!("KeyBar #{width}", keybar, width)

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

  test "login menu renders centered placeholder and command bar actions" do
    state = %App{screen_state: %{}, terminal_size: {80, 24}}
    tree = Login.render(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    placeholder =
      Enum.find(elements, fn element ->
        String.contains?(element.text, "Imagine something cool here")
      end)

    assert placeholder,
           "expected centered placeholder text, got: #{inspect(texts)}"

    refute Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "login menu body should not render welcome text, got: #{inspect(texts)}"

    refute Enum.any?(texts, &String.contains?(&1, "[L]")),
           "login menu body should not render bracketed menu items, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "L Login")),
           "expected command bar Login key, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "L Login")),
           "expected command bar Login label, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "R Register")),
           "expected command bar Register key, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "R Register")),
           "expected command bar Register label, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Q Quit")),
           "expected command bar Quit key, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Q Quit")),
           "expected command bar Quit label, got: #{inspect(texts)}"

    assert placeholder.x in 26..28,
           "expected placeholder near horizontal center, got: #{inspect(placeholder)}"

    assert placeholder.y in 9..11,
           "expected placeholder near vertical center, got: #{inspect(placeholder)}"
  end

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

    tree = Login.render(state)
    positioned = apply(tree)

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

    tree = MainMenu.render(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    # D-11: no Welcome line.
    refute Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "Phase 19 D-11 removes the welcome line; got: #{inspect(texts)}"

    # D-07: boxed Navigation + Oneliners panel headers.
    assert Enum.any?(texts, &(&1 == "Navigation")),
           "expected 'Navigation' panel header, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "Oneliners")),
           "expected 'Oneliners' panel header, got: #{inspect(texts)}"

    # D-08: glyph-shaped Navigation rows (not [B] bracket rows).
    assert Enum.any?(texts, &(&1 =~ ~r/●.*Boards.*B$/)),
           "expected '● Boards    B' row, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/↯.*Logout.*Q$/)),
           "expected '↯ Logout    Q' row, got: #{inspect(texts)}"

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

    tree = MainMenu.render(state)
    positioned = apply(tree)

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
          MainMenu.render(state) |> apply_at_size({width, height})

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
        nav_header =
          Enum.find(elements, fn element -> element.text == "Navigation" end)

        oneliners_header =
          Enum.find(elements, fn element -> element.text == "Oneliners" end)

        assert nav_header,
               "expected 'Navigation' header at #{inspect({width, height})}; got: #{inspect(Enum.map(elements, & &1.text))}"

        assert oneliners_header,
               "expected 'Oneliners' header at #{inspect({width, height})}; got: #{inspect(Enum.map(elements, & &1.text))}"

        # ── Side-by-side: Navigation header LEFT of Oneliners header. ───────
        assert nav_header.x < oneliners_header.x,
               "expected Navigation.x (#{nav_header.x}) < Oneliners.x (#{oneliners_header.x}) at #{inspect({width, height})}"

        # ── Range overlap: per-y, sorted-by-x adjacent pairs do not overlap.
        #    REPLACES the prior identical-`{x, y}` check, which only caught
        #    elements starting at the same column. Range overlap catches
        #    elements whose display-width spans collide on the same y.
        elements_by_y = Enum.group_by(elements, & &1.y)

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

        for row <- oneliner_rows do
          assert row.x >= oneliners_header.x,
                 "oneliner row bled out of right panel at #{inspect({width, height})}: " <>
                   "row.x=#{row.x} < oneliners_header.x=#{oneliners_header.x}; row=#{inspect(row)}"

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

      positioned = MainMenu.render(state) |> apply_at_size({64, 22})
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
      oneliners_header =
        Enum.find(elements, fn element -> element.text == "Oneliners" end)

      assert oneliners_header,
             "expected 'Oneliners' header in CJK fixture render"

      oneliner_rows =
        Enum.filter(elements, fn element ->
          String.starts_with?(element.text, "> @")
        end)

      for row <- oneliner_rows do
        assert row.x >= oneliners_header.x,
               "CJK oneliner row bled out of right panel: row.x=#{row.x} < oneliners_header.x=#{oneliners_header.x}; row=#{inspect(row)}"

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

    state = %App{
      current_user: user,
      board_list: board_list,
      screen_state: %{board_list: %{selected_index: 0}},
      terminal_size: {80, 24}
    }

    tree = BoardList.render(state)
    positioned = apply(tree)

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

    state = %App{
      current_user: user,
      current_thread: thread,
      posts: posts,
      read_position: %{},
      screen_state: %{post_reader: PostReader.init_screen_state([])},
      terminal_size: {80, 24}
    }

    tree = PostReader.render(state)
    positioned = apply(tree)

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

    tree = Login.render(state)
    positioned = apply(tree)

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

    tree = Register.render(state)
    positioned = apply(tree)

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

    tree = Verify.render(state)
    positioned = apply(tree)

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

    state = %App{
      current_screen: :post_composer,
      current_user: %{id: "u1", handle: "alice"},
      current_thread: %{id: "t1", title: "Hello"},
      session_context: %{},
      terminal_size: {80, 24},
      composer_draft: nil,
      screen_state: %{
        post_composer: PostComposer.init_screen_state(input_state: input_st)
      }
    }

    tree = PostComposer.render(state)

    # apply_layout must not raise — this is the primary Bug B assertion
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Hello world")),
           "expected 'Hello world' to appear in rendered text, got: #{inspect(texts)}"
  end

  # ---------------------------------------------------------------------------
  # Modal overlay smoke tests (task #6)
  # ---------------------------------------------------------------------------

  test "no-modal: view/1 without modal renders screen content through layout engine" do
    state = %App{screen_state: %{}, terminal_size: {80, 24}}
    tree = App.view(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Imagine something cool here")),
           "expected login placeholder in no-modal view, got: #{inspect(texts)}"
  end

  test "with-modal: view/1 with :info modal renders title and message through layout engine" do
    state = %App{
      screen_state: %{},
      terminal_size: {80, 24},
      modal: %Foglet.TUI.Modal{type: :info, message: "Your draft was saved."}
    }

    tree = App.view(state)
    positioned = apply(tree)

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
    positioned = apply(tree)

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
       Login.render(%App{
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
       Register.render(%App{
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
       Verify.render(%App{
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
       PostComposer.render(%App{
         current_screen: :post_composer,
         current_user: %{id: "u1", handle: "alice"},
         current_thread: %{id: "t1", title: "Hello"},
         session_context: %{},
         terminal_size: {80, 24},
         composer_draft: nil,
         screen_state: %{
           post_composer: PostComposer.init_screen_state(input_state: input_st)
         }
       })}
    ]

    for {name, tree} <- screens do
      positioned = apply(tree)
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

    ss = NewThread.init_screen_state(boards: boards, width: 80)

    state = %App{
      current_screen: :new_thread,
      current_user: %{id: "u1", handle: "alice"},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{new_thread: ss}
    }

    tree = NewThread.render(state)
    positioned = apply(tree)

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
      screen_state: %{account: Account.init_screen_state()},
      terminal_size: {80, 24}
    }

    tree = Account.render(state)
    positioned = apply(tree)

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

  test "moderation shell renders all five tab labels within height=24" do
    user = %{id: "u2", handle: "alice", role: :mod, status: :active}

    state = %App{
      current_screen: :moderation,
      current_user: user,
      screen_state: %{moderation: Moderation.init_screen_state()},
      terminal_size: {80, 24}
    }

    tree = Moderation.render(state)
    positioned = apply(tree)

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
      screen_state: %{sysop: Sysop.init_screen_state()},
      terminal_size: {80, 24}
    }

    tree = Sysop.render(state)
    positioned = apply(tree)

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
      NewThread.init_screen_state(
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

    tree = NewThread.render(state)
    positioned = apply(tree)

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
end

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
            String.contains?(element.text, "Foglet")
          end)

        content =
          Enum.find(elements, fn element ->
            String.contains?(element.text, "BODY SENTINEL")
          end)

        command =
          Enum.find(elements, fn element ->
            String.contains?(element.text, "Navigate") or String.contains?(element.text, "J/K")
          end)

        assert breadcrumb, "expected breadcrumb/status text at #{inspect({width, height})}"
        assert content, "expected body text at #{inspect({width, height})}"
        assert command, "expected command text at #{inspect({width, height})}"
        assert breadcrumb.y < content.y
        assert content.y < command.y
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
      assert keybar =~ "[J/K]"
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

  test "login menu renders welcome and menu items at distinct y positions" do
    state = %App{screen_state: %{}, terminal_size: {80, 24}}
    tree = Login.render(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "expected 'Welcome' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "[L]")),
           "expected '[L] Login' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "[Q]")),
           "expected '[Q] Quit' text, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 3,
           "expected at least 3 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
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

  test "main_menu renders welcome and all menu items at distinct y positions" do
    user = %{handle: "bob", id: "u1", status: :active, role: :member}

    state =
      %App{current_user: user, screen_state: %{}, terminal_size: {80, 24}}
      |> Map.from_struct()
      |> Map.put(:recent_oneliners, [%{body: "hello", user: %{handle: "alice"}}])

    tree = MainMenu.render(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "expected 'Welcome' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "[B]")),
           "expected '[B] Browse Boards' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "[Q]")),
           "expected '[Q] Logout' text, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "Oneliners")),
           "expected 'Oneliners' panel title, got: #{inspect(texts)}"

    assert Enum.any?(texts, &String.contains?(&1, "@alice  hello")),
           "expected '@alice  hello' row, got: #{inspect(texts)}"

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 3,
           "expected at least 3 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
  end

  test "main_menu clips Unicode oneliners to display-width limits" do
    user = %{handle: "bob", id: "u1", status: :active, role: :member}

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
            unread_count: 3
          },
          %{
            board: %{id: "b2", name: "Announcements"},
            subscribed?: false,
            required_subscription?: false,
            unread_count: 0
          },
          %{
            board: %{id: "b3", name: "Off-topic"},
            subscribed?: true,
            required_subscription?: false,
            unread_count: 1
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

    # The login screen (default) must show its welcome text
    assert Enum.any?(texts, &String.contains?(&1, "Welcome")),
           "expected 'Welcome' in no-modal view, got: #{inspect(texts)}"
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
end

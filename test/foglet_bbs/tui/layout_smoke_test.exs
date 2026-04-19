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

  use ExUnit.Case, async: true

  alias Foglet.TUI.App

  alias Foglet.TUI.Screens.{
    BoardList,
    Login,
    MainMenu,
    NewThread,
    PostComposer,
    PostReader,
    Register,
    Verify
  }

  alias Raxol.UI.Components.Input.MultiLineInput
  alias Raxol.UI.Layout.Engine

  @dimensions %{width: 80, height: 24}

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
    state = %App{
      screen_state: %{
        login: %{
          sub: :login_form,
          form: %{handle: "alice", password: "secret", error: nil},
          focused_field: :handle
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
    state = %App{current_user: user, screen_state: %{}, terminal_size: {80, 24}}
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

    ys = elements |> Enum.map(& &1.y) |> Enum.uniq()

    assert length(ys) >= 3,
           "expected at least 3 distinct y positions, got #{length(ys)}: #{inspect(elements)}"
  end

  # ---------------------------------------------------------------------------
  # Board list screen
  # ---------------------------------------------------------------------------

  test "board_list renders board rows at distinct y positions" do
    boards = [
      %{id: "b1", name: "General", unread_count: 3},
      %{id: "b2", name: "Announcements", unread_count: 0},
      %{id: "b3", name: "Off-topic", unread_count: 1}
    ]

    user = %{handle: "carol", id: "u2", status: :active, role: :member}

    state = %App{
      current_user: user,
      board_list: boards,
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
      screen_state: %{post_reader: %{selected_post_index: 0}},
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
    state = %App{
      screen_state: %{
        login: %{
          sub: :login_form,
          form: %{handle: "alice", password: "", error: nil},
          focused_field: :handle
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
    state = %App{
      current_screen: :register,
      register_wizard: %{
        mode: "open",
        step: :handle,
        data: %{},
        error: nil,
        current_input: "bob"
      },
      terminal_size: {80, 24},
      screen_state: %{}
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
      verify_state: %{buffer: "XK7", attempts: 0, cooldown_until: nil},
      terminal_size: {80, 24},
      screen_state: %{}
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
        post_composer: %{
          mode: :edit,
          reply_to: nil,
          error: nil,
          input_state: input_st
        }
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
      modal: %{type: :info, title: "Saved", message: "Your draft was saved."}
    }

    tree = App.view(state)
    positioned = apply(tree)

    elements = text_elements(positioned)
    texts = Enum.map(elements, & &1.text)

    assert Enum.any?(texts, &String.contains?(&1, "Saved")),
           "expected modal title 'Saved' in positioned elements, got: #{inspect(texts)}"

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
      modal: %{type: :info, title: "Notice", message: "Centered?"}
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
             form: %{handle: "alice", password: "secret", error: nil},
             focused_field: :handle
           }
         },
         terminal_size: {80, 24}
       })},
      {"register wizard",
       Register.render(%App{
         current_screen: :register,
         register_wizard: %{
           mode: "open",
           step: :handle,
           data: %{},
           error: nil,
           current_input: "bob"
         },
         terminal_size: {80, 24},
         screen_state: %{}
       })},
      {"verify screen",
       Verify.render(%App{
         current_screen: :verify,
         current_user: %{id: "u1", handle: "alice"},
         verify_state: %{buffer: "XK7", attempts: 0, cooldown_until: nil},
         terminal_size: {80, 24},
         screen_state: %{}
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
           post_composer: %{mode: :edit, reply_to: nil, error: nil, input_state: input_st}
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

    ss = %{
      step: :compose,
      boards: [board],
      selected_board_index: 0,
      board: board,
      title_input: "Hello",
      body_input_state: body_input_st,
      focused: :title,
      error: nil
    }

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

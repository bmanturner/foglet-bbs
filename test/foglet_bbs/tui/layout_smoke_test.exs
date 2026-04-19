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
  alias Foglet.TUI.Screens.{BoardList, Login, MainMenu, PostReader}
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
end

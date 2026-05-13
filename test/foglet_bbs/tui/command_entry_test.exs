defmodule Foglet.TUI.CommandEntryTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.CommandEntry
  alias Foglet.TUI.Screens.NewThread.State, as: NewThreadState

  defmodule FakePosts do
    def search_readable_posts(_actor, _opts) do
      [
        %{
          board: %{id: "b1", slug: "general", name: "General"},
          thread: %{id: "t1", title: "Welcome thread"},
          post: %{id: "p1", message_number: 42, user: %{handle: "alice"}},
          author: %{handle: "alice"},
          around_message_number: 42,
          snippet: "hello world"
        }
      ]
    end

    def fetch_readable_post_by_board_slug_and_message_number(_actor, "general", 42) do
      {:ok,
       %{
         board: %{id: "b1", slug: "general"},
         thread: %{id: "t1", title: "Welcome thread"},
         post: %{id: "p1", message_number: 42},
         around_message_number: 42
       }}
    end

    def fetch_readable_post_by_board_slug_and_message_number(_actor, _slug, _message_number),
      do: {:error, :not_found}
  end

  test "slash opens CommandEntry on browsing screens and escape restores route" do
    state = %App{current_screen: :board_list, session_context: %{domain: %{posts: FakePosts}}}

    {opened, []} = App.update({:key, %{key: :char, char: "/"}}, state)
    assert %CommandEntry{} = opened.command_entry
    assert opened.current_screen == :board_list

    {closed, []} = App.update({:key, %{key: :escape}}, opened)
    assert closed.command_entry == nil
    assert closed.current_screen == :board_list
  end

  test "printable slash is not intercepted on text-entry screens" do
    state = %App{
      current_screen: :new_thread,
      session_context: %{domain: %{posts: FakePosts}},
      screen_state: %{new_thread: NewThreadState.new(step: :compose)}
    }

    {updated, []} = App.update({:key, %{key: :char, char: "/"}}, state)
    assert updated.command_entry == nil
  end

  test "plain search returns selectable results and selection navigates to target post" do
    state = %App{current_screen: :board_list, session_context: %{domain: %{posts: FakePosts}}}
    {opened, []} = App.update({:key, %{key: :char, char: "/"}}, state)
    {typed, []} = App.update({:key, %{key: :char, char: "h"}}, opened)
    {results, []} = App.update({:key, %{key: :enter}}, typed)

    assert results.command_entry.mode == :results

    {navigated, _cmds} = App.update({:key, %{key: :enter}}, results)
    assert navigated.command_entry == nil
    assert navigated.current_screen == :post_reader
    assert navigated.route_params.load_intent == {:around_message_number, 42}
  end

  test "direct address navigates and missing address reports non-enumerating feedback" do
    state = %App{current_screen: :board_list, session_context: %{domain: %{posts: FakePosts}}}
    {opened, []} = App.update({:key, %{key: :char, char: "/"}}, state)

    typed =
      Enum.reduce(String.graphemes("missing:99"), opened, fn char, acc ->
        {next, []} = App.update({:key, %{key: :char, char: char}}, acc)
        next
      end)

    {feedback, []} = App.update({:key, %{key: :enter}}, typed)
    assert feedback.command_entry.message == "Not found or not accessible."
  end
end

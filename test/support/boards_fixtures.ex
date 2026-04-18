defmodule FogletBbs.BoardsFixtures do
  @moduledoc "Fixtures for boards, threads, and posts tests."

  @doc "Create a category via Foglet.Boards.create_category/1."
  def category_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Category #{System.unique_integer([:positive])}",
          display_order: 0
        },
        attrs
      )

    {:ok, category} = Foglet.Boards.create_category(attrs)
    category
  end

  @doc """
  Create a board in a category via Foglet.Boards.create_board/2.
  Starts a Board Server automatically. Accepts a Category struct or a category_id binary.
  """
  def board_fixture(category_or_id, attrs \\ %{}) do
    category_id =
      case category_or_id do
        %Foglet.Boards.Category{id: id} -> id
        id when is_binary(id) -> id
      end

    attrs =
      Map.merge(
        %{
          slug: "board-#{System.unique_integer([:positive])}",
          name: "Board #{System.unique_integer([:positive])}",
          description: "Test board"
        },
        attrs
      )

    {:ok, board} = Foglet.Boards.create_board(category_id, attrs)
    board
  end

  @doc "Create a thread in a board. Requires a Board Server running for board.id."
  def thread_fixture(board, user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{title: "Thread #{System.unique_integer([:positive])}", body: "Root post body"},
        attrs
      )

    {:ok, %{thread: thread}} = Foglet.Threads.create_thread(board.id, user.id, attrs)
    thread
  end

  @doc "Create a post reply in a thread. Requires a Board Server running."
  def post_fixture(thread, user, attrs \\ %{}) do
    attrs = Map.merge(%{body: "Post body #{System.unique_integer([:positive])}"}, attrs)
    {:ok, post} = Foglet.Posts.create_reply(thread.id, thread.board_id, user.id, attrs)
    post
  end

  @doc "Create a user via Foglet.Accounts.register_user/1."
  def user_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          handle: "user#{System.unique_integer([:positive])}",
          email: "user#{System.unique_integer([:positive])}@test.com",
          password: "validpassword123"
        },
        attrs
      )

    {:ok, user} = Foglet.Accounts.register_user(attrs)
    user
  end

  @doc "Valid attrs for board creation."
  def valid_board_attributes(overrides \\ %{}) do
    Map.merge(
      %{
        slug: "board-#{System.unique_integer([:positive])}",
        name: "Test Board #{System.unique_integer([:positive])}",
        description: "A test board"
      },
      overrides
    )
  end

  @doc "Valid attrs for thread creation."
  def valid_thread_attributes(overrides \\ %{}) do
    Map.merge(%{title: "Test Thread #{System.unique_integer([:positive])}"}, overrides)
  end

  @doc "Valid attrs for post creation."
  def valid_post_attributes(overrides \\ %{}) do
    Map.merge(%{body: "# Hello\n\nThis is a test post."}, overrides)
  end
end

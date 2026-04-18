defmodule FogletBbs.BoardsFixtures do
  @moduledoc """
  Fixtures for boards, threads, and posts tests.

  Fixture implementations filled in by Plan 03 (contexts).
  Plan 01 creates the module skeleton so test files can reference it.
  """

  alias FogletBbs.AccountsFixtures

  @doc "Create a category. Raises until Plan 03 implements Foglet.Boards context."
  def category_fixture(_attrs \\ %{}) do
    raise "category_fixture/1 not implemented until Plan 03 wires Foglet.Boards.create_category/1"
  end

  @doc "Create a board in a category. Raises until Plan 03 is complete."
  def board_fixture(_category_or_attrs \\ %{}, _attrs \\ %{}) do
    raise "board_fixture/2 not implemented until Plan 03 wires Foglet.Boards.create_board/2"
  end

  @doc "Create a thread in a board. Raises until Plan 03 is complete."
  def thread_fixture(_board, _user \\ nil, _attrs \\ %{}) do
    raise "thread_fixture/3 not implemented until Plan 03 wires Foglet.Threads.create_thread/3"
  end

  @doc "Create a post reply. Raises until Plan 03 is complete."
  def post_fixture(_thread, _user \\ nil, _attrs \\ %{}) do
    raise "post_fixture/3 not implemented until Plan 03 wires Foglet.Posts.create_reply/3"
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

  @doc "Access to AccountsFixtures — boards tests need users too."
  defdelegate user_fixture(attrs \\ %{}), to: AccountsFixtures
end

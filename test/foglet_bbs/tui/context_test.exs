defmodule Foglet.TUI.ContextTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context
  alias Foglet.TUI.SessionContext

  describe "new/1" do
    test "builds the narrow screen-facing context with defaults" do
      assert %Context{
               current_user: nil,
               session_context: %SessionContext{},
               session_pid: nil,
               terminal_size: {80, 24},
               route: :login,
               route_params: %{},
               domain: %{}
             } = Context.new()
    end

    test "accepts only public runtime fields" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      context =
        Context.new(%{
          current_user: user,
          session_context: %{user: user},
          session_pid: self(),
          terminal_size: {132, 50},
          route: {:post_reader, %{thread_id: "t1"}},
          route_params: %{thread_id: "t1"},
          domain: %{posts: Foglet.Posts}
        })

      assert context.current_user == user
      assert context.session_context == %{user: user}
      assert context.session_pid == self()
      assert context.terminal_size == {132, 50}
      assert context.route == {:post_reader, %{thread_id: "t1"}}
      assert context.route_params == %{thread_id: "t1"}
      assert context.domain == %{posts: Foglet.Posts}
    end

    test "uses session_context domain unless domain is explicit" do
      assert %Context{domain: %{boards: Foglet.Boards}} =
               Context.new(session_context: %{domain: %{boards: Foglet.Boards}})

      assert %Context{domain: %{threads: Foglet.Threads}} =
               Context.new(
                 session_context: %{domain: %{boards: Foglet.Boards}},
                 domain: %{threads: Foglet.Threads}
               )
    end

    test "does not expose App-owned screen storage fields" do
      fields = Context.new() |> Map.from_struct()

      refute Map.has_key?(fields, :board_list)
      refute Map.has_key?(fields, :current_thread_list)
      refute Map.has_key?(fields, :posts)
      refute Map.has_key?(fields, :recent_oneliners)
      refute Map.has_key?(fields, :screen_state)
    end

    test "rejects App-owned screen storage fields in input" do
      for field <- [:board_list, :current_thread_list, :posts, :recent_oneliners, :screen_state] do
        assert_raise ArgumentError, ~r/unknown Foglet\.TUI\.Context field/, fn ->
          Context.new(%{field => []})
        end
      end
    end
  end
end

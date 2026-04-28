defmodule Foglet.TUI.EffectTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Effect

  describe "constructors" do
    test "navigate/2 carries the target screen and params" do
      assert %Effect{
               type: :navigate,
               payload: %{screen: :post_reader, params: %{thread_id: "t1"}}
             } = Effect.navigate(:post_reader, %{thread_id: "t1"})
    end

    test "task/3 carries operation, screen identity, and a lazy function" do
      owner = self()

      effect =
        Effect.task(:load_posts, :post_reader, fn ->
          send(owner, :task_ran)
          {:ok, [:post]}
        end)

      assert %Effect{
               type: :task,
               payload: %{op: :load_posts, screen_key: :post_reader, fun: fun}
             } = effect

      refute_received :task_ran
      assert fun.() == {:ok, [:post]}
      assert_received :task_ran
    end

    test "task/3 requires an atom operation and zero-arity function" do
      assert_raise FunctionClauseError, fn ->
        Effect.task("load_posts", :post_reader, fn -> :ok end)
      end

      assert_raise FunctionClauseError, fn ->
        Effect.task(:load_posts, :post_reader, fn _arg -> :ok end)
      end
    end

    test "open_modal/1 and dismiss_modal/0 carry modal operations" do
      modal = %{title: "Notice"}

      assert %Effect{type: :modal, payload: {:open, ^modal}} = Effect.open_modal(modal)
      assert %Effect{type: :modal, payload: :dismiss} = Effect.dismiss_modal()
    end

    test "publish/2 carries topic and message" do
      assert %Effect{
               type: :publish,
               payload: %{topic: "boards", message: {:created, :board}}
             } = Effect.publish("boards", {:created, :board})
    end

    test "session/1 carries a session process message" do
      pid = self()

      assert %Effect{type: :session, payload: {:heartbeat, ^pid}} =
               Effect.session({:heartbeat, pid})
    end

    test "terminal_size/1 carries a terminal size update" do
      assert %Effect{type: :terminal, payload: {:size, {120, 40}}} =
               Effect.terminal_size({120, 40})
    end

    test "quit/0 carries no payload" do
      assert %Effect{type: :quit, payload: nil} = Effect.quit()
    end
  end
end

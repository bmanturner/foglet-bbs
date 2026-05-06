defmodule Foglet.TUI.CommandTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Command, as: TUICommand

  describe "task/2" do
    test "success case: returned %Command{} struct has type :task" do
      cmd = TUICommand.task(:foo, fn -> {:bar, 1} end)
      assert %Raxol.Core.Runtime.Command{type: :task} = cmd
    end

    test "success case: invoking the command function produces the raw result" do
      cmd = TUICommand.task(:foo, fn -> {:bar, 1} end)
      result = cmd.data.()
      assert result == {:bar, 1}
    end

    test "error case: raising inside the closure returns {:task_error, op, reason}" do
      cmd = TUICommand.task(:foo, fn -> raise "boom" end)
      result = cmd.data.()
      assert {:task_error, :foo, reason} = result
      assert is_binary(reason)
      assert reason =~ "boom"
    end

    test "error case: throwing inside the closure returns {:task_error, op, reason}" do
      cmd = TUICommand.task(:bar, fn -> throw(:oops) end)
      result = cmd.data.()
      assert {:task_error, :bar, reason} = result
      assert is_binary(reason)
    end

    test "success case: return value passes through unchanged for non-tuple results" do
      cmd = TUICommand.task(:baz, fn -> 42 end)
      result = cmd.data.()
      assert result == 42
    end
  end

  describe "screen_task/4" do
    test "success case: wraps results for screen-scoped dispatch" do
      cmd = TUICommand.screen_task(:sample, :load, fn -> {:loaded, 1} end)

      assert %Raxol.Core.Runtime.Command{type: :task} = cmd
      assert cmd.data.() == {:screen_task_result, :sample, :load, {:ok, {:loaded, 1}}}
    end

    test "error case: returns sanitized screen result and reports failure metadata" do
      self = self()

      cmd =
        TUICommand.screen_task(:sample, :load, fn -> raise "secret boom" end, fn metadata ->
          send(self, {:failure, metadata})
        end)

      assert cmd.data.() ==
               {:screen_task_result, :sample, :load, {:error, {:task_failed, :exception}}}

      assert_receive {:failure,
                      %{
                        screen_key: :sample,
                        op: :load,
                        failure_kind: :exception,
                        reason: %RuntimeError{message: "secret boom"}
                      }}
    end
  end
end

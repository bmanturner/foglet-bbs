defmodule Foglet.TUI.Widgets.Modal.Form.SubmitStashTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  # Use a unique module key per test to avoid cross-test Process dict collisions.
  # We pass a unique atom derived from the test context to stash/pop calls.
  # (Tests in async: true may run in the same process via ExUnit.Case pool.)

  describe "stash/pop" do
    test "stash then pop returns the payload and clears it" do
      SubmitStash.stash(__MODULE__, {:test_payload, 1})
      result = SubmitStash.pop(__MODULE__)
      assert result == {:test_payload, 1}

      # Second pop must return nil — entry was cleared
      assert SubmitStash.pop(__MODULE__) == nil
    end

    test "pop on empty stash returns nil (no crash)" do
      # Key is unused in this test — no prior stash
      assert SubmitStash.pop(FakeModuleForEmptyTest) == nil
    end
  end

  describe "with_stashed/2" do
    test "runs function with the stashed payload and deletes it" do
      SubmitStash.stash(WithStashedTest.Success, %{name: "alice"})

      result =
        SubmitStash.with_stashed(WithStashedTest.Success, fn payload ->
          {:handled, payload}
        end)

      assert result == {:handled, %{name: "alice"}}
      # Verify cleanup happened
      assert SubmitStash.pop(WithStashedTest.Success) == nil
    end

    test "with_stashed/2 passes nil when nothing is stashed" do
      result =
        SubmitStash.with_stashed(WithStashedTest.Empty, fn payload ->
          payload
        end)

      assert result == nil
    end

    test "with_stashed/2 guarantees deletion even when the function raises" do
      SubmitStash.stash(WithStashedTest.Raise, :will_raise)

      assert_raise RuntimeError, fn ->
        SubmitStash.with_stashed(WithStashedTest.Raise, fn _payload ->
          raise "intentional test error"
        end)
      end

      # Entry must be cleaned up despite the raise
      assert SubmitStash.pop(WithStashedTest.Raise) == nil
    end
  end

  describe "namespace isolation" do
    test "two modules can stash concurrently without collision" do
      SubmitStash.stash(ModA, :payload_a)
      SubmitStash.stash(ModB, :payload_b)

      assert SubmitStash.pop(ModA) == :payload_a
      assert SubmitStash.pop(ModB) == :payload_b
    end
  end
end

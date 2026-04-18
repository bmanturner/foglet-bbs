defmodule Foglet.TUI.Screens.VerifyTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.TUI.Screens.Verify

  import FogletBbs.AccountsFixtures

  setup do
    user = user_fixture()
    {:ok, code} = Accounts.build_verify_code(user)

    state =
      %Foglet.TUI.App{
        current_screen: :verify,
        current_user: user,
        session_context: %{},
        terminal_size: {80, 24},
        verify_state: %{buffer: "", attempts: 0, cooldown_until: nil}
      }
      |> Map.from_struct()

    %{state: state, user: user, code: code}
  end

  describe "render/1 (D-08)" do
    test "renders without crashing", %{state: state} do
      assert _ = Verify.render(state)
    end
  end

  describe "handle_key character entry" do
    test "appends uppercase alphanumeric chars up to 6", %{state: state} do
      {:update, s, _} = Verify.handle_key(%{key: "a"}, state)
      assert s.verify_state.buffer == "A"

      {:update, s, _} = Verify.handle_key(%{key: "1"}, s)
      assert s.verify_state.buffer == "A1"
    end

    test "ignores input beyond 6 chars", %{state: state} do
      filled = %{state | verify_state: %{buffer: "ABCDEF", attempts: 0, cooldown_until: nil}}
      assert :no_match = Verify.handle_key(%{key: "G"}, filled)
    end

    test "backspace removes last char", %{state: state} do
      s = %{state | verify_state: %{buffer: "ABC", attempts: 0, cooldown_until: nil}}
      {:update, new, _} = Verify.handle_key(%{key: "backspace"}, s)
      assert new.verify_state.buffer == "AB"
    end
  end

  describe "submit via {:submit} event (D-12)" do
    test "correct code transitions to :main_menu", %{state: state, code: code} do
      s = %{state | verify_state: %{buffer: code, attempts: 0, cooldown_until: nil}}
      {new_state, _} = Verify.handle_verify_event({:submit}, s)
      assert new_state.current_screen == :main_menu
      assert new_state.current_user.confirmed_at != nil
      assert new_state.verify_state == nil
    end

    test "wrong code increments attempts + error modal", %{state: state} do
      s = %{state | verify_state: %{buffer: "WRONG1", attempts: 0, cooldown_until: nil}}
      {new_state, _} = Verify.handle_verify_event({:submit}, s)
      assert new_state.verify_state.attempts == 1
      assert new_state.verify_state.buffer == ""
      assert new_state.modal.type == :error
    end

    test "after 5 invalid attempts cooldown_until is set (D-10)", %{state: state} do
      final_state =
        Enum.reduce(1..5, state, fn _, acc ->
          s = %{acc | verify_state: %{acc.verify_state | buffer: "WRONG1"}}
          {new_state, _} = Verify.handle_verify_event({:submit}, s)
          new_state
        end)

      assert final_state.verify_state.attempts == 5
      assert final_state.verify_state.cooldown_until != nil
      assert DateTime.compare(final_state.verify_state.cooldown_until, DateTime.utc_now()) == :gt
    end

    test "during cooldown submit returns cooldown modal without incrementing", %{state: state} do
      future = DateTime.add(DateTime.utc_now(), 30, :second)
      s = %{state | verify_state: %{buffer: "ANYTHI", attempts: 5, cooldown_until: future}}

      {new_state, _} = Verify.handle_verify_event({:submit}, s)
      assert new_state.verify_state.attempts == 5
      assert new_state.modal.type == :error
      assert new_state.modal.message =~ "Wait"
    end
  end

  describe "resend ({:resend} event) (D-12)" do
    test "generates a new code and resets buffer + attempts", %{state: state} do
      s = %{state | verify_state: %{buffer: "STALE1", attempts: 3, cooldown_until: nil}}
      {new_state, _} = Verify.handle_verify_event({:resend}, s)
      assert new_state.verify_state.buffer == ""
      assert new_state.verify_state.attempts == 0
      assert new_state.modal.type == :info
    end
  end
end

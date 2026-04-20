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
        verify_state: %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
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
      {:update, s, _} = Verify.handle_key(%{key: :char, char: "a"}, state)
      assert s.verify_state.buffer == "A"

      {:update, s, _} = Verify.handle_key(%{key: :char, char: "1"}, s)
      assert s.verify_state.buffer == "A1"
    end

    test "ignores input beyond 6 chars", %{state: state} do
      filled = %{
        state
        | verify_state: %{
            buffer: "ABCDEF",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      assert :no_match = Verify.handle_key(%{key: :char, char: "G"}, filled)
    end

    test "backspace removes last char", %{state: state} do
      s = %{
        state
        | verify_state: %{
            buffer: "ABC",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      {:update, new, _} = Verify.handle_key(%{key: :backspace}, s)
      assert new.verify_state.buffer == "AB"
    end
  end

  describe "submit via {:submit} event (D-12)" do
    test "correct code transitions to :main_menu", %{state: state, code: code} do
      s = %{
        state
        | verify_state: %{
            buffer: code,
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      {new_state, _} = Verify.handle_verify_event({:submit}, s)
      assert new_state.current_screen == :main_menu
      assert new_state.current_user.confirmed_at != nil
      assert new_state.verify_state == nil
    end

    test "wrong code increments attempts + error modal", %{state: state} do
      s = %{
        state
        | verify_state: %{
            buffer: "WRONG1",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

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

      s = %{
        state
        | verify_state: %{
            buffer: "ANYTHI",
            attempts: 5,
            cooldown_until: future,
            resend_cooldown_until: nil
          }
      }

      {new_state, _} = Verify.handle_verify_event({:submit}, s)
      assert new_state.verify_state.attempts == 5
      assert new_state.modal.type == :error
      assert new_state.modal.message =~ "Wait"
    end
  end

  describe "resend ({:resend} event) (D-12)" do
    test "generates a new code and resets buffer + attempts", %{state: state} do
      s = %{
        state
        | verify_state: %{
            buffer: "STALE1",
            attempts: 3,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      {new_state, _} = Verify.handle_verify_event({:resend}, s)
      assert new_state.verify_state.buffer == ""
      assert new_state.verify_state.attempts == 0
      assert new_state.modal.type == :info
    end
  end

  describe "handle_key/2 — resend ordering (r must not append to buffer)" do
    test "'r' triggers resend, NOT append to buffer", %{state: state} do
      s = %{
        state
        | verify_state: %{
            buffer: "AB",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      # resend_code calls Accounts.build_verify_code which needs a real user (set in setup)
      result = Verify.handle_key(%{key: :char, char: "r"}, s)
      # Should be {:update, _, []} from resend — buffer should NOT be "ABR"
      assert {:update, new_state, []} = result

      refute new_state.verify_state.buffer == "ABR",
             "'r' was appended to buffer instead of triggering resend"
    end

    test "'R' triggers resend, NOT append to buffer", %{state: state} do
      s = %{
        state
        | verify_state: %{
            buffer: "AB",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      result = Verify.handle_key(%{key: :char, char: "R"}, s)
      assert {:update, new_state, []} = result
      refute new_state.verify_state.buffer == "ABR"
    end
  end

  describe "handle_key/2 — char validation and buffer limits" do
    test "typing 6 valid chars fills the buffer completely", %{state: state} do
      final =
        Enum.reduce(~w(A B C 1 2 3), state, fn char, acc ->
          {:update, new_acc, []} = Verify.handle_key(%{key: :char, char: char}, acc)
          new_acc
        end)

      assert final.verify_state.buffer == "ABC123"
    end

    test "valid chars are uppercased before appending", %{state: state} do
      {:update, s1, []} = Verify.handle_key(%{key: :char, char: "a"}, state)
      assert s1.verify_state.buffer == "A"

      {:update, s2, []} = Verify.handle_key(%{key: :char, char: "b"}, s1)
      assert s2.verify_state.buffer == "AB"
    end

    test "invalid chars (punctuation, space) are rejected and return :no_match", %{state: state} do
      assert :no_match = Verify.handle_key(%{key: :char, char: "!"}, state)
      assert :no_match = Verify.handle_key(%{key: :char, char: " "}, state)
      assert :no_match = Verify.handle_key(%{key: :char, char: "-"}, state)
    end

    test "buffer does not exceed 6 chars — 7th valid char is rejected", %{state: state} do
      filled = %{
        state
        | verify_state: %{
            buffer: "ABCDEF",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: nil
          }
      }

      assert :no_match = Verify.handle_key(%{key: :char, char: "G"}, filled)
      assert :no_match = Verify.handle_key(%{key: :char, char: "1"}, filled)
    end

    test "non-char keys like :up/:down return :no_match", %{state: state} do
      assert :no_match = Verify.handle_key(%{key: :up}, state)
      assert :no_match = Verify.handle_key(%{key: :down}, state)
    end
  end

  describe "resend cooldown — VERIFY-02 two-timer model" do
    setup do
      original =
        try do
          Foglet.Config.get!("email_verify_resend_cooldown_seconds")
        rescue
          _ -> :not_seeded
        end

      on_exit(fn ->
        case original do
          :not_seeded -> :ok
          value -> Foglet.Config.put!("email_verify_resend_cooldown_seconds", value)
        end
      end)

      :ok
    end

    test "successful resend sets resend_cooldown_until using config-driven duration",
         %{state: state} do
      Foglet.Config.put!("email_verify_resend_cooldown_seconds", 90)

      before = DateTime.utc_now()
      {new_state, _} = Foglet.TUI.Screens.Verify.handle_verify_event({:resend}, state)

      assert %DateTime{} = new_state.verify_state.resend_cooldown_until

      remaining =
        DateTime.diff(new_state.verify_state.resend_cooldown_until, before, :second)

      # Allow 1s of clock drift between the test's `before` capture and
      # DateTime.utc_now() inside resend_code_raw/1.
      assert remaining in 89..91,
             "Expected ~90s from before, got #{remaining}"
    end

    test "resend while resend_cooldown_until is active returns cooldown modal, no new code",
         %{state: state} do
      future = DateTime.add(DateTime.utc_now(), 30, :second)

      s = %{
        state
        | verify_state: %{
            buffer: "",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: future
          }
      }

      result = Foglet.TUI.Screens.Verify.handle_key(%{key: :char, char: "r"}, s)
      assert {:update, new_state, []} = result
      assert new_state.modal.type == :error
      assert new_state.modal.message =~ "wait"
      # resend_cooldown_until is NOT mutated by a blocked press
      assert new_state.verify_state.resend_cooldown_until == future
    end

    test "invalid-attempts cooldown does NOT block resend (two independent timers)",
         %{state: state} do
      # Simulate user hit invalid 5 times and is under cooldown_until lockout,
      # but resend_cooldown_until is nil.
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      s = %{
        state
        | verify_state: %{
            buffer: "",
            attempts: 5,
            cooldown_until: future,
            resend_cooldown_until: nil
          }
      }

      # The resend_code path should SUCCEED, setting resend_cooldown_until
      # and (per D-09) clearing cooldown_until + attempts as a side effect.
      {:update, new_state, []} =
        Foglet.TUI.Screens.Verify.handle_key(%{key: :char, char: "R"}, s)

      assert new_state.modal.type == :info
      assert %DateTime{} = new_state.verify_state.resend_cooldown_until
      assert new_state.verify_state.cooldown_until == nil
      assert new_state.verify_state.attempts == 0
      assert new_state.verify_state.buffer == ""
    end

    test "resend cooldown does NOT block typing a char (invalid-attempts cooldown unaffected)",
         %{state: state} do
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      s = %{
        state
        | verify_state: %{
            buffer: "",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: future
          }
      }

      # Typing "A" should append normally — the resend timer does NOT gate
      # code entry.
      {:update, new_state, _} =
        Foglet.TUI.Screens.Verify.handle_key(%{key: :char, char: "a"}, s)

      assert new_state.verify_state.buffer == "A"
      assert new_state.verify_state.resend_cooldown_until == future
    end

    test "missing config key defaults resend cooldown to 60s", %{state: state} do
      import Ecto.Query, only: [from: 2]

      case from(e in Foglet.Config.Entry, where: e.key == "email_verify_resend_cooldown_seconds")
           |> FogletBbs.Repo.delete_all() do
        {_, _} -> :ok
      end

      Foglet.Config.invalidate("email_verify_resend_cooldown_seconds")

      before = DateTime.utc_now()
      {new_state, _} = Foglet.TUI.Screens.Verify.handle_verify_event({:resend}, state)

      remaining =
        DateTime.diff(new_state.verify_state.resend_cooldown_until, before, :second)

      assert remaining in 59..61,
             "Expected ~60s default, got #{remaining}"
    end
  end
end

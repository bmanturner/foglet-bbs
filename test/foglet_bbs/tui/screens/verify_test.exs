defmodule Foglet.TUI.Screens.VerifyTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.Verification
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Verify
  alias Foglet.TUI.Screens.Verify.State, as: VerifyState

  import FogletBbs.AccountsFixtures
  import Swoosh.TestAssertions

  defmodule FakeVerification do
    def verify_email_code(user, code) do
      owner = Process.get(:fake_verify_owner)
      if owner, do: send(owner, {:verify_email_code, user, code})
      Process.get(:fake_verify_submit_result, {:error, :invalid_code})
    end

    def deliver_verification_code(user) do
      owner = Process.get(:fake_verify_owner)
      if owner, do: send(owner, {:deliver_verification_code, user})
      Process.get(:fake_verify_resend_result, {:error, :delivery_failed})
    end
  end

  defp verify_state(overrides \\ %{}) do
    Map.merge(VerifyState.default(), overrides)
  end

  defp context(user, extra \\ []) do
    Context.new(
      Keyword.merge(
        [
          current_user: user,
          session_context: %{},
          terminal_size: {80, 24}
        ],
        extra
      )
    )
  end

  defp fake_context(user) do
    context(user, domain: %{verification: FakeVerification})
  end

  defp task_effect(effects, op) do
    Enum.find(effects, &match?(%Effect{type: :task, payload: %{op: ^op}}, &1))
  end

  defp modal_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :modal, payload: {:open, _}}, &1))
  end

  defp session_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :session}, &1))
  end

  defp navigate_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :navigate}, &1))
  end

  defp run_task(%Effect{payload: %{fun: fun}}), do: fun.()

  setup do
    original_delivery_mode = Foglet.Config.get("delivery_mode", "no_email")
    original_resend_cooldown = Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)
    Foglet.Config.put!("delivery_mode", "email")
    Foglet.Config.put!("email_verify_resend_cooldown_seconds", 60)

    on_exit(fn ->
      Foglet.Config.put!("delivery_mode", original_delivery_mode)
      Foglet.Config.put!("email_verify_resend_cooldown_seconds", original_resend_cooldown)
      Foglet.Config.invalidate("delivery_mode")
      Foglet.Config.invalidate("email_verify_resend_cooldown_seconds")
    end)

    user = user_fixture()
    {:ok, code} = Verification.build_verify_code(user)
    %{user: user, code: code}
  end

  setup :set_swoosh_global

  describe "init/render" do
    test "Verify.init/1 builds default code-entry state", %{user: user} do
      assert Verify.init(context(user)) == VerifyState.default()
    end

    test "Verify.render/2 renders local state without App-shaped input", %{user: user} do
      assert Verify.render(Verify.init(context(user)), context(user))
    end
  end

  describe "code entry reducer" do
    test "character entry uppercases alphanumeric chars up to six", %{user: user} do
      {state, []} = Verify.update({:key, %{key: :char, char: "a"}}, verify_state(), context(user))
      assert state.buffer == "A"

      final =
        Enum.reduce(~w(1 b 2 c 3), state, fn char, acc ->
          {next, []} = Verify.update({:key, %{key: :char, char: char}}, acc, context(user))
          next
        end)

      assert final.buffer == "A1B2C3"

      {unchanged, []} =
        Verify.update({:key, %{key: :char, char: "Z"}}, final, context(user))

      assert unchanged.buffer == "A1B2C3"
    end

    test "invalid characters are ignored without effects", %{user: user} do
      {state, []} = Verify.update({:key, %{key: :char, char: "!"}}, verify_state(), context(user))
      assert state.buffer == ""
    end

    test "backspace removes the last character", %{user: user} do
      {state, []} =
        Verify.update({:key, %{key: :backspace}}, verify_state(%{buffer: "ABC"}), context(user))

      assert state.buffer == "AB"
    end

    test "escape requests navigation back to login", %{user: user} do
      {state, effects} = Verify.update({:key, %{key: :escape}}, verify_state(), context(user))

      assert state == VerifyState.default()
      assert %Effect{type: :navigate, payload: %{screen: :login}} = navigate_effect(effects)
    end

    test "{:verify, {:set_buffer, code}} updates the buffer directly", %{user: user} do
      {state, []} =
        Verify.update({:verify, {:set_buffer, "ABC123"}}, verify_state(), context(user))

      assert state.buffer == "ABC123"
    end
  end

  describe "submit reducer and outcomes" do
    test "enter with a complete code requests a verify_submit task", %{user: user} do
      {state, effects} =
        Verify.update(
          {:key, %{key: :enter}},
          verify_state(%{buffer: "ABC123"}),
          fake_context(user)
        )

      assert state.buffer == "ABC123"

      assert %Effect{type: :task, payload: %{op: :verify_submit, screen_key: :verify}} =
               task_effect(effects, :verify_submit)
    end

    test "correct code promotes the verified user through a session effect", %{
      user: user,
      code: code
    } do
      {state, effects} =
        Verify.update({:verify, :submit}, verify_state(%{buffer: code}), context(user))

      result = run_task(task_effect(effects, :verify_submit))

      {state, effects} =
        Verify.update({:task_result, :verify_submit, {:ok, result}}, state, context(user))

      assert state == VerifyState.default()

      assert %Effect{type: :session, payload: {:promote_session, confirmed}} =
               session_effect(effects)

      assert confirmed.confirmed_at != nil
    end

    test "invalid code increments attempts and clears the buffer", %{user: user} do
      {state, effects} =
        Verify.update(
          {:task_result, :verify_submit, {:ok, {:error, :invalid_code}}},
          verify_state(%{buffer: "WRONG1"}),
          context(user)
        )

      assert state.attempts == 1
      assert state.buffer == ""
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
    end

    test "expired code clears the buffer without incrementing attempts", %{user: user} do
      {state, effects} =
        Verify.update(
          {:task_result, :verify_submit, {:ok, {:error, :expired}}},
          verify_state(%{buffer: "OLD123", attempts: 2}),
          context(user)
        )

      assert state.buffer == ""
      assert state.attempts == 2
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
    end

    test "after five invalid attempts cooldown_until is set", %{user: user} do
      final_state =
        Enum.reduce(1..5, verify_state(%{buffer: "WRONG1"}), fn _, acc ->
          {state, _effects} =
            Verify.update(
              {:task_result, :verify_submit, {:ok, {:error, :invalid_code}}},
              %{acc | buffer: "WRONG1"},
              context(user)
            )

          state
        end)

      assert final_state.attempts == 5
      assert %DateTime{} = final_state.cooldown_until
      assert DateTime.compare(final_state.cooldown_until, DateTime.utc_now()) == :gt
    end

    test "active invalid-attempt cooldown blocks submit without incrementing", %{user: user} do
      future = DateTime.add(DateTime.utc_now(), 30, :second)

      {state, effects} =
        Verify.update(
          {:verify, :submit},
          verify_state(%{buffer: "ABC123", attempts: 5, cooldown_until: future}),
          context(user)
        )

      assert state.attempts == 5
      assert state.cooldown_until == future
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
    end

    test "submit with no user opens error modal and requests login navigation" do
      {state, effects} =
        Verify.update({:verify, :submit}, verify_state(%{buffer: "ABC123"}), context(nil))

      assert state == VerifyState.default()
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
      assert %Effect{type: :navigate, payload: %{screen: :login}} = navigate_effect(effects)
    end
  end

  describe "resend reducer and outcomes" do
    test "Ctrl+R requests a verify_resend task while bare R enters the buffer", %{user: user} do
      {state, effects} =
        Verify.update(
          {:key, %{key: :char, char: "r", ctrl: true}},
          verify_state(),
          fake_context(user)
        )

      # Optimistic dispatch-time cooldown so a fast second Ctrl+R lands on
      # the cooldown branch instead of firing a duplicate task (FOG-64 row 11).
      assert state.buffer == ""
      assert state.attempts == 0
      assert %DateTime{} = state.resend_cooldown_until

      assert %Effect{type: :task, payload: %{op: :verify_resend, screen_key: :verify}} =
               task_effect(effects, :verify_resend)

      {state, []} = Verify.update({:key, %{key: :char, char: "r"}}, verify_state(), context(user))
      assert state.buffer == "R"
    end

    test "successful resend resets attempts and sets resend cooldown", %{user: user} do
      Foglet.Config.put!("email_verify_resend_cooldown_seconds", 90)

      before = DateTime.utc_now()

      {state, effects} =
        Verify.update(
          {:verify, :resend},
          verify_state(%{buffer: "STALE1", attempts: 3}),
          context(user)
        )

      # Cooldown is set optimistically at dispatch time (FOG-64 row 11),
      # so it is already populated before the task result lands.
      assert state.buffer == ""
      assert state.attempts == 0
      assert state.cooldown_until == nil
      assert %DateTime{} = state.resend_cooldown_until
      assert DateTime.diff(state.resend_cooldown_until, before, :second) in 89..91

      result = run_task(task_effect(effects, :verify_resend))

      {state, effects} =
        Verify.update({:task_result, :verify_resend, {:ok, result}}, state, context(user))

      assert state.buffer == ""
      assert state.attempts == 0
      assert state.cooldown_until == nil
      assert %DateTime{} = state.resend_cooldown_until
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :info
      assert modal.message =~ "You can request another in"
      assert_email_sent(subject: "Your Foglet verification code")
    end

    test "resend failure clears optimistic cooldown so the user can retry", %{user: user} do
      Process.put(:fake_verify_owner, self())
      Process.put(:fake_verify_resend_result, {:error, :delivery_failed})
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      {state, effects} =
        Verify.update(
          {:verify, :resend},
          verify_state(%{resend_cooldown_until: nil, cooldown_until: future}),
          fake_context(user)
        )

      # Optimistic cooldown applied at dispatch (FOG-64 row 11) — buffer is
      # cleared by `after_resend/2` regardless of eventual delivery outcome.
      assert state.buffer == ""
      assert %DateTime{} = state.resend_cooldown_until

      result = run_task(task_effect(effects, :verify_resend))

      {state, effects} =
        Verify.update({:task_result, :verify_resend, {:ok, result}}, state, context(user))

      # On failure, drop the optimistic resend cooldown so the user is not
      # locked out waiting for a request that never landed. The pre-existing
      # invalid-attempts `cooldown_until` is cleared by `after_resend/2` at
      # dispatch (FOG-64), so it stays nil here regardless of outcome.
      assert state.cooldown_until == nil
      assert state.resend_cooldown_until == nil
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
      assert_received {:deliver_verification_code, ^user}
    end

    test "active resend cooldown blocks resend without mutating timers", %{user: user} do
      future = DateTime.add(DateTime.utc_now(), 30, :second)

      {state, effects} =
        Verify.update(
          {:verify, :resend},
          verify_state(%{resend_cooldown_until: future}),
          context(user)
        )

      assert state.resend_cooldown_until == future
      refute task_effect(effects, :verify_resend)
      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error
    end

    test "resend cooldown does not block code entry", %{user: user} do
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      {state, []} =
        Verify.update(
          {:key, %{key: :char, char: "a"}},
          verify_state(%{resend_cooldown_until: future}),
          context(user)
        )

      assert state.buffer == "A"
      assert state.resend_cooldown_until == future
    end
  end
end

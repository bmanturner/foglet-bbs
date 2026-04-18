defmodule Foglet.TUI.Screens.RegisterTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.TUI.Screens.Register

  import FogletBbs.AccountsFixtures

  defp base_state(mode) do
    step = if mode == "invite_only", do: :invite_code, else: :handle

    %Foglet.TUI.App{
      current_screen: :register,
      session_context: %{registration_mode: mode},
      terminal_size: {80, 24},
      register_wizard: %{mode: mode, step: step, data: %{}, error: nil}
    }
    |> Map.from_struct()
  end

  describe "render/1" do
    test "renders without crashing for each mode" do
      for mode <- ["open", "invite_only", "sysop_approved"] do
        assert _ = Register.render(base_state(mode))
      end
    end
  end

  describe "wizard sequence (D-23)" do
    test "open mode: handle → email → password → :verify" do
      state = base_state("open")
      attrs = valid_user_attributes()
      handle = attrs[:handle] || attrs["handle"]
      email = attrs[:email] || attrs["email"]
      password = attrs[:password] || attrs["password"]

      {state, _} = Register.handle_wizard_event({:submit_step, :handle, handle}, state)
      assert state.register_wizard.step == :email

      {state, _} = Register.handle_wizard_event({:submit_step, :email, email}, state)
      assert state.register_wizard.step == :password

      {state, _} = Register.handle_wizard_event({:submit_step, :password, password}, state)

      assert state.current_screen == :verify
      assert state.current_user != nil
      assert state.register_wizard == nil
      assert state.verify_state == %{buffer: "", attempts: 0, cooldown_until: nil}
    end

    test "invite_only mode: rejects empty/invalid invite_code before handle step" do
      state = base_state("invite_only")

      {state, _} = Register.handle_wizard_event({:submit_step, :invite_code, ""}, state)
      assert state.register_wizard.step == :invite_code
      assert state.register_wizard.error != nil
    end

    test "invite_only mode: accepts non-empty alphanumeric invite_code (dev default)" do
      state = base_state("invite_only")

      {state, _} = Register.handle_wizard_event({:submit_step, :invite_code, "ABC123"}, state)
      assert state.register_wizard.step == :handle
    end

    test "sysop_approved mode: calls register_pending_user and emits terminate_after_modal (D-05, D-07)" do
      state = base_state("sysop_approved")
      attrs = valid_user_attributes()
      handle = attrs[:handle] || attrs["handle"]
      email = attrs[:email] || attrs["email"]
      password = attrs[:password] || attrs["password"]

      {state, _} = Register.handle_wizard_event({:submit_step, :handle, handle}, state)
      {state, _} = Register.handle_wizard_event({:submit_step, :email, email}, state)
      {state, cmds} = Register.handle_wizard_event({:submit_step, :password, password}, state)

      assert %{status: :pending} = Foglet.Accounts.get_user_by_handle(handle)
      assert Enum.any?(cmds, &match?({:terminate_after_modal, :pending_approval}, &1))
      assert %{message: msg, type: :info} = state.modal
      assert msg =~ "pending"
    end

    test "SSH keys are NEVER part of the wizard (D-24)" do
      state = base_state("open")

      steps =
        [state.register_wizard.step] ++
          Enum.flat_map(
            [{:handle, "alice123"}, {:email, "alice@example.com"}, {:password, "supersecret123"}],
            fn {step, value} ->
              {new_state, _} = Register.handle_wizard_event({:submit_step, step, value}, state)
              [new_state.register_wizard && new_state.register_wizard.step]
            end
          )

      refute Enum.any?(steps, &(&1 == :ssh_key))
    end
  end

  describe "cancel" do
    test "{:cancel} resets wizard and returns to :login" do
      state = base_state("open")
      {new_state, _} = Register.handle_wizard_event({:cancel}, state)
      assert new_state.current_screen == :login
      assert new_state.register_wizard == nil
    end
  end
end

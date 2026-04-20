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
      register_wizard: %{mode: mode, step: step, data: %{}, error: nil, current_input: ""}
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

      assert state.verify_state == %{
               buffer: "",
               attempts: 0,
               cooldown_until: nil,
               resend_cooldown_until: nil
             }
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

  describe "submit/2 — VERIFY-01 post-registration routing" do
    setup do
      original =
        try do
          Foglet.Config.get!("require_email_verification")
        rescue
          _ -> :not_seeded
        end

      on_exit(fn ->
        case original do
          :not_seeded -> :ok
          value -> Foglet.Config.put!("require_email_verification", value)
        end
      end)

      :ok
    end

    test "open mode + toggle=true routes to :verify with verify_state including resend_cooldown_until" do
      Foglet.Config.put!("require_email_verification", true)

      attrs = valid_user_attributes(%{password: "letmein12"})
      handle = attrs[:handle] || attrs["handle"]
      email = attrs[:email] || attrs["email"]
      password = attrs[:password] || attrs["password"]

      state = base_state("open")
      {state, _} = Register.handle_wizard_event({:submit_step, :handle, handle}, state)
      {state, _} = Register.handle_wizard_event({:submit_step, :email, email}, state)
      {state, cmds} = Register.handle_wizard_event({:submit_step, :password, password}, state)

      assert state.current_screen == :verify
      assert state.current_user != nil
      assert state.current_user.handle == handle
      assert state.register_wizard == nil
      assert Map.has_key?(state.verify_state, :resend_cooldown_until)
      assert state.verify_state.resend_cooldown_until == nil
      assert state.verify_state.buffer == ""
      assert state.verify_state.attempts == 0
      assert state.verify_state.cooldown_until == nil
      assert cmds == []
    end

    test "open mode + toggle=false routes to :main_menu via {:promote_session, user}" do
      Foglet.Config.put!("require_email_verification", false)

      attrs = valid_user_attributes(%{password: "letmein12"})
      handle = attrs[:handle] || attrs["handle"]
      email = attrs[:email] || attrs["email"]
      password = attrs[:password] || attrs["password"]

      state = base_state("open")
      {state, _} = Register.handle_wizard_event({:submit_step, :handle, handle}, state)
      {state, _} = Register.handle_wizard_event({:submit_step, :email, email}, state)
      {state, cmds} = Register.handle_wizard_event({:submit_step, :password, password}, state)

      assert [{:promote_session, returned_user}] = cmds
      assert returned_user.handle == handle
      assert state.current_user != nil
      assert state.current_user.id == returned_user.id
      assert state.register_wizard == nil
      # The :main_menu branch does NOT touch current_screen inline — app.ex's
      # handler for {:promote_session, _} does. So state.current_screen may
      # remain :register until the command runs through App.update/2.
      # What matters here: no verify_state was built, no :verify code logged.
      assert Map.get(state, :verify_state) == nil or
               Map.get(state, :verify_state) ==
                 %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
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

  describe "handle_key/2 — character input" do
    test "typing a single char appends to current_input" do
      state = base_state("open")
      {:update, new_state, []} = Register.handle_key(%{key: :char, char: "a"}, state)
      assert new_state.register_wizard.current_input == "a"
    end

    test "typing multiple chars builds up current_input" do
      state = base_state("open")
      {:update, s1, []} = Register.handle_key(%{key: :char, char: "a"}, state)
      {:update, s2, []} = Register.handle_key(%{key: :char, char: "l"}, s1)
      {:update, s3, []} = Register.handle_key(%{key: :char, char: "i"}, s2)
      assert s3.register_wizard.current_input == "ali"
    end

    test "spacebar appends a literal space to current_input" do
      state = base_state("open")
      {:update, s1, []} = Register.handle_key(%{key: :char, char: "h"}, state)
      {:update, s2, []} = Register.handle_key(%{key: :char, char: " "}, s1)
      {:update, s3, []} = Register.handle_key(%{key: :char, char: "i"}, s2)
      assert s3.register_wizard.current_input == "h i"
    end

    test "backspace removes the last char from current_input" do
      state = %{
        base_state("open")
        | register_wizard: %{
            mode: "open",
            step: :handle,
            data: %{},
            error: nil,
            current_input: "abc"
          }
      }

      {:update, new_state, []} = Register.handle_key(%{key: :backspace}, state)
      assert new_state.register_wizard.current_input == "ab"
    end

    test "backspace on empty current_input is a no-op (stays empty)" do
      state = base_state("open")
      {:update, new_state, []} = Register.handle_key(%{key: :backspace}, state)
      assert new_state.register_wizard.current_input == ""
    end

    test "enter dispatches {:register_wizard, {:submit_step, step, value}} as a command" do
      state = %{
        base_state("open")
        | register_wizard: %{
            mode: "open",
            step: :handle,
            data: %{},
            error: nil,
            current_input: "myhandle"
          }
      }

      {:update, _new_state, cmds} = Register.handle_key(%{key: :enter}, state)
      assert Enum.member?(cmds, {:register_wizard, {:submit_step, :handle, "myhandle"}})
    end

    test "enter with empty input dispatches submit_step with empty string" do
      state = base_state("open")
      {:update, _new_state, cmds} = Register.handle_key(%{key: :enter}, state)
      assert Enum.member?(cmds, {:register_wizard, {:submit_step, :handle, ""}})
    end

    test "escape cancels wizard and returns to :login" do
      state = base_state("open")
      {:update, new_state, []} = Register.handle_key(%{key: :escape}, state)
      assert new_state.current_screen == :login
      assert new_state.register_wizard == nil
    end

    test "non-char keys (e.g. :up) return :no_match" do
      state = base_state("open")
      assert :no_match = Register.handle_key(%{key: :up}, state)
    end
  end

  describe "handle_wizard_event/2 — step advancement resets current_input" do
    test "advancing from :handle to :email resets current_input to empty" do
      state = base_state("open")
      {new_state, _} = Register.handle_wizard_event({:submit_step, :handle, "myhandle"}, state)
      assert new_state.register_wizard.step == :email
      assert new_state.register_wizard.current_input == ""
    end

    test "advancing from :email to :password resets current_input to empty" do
      state = %{
        base_state("open")
        | register_wizard: %{
            mode: "open",
            step: :email,
            data: %{handle: "myhandle"},
            error: nil,
            current_input: "typed@email.com"
          }
      }

      {new_state, _} =
        Register.handle_wizard_event({:submit_step, :email, "typed@email.com"}, state)

      assert new_state.register_wizard.step == :password
      assert new_state.register_wizard.current_input == ""
    end
  end
end

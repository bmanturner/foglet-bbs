defmodule Foglet.TUI.Screens.RegisterTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.TUI.Screens.Register
  alias Foglet.TUI.Widgets.Input.TextInput

  # Moves cursor to end so subsequent :backspace tests behave like a user who
  # just finished typing (Phase 1 pattern verbatim).
  defp text_input_at_end(ti) do
    {ti_end, _action} = TextInput.handle_event(%{key: :end}, ti)
    ti_end
  end

  # Pre-init screen_state-free state — register.ex self-initializes on first
  # get_register_ss/1 call (D-06). screen_state is an empty map.
  defp base_state(mode \\ "open") do
    %Foglet.TUI.App{
      current_screen: :register,
      current_user: nil,
      session_context: %{registration_mode: mode},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  # Seeds screen_state[:register] for tests that don't want to run the wizard
  # through the invite_code step first. fields is a keyword list:
  # [handle: "alice", email: "a@b.c", password: "sekret", confirm: "sekret",
  #  invite_code: "CODE", error: nil, collected: %{invite_code: "CODE"}]
  defp combined_state(fields \\ [], focused \\ :handle, mode \\ "open") do
    handle_input =
      TextInput.init(value: Keyword.get(fields, :handle, "")) |> text_input_at_end()

    email_input =
      TextInput.init(value: Keyword.get(fields, :email, "")) |> text_input_at_end()

    password_input =
      TextInput.init(value: Keyword.get(fields, :password, ""), mask_char: "*")
      |> text_input_at_end()

    confirm_input =
      TextInput.init(value: Keyword.get(fields, :confirm, ""), mask_char: "*")
      |> text_input_at_end()

    reg = %{
      mode: mode,
      step: :combined,
      focused_field: focused,
      invite_code_input: TextInput.init([]),
      handle_input: handle_input,
      email_input: email_input,
      password_input: password_input,
      confirm_input: confirm_input,
      collected: Keyword.get(fields, :collected, %{}),
      error: Keyword.get(fields, :error, nil)
    }

    %Foglet.TUI.App{
      current_screen: :register,
      current_user: nil,
      session_context: %{registration_mode: mode},
      terminal_size: {80, 24},
      screen_state: %{register: reg}
    }
    |> Map.from_struct()
  end

  # Seeds screen_state[:register] on the :invite_code step for invite_only tests.
  defp invite_state(fields \\ []) do
    invite_code_input =
      TextInput.init(value: Keyword.get(fields, :invite_code, "")) |> text_input_at_end()

    reg = %{
      mode: "invite_only",
      step: :invite_code,
      focused_field: :invite_code,
      invite_code_input: invite_code_input,
      handle_input: TextInput.init([]),
      email_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      confirm_input: TextInput.init(mask_char: "*"),
      collected: %{},
      error: Keyword.get(fields, :error, nil)
    }

    %Foglet.TUI.App{
      current_screen: :register,
      current_user: nil,
      session_context: %{registration_mode: "invite_only"},
      terminal_size: {80, 24},
      screen_state: %{register: reg}
    }
    |> Map.from_struct()
  end

  describe "init_screen_state/1 (AUDIT-19)" do
    test "returns minimal open-mode stub with four TextInput structs" do
      ss = Register.init_screen_state([])
      assert ss.mode == "open"
      assert ss.step == :combined
      assert ss.focused_field == :handle
      assert match?(%TextInput{}, ss.invite_code_input)
      assert match?(%TextInput{}, ss.handle_input)
      assert match?(%TextInput{}, ss.email_input)
      assert match?(%TextInput{}, ss.password_input)
      assert match?(%TextInput{}, ss.confirm_input)
      assert ss.password_input.raxol_state.mask_char == "*"
      assert ss.confirm_input.raxol_state.mask_char == "*"
      assert ss.collected == %{}
      assert ss.error == nil
    end

    test "accepts opts but ignores them" do
      assert Register.init_screen_state(foo: :bar).mode == "open"
    end
  end

  describe "render/1" do
    test "renders :combined step in open mode (no crash, returns non-nil)" do
      assert Register.render(base_state("open")) != nil
    end

    test "renders :invite_code step in invite_only mode" do
      assert Register.render(base_state("invite_only")) != nil
    end
  end

  describe "handle_key/2 — :escape" do
    test "escape from :combined step returns to :login and clears screen_state[:register]" do
      state = combined_state([handle: "alice"], :handle)
      {:update, new_state, []} = Register.handle_key(%{key: :escape}, state)
      assert new_state.current_screen == :login
      assert Map.get(new_state.screen_state || %{}, :register) == nil
    end

    test "escape from :invite_code step returns to :login and clears screen_state[:register]" do
      state = invite_state(invite_code: "ABC")
      {:update, new_state, []} = Register.handle_key(%{key: :escape}, state)
      assert new_state.current_screen == :login
      assert Map.get(new_state.screen_state || %{}, :register) == nil
    end
  end

  describe "handle_key/2 — :tab cycling on :combined step (D-02)" do
    test "tab from :handle advances focus to :email" do
      state = combined_state([], :handle)
      {:update, new_state, []} = Register.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :email
    end

    test "tab from :email advances to :password" do
      state = combined_state([], :email)
      {:update, new_state, []} = Register.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :password
    end

    test "tab from :password advances to :confirm_password" do
      state = combined_state([], :password)
      {:update, new_state, []} = Register.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :confirm_password
    end

    test "tab from :confirm_password wraps to :handle" do
      state = combined_state([], :confirm_password)
      {:update, new_state, []} = Register.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :handle
    end
  end

  describe "handle_key/2 — :enter on :combined step (D-02, D-03)" do
    test "enter on :handle advances focus to :email (no submit)" do
      state = combined_state([handle: "alice"], :handle)
      {:update, new_state, cmds} = Register.handle_key(%{key: :enter}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :email
      assert cmds == []
    end

    test "enter on :email advances focus to :password" do
      state = combined_state([email: "a@b.c"], :email)
      {:update, new_state, cmds} = Register.handle_key(%{key: :enter}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :password
      assert cmds == []
    end

    test "enter on :password advances focus to :confirm_password" do
      state = combined_state([password: "sekret01"], :password)
      {:update, new_state, cmds} = Register.handle_key(%{key: :enter}, state)
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :confirm_password
      assert cmds == []
    end

    test "enter on :confirm_password with matching passwords clears error and proceeds to submit path" do
      state =
        combined_state(
          [handle: "alice", email: "a@b.c", password: "sekret01", confirm: "sekret01"],
          :confirm_password
        )

      result = Register.handle_key(%{key: :enter}, state)
      assert match?({:update, _, _}, result)
      {:update, result_state, _commands} = result
      assert get_in(result_state, [:screen_state, :register, :error]) != "Passwords do not match."
    end
  end

  describe "handle_key/2 — :enter on :confirm_password with mismatched passwords (D-03, Pitfall 3)" do
    test "sets error 'Passwords do not match.' and stays on :confirm_password" do
      state = combined_state([password: "sekret01", confirm: "different"], :confirm_password)
      {:update, new_state, []} = Register.handle_key(%{key: :enter}, state)

      assert get_in(new_state, [:screen_state, :register, :error]) == "Passwords do not match."

      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :confirm_password

      assert new_state.current_screen == :register
    end
  end

  describe "handle_key/2 — character input delegation (D-06)" do
    test "typing a char on :handle appends to handle_input" do
      state = combined_state([], :handle)
      {:update, new_state, []} = Register.handle_key(%{key: :char, char: "a"}, state)

      assert get_in(new_state, [
               :screen_state,
               :register,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"
    end

    test "typing a char on :email appends to email_input" do
      state = combined_state([], :email)
      {:update, new_state, []} = Register.handle_key(%{key: :char, char: "b"}, state)

      assert get_in(new_state, [
               :screen_state,
               :register,
               :email_input,
               Access.key(:raxol_state),
               :value
             ]) == "b"
    end

    test "typing a char on :password appends to password_input (masked in render, raw in struct)" do
      state = combined_state([], :password)
      {:update, new_state, []} = Register.handle_key(%{key: :char, char: "a"}, state)

      assert get_in(new_state, [
               :screen_state,
               :register,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"
    end

    test "backspace on :handle removes the last char" do
      state = combined_state([handle: "abc"], :handle)
      {:update, new_state, []} = Register.handle_key(%{key: :backspace}, state)

      assert get_in(new_state, [
               :screen_state,
               :register,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "ab"
    end
  end

  describe "handle_key/2 — character input on :invite_code step" do
    test "typing on :invite_code step appends to invite_code_input" do
      state = invite_state([])
      {:update, new_state, []} = Register.handle_key(%{key: :char, char: "X"}, state)

      assert get_in(new_state, [
               :screen_state,
               :register,
               :invite_code_input,
               Access.key(:raxol_state),
               :value
             ]) == "X"
    end

    test "enter on :invite_code step emits {:register_wizard, {:submit_step, :invite_code, value}} command" do
      state = invite_state(invite_code: "ABC123")
      {:update, _state, commands} = Register.handle_key(%{key: :enter}, state)

      assert Enum.any?(
               commands,
               fn c -> match?({:register_wizard, {:submit_step, :invite_code, "ABC123"}}, c) end
             )
    end
  end

  describe "handle_wizard_event/2 — {:cancel}" do
    test "clears screen_state[:register] and transitions to :login" do
      state = combined_state(handle: "alice")
      {new_state, []} = Register.handle_wizard_event({:cancel}, state)
      assert new_state.current_screen == :login
      assert Map.get(new_state.screen_state || %{}, :register) == nil
    end
  end

  describe "handle_wizard_event/2 — {:submit_step, :invite_code, value}" do
    test "valid invite_code advances to :combined step, stores code in :collected, focused_field becomes :handle" do
      state = invite_state(invite_code: "VALIDCODE1")

      {new_state, []} =
        Register.handle_wizard_event({:submit_step, :invite_code, "VALIDCODE1"}, state)

      assert get_in(new_state, [:screen_state, :register, :step]) == :combined
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :handle

      assert get_in(new_state, [:screen_state, :register, :collected, :invite_code]) ==
               "VALIDCODE1"

      assert get_in(new_state, [:screen_state, :register, :error]) == nil
    end

    test "invalid invite_code (too short / contains punctuation) stays on :invite_code with error" do
      state = invite_state(invite_code: "no")
      {new_state, _cmds} = Register.handle_wizard_event({:submit_step, :invite_code, "no"}, state)
      assert get_in(new_state, [:screen_state, :register, :step]) == :invite_code
      assert get_in(new_state, [:screen_state, :register, :error]) != nil
    end

    test "empty invite_code stays on :invite_code with error" do
      state = invite_state(invite_code: "")
      {new_state, _cmds} = Register.handle_wizard_event({:submit_step, :invite_code, ""}, state)
      assert get_in(new_state, [:screen_state, :register, :step]) == :invite_code
      assert get_in(new_state, [:screen_state, :register, :error]) != nil
    end
  end

  describe "handle_wizard_event/2 — {:submit_step, :combined, _}" do
    test "is a no-op passthrough (submit runs inline in handle_combined_key/2 per D-02)" do
      state = combined_state([handle: "alice"], :confirm_password)
      {new_state, []} = Register.handle_wizard_event({:submit_step, :combined, ""}, state)
      assert new_state.current_screen == :register
    end
  end

  describe "mode selection (D-04, D-06)" do
    test "open mode: first render self-inits on :combined step with focused_field :handle" do
      {:update, state_after_key, _} = Register.handle_key(%{key: :tab}, base_state("open"))
      assert get_in(state_after_key, [:screen_state, :register, :step]) == :combined
      assert get_in(state_after_key, [:screen_state, :register, :focused_field]) == :email
    end

    test "invite_only mode: first access self-inits on :invite_code step with focused_field :invite_code" do
      {:update, new_state, _} =
        Register.handle_key(%{key: :char, char: "X"}, base_state("invite_only"))

      assert get_in(new_state, [:screen_state, :register, :step]) == :invite_code
      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :invite_code
    end

    test "sysop_approved mode: first access self-inits on :combined step (no :invite_code step)" do
      {:update, new_state, _} = Register.handle_key(%{key: :tab}, base_state("sysop_approved"))
      assert get_in(new_state, [:screen_state, :register, :step]) == :combined
    end
  end

  # WR-03: Integration test verifying the full App-level round-trip for the
  # :invite_code step. Exercises the path:
  #   handle_key(:enter) → {:register_wizard, {:submit_step, :invite_code, value}}
  #     → App.process_screen_commands → do_update({:register_wizard, ...})
  #       → handle_wizard_event → {new_state, []} with step == :combined
  # This catches any contract drift between handle_wizard_event's return shape
  # and do_update's expectations (e.g., wrapping in {:ok, ...} would silently
  # drop the state transition and leave the wizard stuck on :invite_code).
  describe "App.update/2 round-trip — invite_code step (WR-03)" do
    test "pressing enter on a valid invite code advances state to :combined step via App.update" do
      alias Foglet.TUI.App

      # Build state with :invite_code step and a pre-typed valid code.
      state = invite_state(invite_code: "VALIDCODE1")

      # App.update returns {new_state, commands}.
      {new_state, _commands} = App.update({:key, %{key: :enter}}, state)

      assert get_in(new_state, [:screen_state, :register, :step]) == :combined,
             "expected step to advance to :combined after valid invite code, " <>
               "got: #{inspect(get_in(new_state, [:screen_state, :register, :step]))}"

      assert get_in(new_state, [:screen_state, :register, :focused_field]) == :handle,
             "expected focused_field to be :handle after advancing to :combined"

      assert get_in(new_state, [:screen_state, :register, :collected, :invite_code]) ==
               "VALIDCODE1",
             "expected invite_code to be stored in :collected"
    end
  end
end

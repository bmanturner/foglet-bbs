defmodule Foglet.TUI.Screens.LoginTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Widgets.Input.TextInput

  import Ecto.Query
  import Foglet.TUI.RenderHelpers
  import FogletBbs.AccountsFixtures
  import Swoosh.TestAssertions

  defp base_state(mode \\ "open") do
    %Foglet.TUI.App{
      current_screen: :login,
      current_user: nil,
      session_context: %{registration_mode: mode},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  # Moves the TextInput cursor to end-of-value, simulating the user having typed the
  # pre-seeded value. This is necessary because TextInput.init/1 places the cursor at
  # position 0 regardless of the initial value; a real user would have cursor at the end.
  defp text_input_at_end(ti) do
    {ti_end, _action} = TextInput.handle_event(%{key: :end}, ti)
    ti_end
  end

  # Build a state with the login form open and a specific field focused.
  # Fields: handle (string), password (string), error (string | nil)
  defp form_state(fields, focused \\ :password) do
    handle_input = TextInput.init(value: Keyword.get(fields, :handle, "")) |> text_input_at_end()

    password_input =
      TextInput.init(value: Keyword.get(fields, :password, ""), mask_char: "*")
      |> text_input_at_end()

    error = Keyword.get(fields, :error, nil)

    %Foglet.TUI.App{
      current_screen: :login,
      session_context: %{registration_mode: "open"},
      terminal_size: {80, 24},
      screen_state: %{
        login: %{
          sub: :login_form,
          focused_field: focused,
          handle_input: handle_input,
          password_input: password_input,
          error: error
        }
      }
    }
    |> Map.from_struct()
  end

  defp reset_request_state(identifier) do
    identifier_input = TextInput.init(value: identifier) |> text_input_at_end()

    %Foglet.TUI.App{
      current_screen: :login,
      session_context: %{registration_mode: "open"},
      terminal_size: {80, 24},
      screen_state: %{
        login: %{
          sub: :reset_request,
          focused_field: :identifier,
          identifier_input: identifier_input,
          message: nil
        }
      }
    }
    |> Map.from_struct()
  end

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode)
      Config.invalidate("delivery_mode")
    end)

    :ok
  end

  defp forbidden_reset_route, do: "/users/reset_password"
  defp forbidden_http_prefix, do: "http://"
  defp forbidden_https_prefix, do: "https://"

  describe "init_screen_state/1 (AUDIT-19)" do
    test "returns minimal menu sub-state" do
      assert Login.init_screen_state([]) == %{sub: :menu}
    end

    test "accepts opts but ignores them (intentionally minimal)" do
      assert Login.init_screen_state(foo: :bar) == %{sub: :menu}
    end
  end

  describe "render/1 (SSH-04, D-06)" do
    test "renders BBS Chrome V2 location" do
      text = Login.render(base_state("open")) |> collect_text_values() |> Enum.join("\n")

      assert Presentation.mode_for!(:login) == :bbs
      assert text =~ "Foglet"
      assert text =~ "Login"
    end

    test "renders without crashing under open mode" do
      assert _ = Login.render(base_state("open"))
    end

    test "renders without crashing under disabled mode" do
      assert _ = Login.render(base_state("disabled"))
    end

    test "renders login form without crashing when in login_form sub" do
      assert _ = Login.render(form_state(handle: "alice", password: "secret"))
    end

    test "renders forgot password only in email delivery mode" do
      Config.put!("delivery_mode", "email")
      email_text = Login.render(base_state("open")) |> collect_text_values() |> Enum.join("\n")
      assert email_text =~ "Forgot password"

      Config.put!("delivery_mode", "no_email")
      no_email_text = Login.render(base_state("open")) |> collect_text_values() |> Enum.join("\n")
      refute no_email_text =~ "Forgot password"
    end
  end

  describe "handle_key/2 — menu sub" do
    test "'Q' returns terminate command" do
      assert {:update, _, [{:terminate, :user_quit}]} =
               Login.handle_key(%{key: :char, char: "Q"}, base_state())
    end

    test "'q' lowercase also terminates" do
      assert {:update, _, [{:terminate, :user_quit}]} =
               Login.handle_key(%{key: :char, char: "q"}, base_state())
    end

    test "'R' transitions to :register when registration enabled (D-22)" do
      {:update, new_state, _} = Login.handle_key(%{key: :char, char: "R"}, base_state("open"))
      assert new_state.current_screen == :register
      # Post-Phase-2: login.ex:maybe_register/1 no longer initializes wizard state.
      # register.ex self-initializes screen_state[:register] on first access (D-06).
      # Only the screen transition is login.ex's responsibility.
    end

    test "'R' returns :no_match when registration disabled (D-06)" do
      assert :no_match = Login.handle_key(%{key: :char, char: "R"}, base_state("disabled"))
    end

    test "'L' enters login_form sub-state with focus on :handle" do
      {:update, new_state, _} = Login.handle_key(%{key: :char, char: "L"}, base_state())
      assert get_in(new_state, [:screen_state, :login, :sub]) == :login_form
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :handle
    end

    test "'F' enters reset_request sub-state only in email delivery mode" do
      Config.put!("delivery_mode", "email")

      {:update, new_state, []} = Login.handle_key(%{key: :char, char: "F"}, base_state())
      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :identifier

      Config.put!("delivery_mode", "no_email")
      assert :no_match = Login.handle_key(%{key: :char, char: "F"}, base_state())
    end

    test "unknown key returns :no_match in menu sub" do
      assert :no_match = Login.handle_key(%{key: :char, char: "x"}, base_state())
    end
  end

  describe "handle_key/2 — login form typing" do
    test "typing a character appends to focused field (handle)" do
      state = form_state([], :handle)
      {:update, new_state, []} = Login.handle_key(%{key: :char, char: "a"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"

      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == ""
    end

    test "typing multiple characters builds up the handle" do
      state = form_state([handle: "al"], :handle)
      {:update, s1, []} = Login.handle_key(%{key: :char, char: "i"}, state)
      {:update, s2, []} = Login.handle_key(%{key: :char, char: "c"}, s1)
      {:update, s3, []} = Login.handle_key(%{key: :char, char: "e"}, s2)

      assert get_in(s3, [:screen_state, :login, :handle_input, Access.key(:raxol_state), :value]) ==
               "alice"
    end

    test "typing appends to password field when focused" do
      state = form_state([], :password)
      {:update, new_state, []} = Login.handle_key(%{key: :char, char: "s"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == "s"
    end

    test "spacebar appends a literal space to focused field" do
      state = form_state([handle: "hello"], :handle)
      {:update, new_state, []} = Login.handle_key(%{key: :char, char: " "}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "hello "
    end

    test "backspace removes last character from focused field" do
      state = form_state([handle: "alice"], :handle)
      {:update, new_state, []} = Login.handle_key(%{key: :backspace}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "alic"
    end

    test "backspace on empty field is a no-op" do
      state = form_state([handle: ""], :handle)
      {:update, new_state, []} = Login.handle_key(%{key: :backspace}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == ""
    end

    test "tab cycles focus from :handle to :password" do
      state = form_state([], :handle)
      {:update, new_state, []} = Login.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
    end

    test "tab cycles focus from :password back to :handle" do
      state = form_state([], :password)
      {:update, new_state, []} = Login.handle_key(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :handle
    end

    test "enter on :handle field moves focus to :password without submitting" do
      state = form_state([handle: "alice"], :handle)
      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
      assert cmds == []
    end

    test "escape from login form returns to menu sub with cleared form" do
      state = form_state([handle: "alice", password: "secret"], :password)
      {:update, new_state, []} = Login.handle_key(%{key: :escape}, state)
      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      # Form is cleared — handle_input and password_input are gone from the returned sub-state
      assert get_in(new_state, [:screen_state, :login, :handle_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_input]) == nil
    end
  end

  describe "handle_key/2 — reset request subflow" do
    test "typing updates the identifier field" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state("ali")

      {:update, new_state, []} = Login.handle_key(%{key: :char, char: "c"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alic"
    end

    test "enter submits and shows generic success copy for unknown identifiers" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state("unknown@example.test")

      {:update, new_state, []} = Login.handle_key(%{key: :enter}, state)

      assert get_in(new_state, [:screen_state, :login, :message]) ==
               "If an active account matches, reset instructions will be sent by email."

      rendered =
        Login.render(new_state)
        |> collect_text_values()
        |> Enum.join("\n")

      assert rendered =~ "If an active account matches"
      refute rendered =~ forbidden_reset_route()
      refute rendered =~ forbidden_http_prefix()
      refute rendered =~ forbidden_https_prefix()
    end

    test "enter reports unavailable if delivery mode is disabled" do
      Config.put!("delivery_mode", "no_email")
      state = reset_request_state("alice")

      {:update, new_state, []} = Login.handle_key(%{key: :enter}, state)

      assert get_in(new_state, [:screen_state, :login, :message]) ==
               "Password reset by email is unavailable on this Foglet."
    end

    test "escape returns to menu" do
      state = reset_request_state("alice")

      {:update, new_state, []} = Login.handle_key(%{key: :escape}, state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert get_in(new_state, [:screen_state, :login, :identifier_input]) == nil
    end
  end

  describe "login form submission" do
    test "valid credentials emit {:promote_session, user} command" do
      password = "correcthorsebatterystaple"
      user = user_fixture(%{password: password})
      # Confirm the user so login produces {:promote_session} rather than routing to verify
      {:ok, user} = Foglet.Accounts.confirm_user(user)

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      # The screen clears screen_state on success and delegates to App via command
      assert new_state.screen_state == %{}
      assert [{:promote_session, returned_user}] = cmds
      assert returned_user.id == user.id
    end

    test "full flow: type handle, tab, type password, enter → promote_session" do
      password = "horsecorrectbattery"
      user = user_fixture(%{password: password})
      # Confirm the user so login produces {:promote_session} rather than routing to verify
      {:ok, user} = Foglet.Accounts.confirm_user(user)

      # Start at menu, press L to enter form
      {:update, s1, []} = Login.handle_key(%{key: :char, char: "L"}, base_state())

      # Type the handle character by character
      s2 =
        Enum.reduce(String.graphemes(user.handle), s1, fn char, acc ->
          {:update, next, []} = Login.handle_key(%{key: :char, char: char}, acc)
          next
        end)

      # Tab to password field
      {:update, s3, []} = Login.handle_key(%{key: :tab}, s2)
      assert get_in(s3, [:screen_state, :login, :focused_field]) == :password

      # Type the password
      s4 =
        Enum.reduce(String.graphemes(password), s3, fn char, acc ->
          {:update, next, []} = Login.handle_key(%{key: :char, char: char}, acc)
          next
        end)

      # Enter submits
      {:update, final_state, cmds} = Login.handle_key(%{key: :enter}, s4)

      assert final_state.screen_state == %{}
      assert [{:promote_session, returned_user}] = cmds
      assert returned_user.id == user.id
    end

    test "invalid credentials surface an inline error and clear password field" do
      state = form_state([handle: "ghost", password: "nope"], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      assert cmds == []
      assert get_in(new_state, [:screen_state, :login, :error]) == "Invalid credentials."
      # Password is cleared so user doesn't have to delete it before retrying
      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == ""

      # Handle is preserved for retry convenience
      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "ghost"
    end

    test "pending user shows 'pending sysop approval' modal (D-05)" do
      password = "correct horse battery"
      attrs = valid_user_attributes(%{password: password})
      {:ok, user} = Foglet.Accounts.register_pending_user(attrs)
      assert user.status == :pending

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, _} = Login.handle_key(%{key: :enter}, state)

      assert %{type: :error, message: msg} = new_state.modal
      assert msg == "Your account is pending sysop approval."
      refute msg =~ "notification"
      refute msg =~ "email"
    end

    test "rejected user shows rejection modal and does not promote session" do
      password = "correct horse battery"

      user =
        user_fixture(%{password: password})
        |> Foglet.Accounts.User.status_changeset(%{status: :rejected})
        |> FogletBbs.Repo.update!()

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      assert %{type: :error, message: "Your registration was rejected. Contact the sysop."} =
               new_state.modal

      assert new_state.screen_state == %{}
      refute Enum.any?(cmds, &match?({:promote_session, _}, &1))
    end
  end

  describe "status modals clear screen_state (Gap 3b)" do
    test "Test D: pending user modal sets screen_state to %{}" do
      password = "correcthorsebatterystaple"
      attrs = valid_user_attributes(%{password: password})
      {:ok, user} = Foglet.Accounts.register_pending_user(attrs)
      assert user.status == :pending

      state =
        form_state(
          [handle: user.handle, password: password],
          :password
        )

      {:update, new_state, _} = Login.handle_key(%{key: :enter}, state)

      assert new_state.modal != nil, "Expected a modal to be set for pending user"

      assert new_state.screen_state == %{},
             "Expected screen_state to be cleared when pending modal is shown, got: #{inspect(new_state.screen_state)}"
    end

    test "Test E: suspended user modal sets screen_state to %{}" do
      password = "correcthorsebatterystaple"
      user = user_fixture(%{password: password})
      # Confirm user first so authentication succeeds, then suspend them
      {:ok, user} = Foglet.Accounts.confirm_user(user)
      # Suspend the user via Repo
      {:ok, _} =
        FogletBbs.Repo.update(Ecto.Changeset.change(user, status: :suspended))

      state =
        form_state(
          [handle: user.handle, password: password],
          :password
        )

      {:update, new_state, _} = Login.handle_key(%{key: :enter}, state)

      assert new_state.modal != nil, "Expected a modal to be set for suspended user"

      assert new_state.screen_state == %{},
             "Expected screen_state to be cleared when suspended modal is shown, got: #{inspect(new_state.screen_state)}"
    end
  end

  describe "submit_login/1 — VERIFY-01 retroactive bypass" do
    setup :set_swoosh_global

    setup do
      original = Foglet.Config.get("require_email_verification", :not_seeded)
      original_delivery_mode = Config.get("delivery_mode", "no_email")

      on_exit(fn ->
        case original do
          :not_seeded -> :ok
          value -> Foglet.Config.put!("require_email_verification", value)
        end

        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
      end)

      :ok
    end

    test "unconfirmed user + toggle=true + email mode delivers verification email and routes to :verify" do
      Foglet.Config.put!("require_email_verification", true)
      Config.put!("delivery_mode", "email")

      password = "letmein12"

      user =
        user_fixture(%{
          password: password,
          handle: "loginverify",
          email: "loginverify@example.test"
        })

      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      assert new_state.current_screen == :verify
      assert new_state.current_user.id == user.id
      refute Map.has_key?(new_state.screen_state || %{}, :verify)
      assert cmds == []

      assert FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"loginverify", "loginverify@example.test"}]
        assert email.subject == "Your Foglet verification code"
      end)
    end

    test "unconfirmed user + toggle=true + no-email mode reports unavailable without routing" do
      Foglet.Config.put!("require_email_verification", true)
      Config.put!("delivery_mode", "no_email")

      password = "letmein12"
      user = user_fixture(%{password: password})
      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      assert new_state.current_screen == :login
      assert is_nil(new_state.current_user)
      assert cmds == []

      assert %{type: :error, message: msg} = new_state.modal
      assert msg == "Email verification is unavailable because email delivery is disabled."

      refute FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )
    end

    test "unconfirmed user + toggle=false routes to :main_menu via {:promote_session, user}" do
      Foglet.Config.put!("require_email_verification", false)

      password = "letmein12"
      user = user_fixture(%{password: password})
      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {:update, new_state, cmds} = Login.handle_key(%{key: :enter}, state)

      assert new_state.screen_state == %{}
      assert [{:promote_session, returned_user}] = cmds
      assert returned_user.id == user.id
    end

    test "confirmed user is unaffected by toggle value" do
      for toggle <- [true, false] do
        Foglet.Config.put!("require_email_verification", toggle)

        password = "letmein12"
        user = user_fixture(%{password: password})
        {:ok, confirmed} = Foglet.Accounts.confirm_user(user)
        assert confirmed.confirmed_at != nil

        state = form_state([handle: confirmed.handle, password: password], :password)

        {:update, _new_state, cmds} = Login.handle_key(%{key: :enter}, state)

        assert [{:promote_session, _}] = cmds,
               "Confirmed user must always promote regardless of toggle=#{toggle}"
      end
    end
  end
end

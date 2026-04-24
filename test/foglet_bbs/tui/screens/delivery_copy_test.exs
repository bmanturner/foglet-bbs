defmodule Foglet.TUI.Screens.DeliveryCopyTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.WidgetHelpers
  import FogletBbs.AccountsFixtures
  import Swoosh.TestAssertions

  alias Foglet.Accounts
  alias Foglet.Config
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Screens.Register
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Screens.Verify
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput

  @forbidden_copy [
    "emailed to you",
    "A new code has been sent.",
    "You will be notified by email.",
    "approval notification",
    "/users/reset_password",
    "operator reset URL",
    "reset URL",
    "http://",
    "https://"
  ]

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")
    original_require_verification = Config.get("require_email_verification", true)

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode, nil)
      Config.put!("require_email_verification", original_require_verification, nil)
      Config.invalidate("delivery_mode")
      Config.invalidate("require_email_verification")
    end)

    :ok
  end

  setup :set_swoosh_global

  describe "cross-surface delivery copy" do
    test "Login reset request copy is generic and browser-free" do
      Config.put!("delivery_mode", "email", nil)

      state =
        login_state(%{
          sub: :reset_request,
          focused_field: :identifier,
          identifier_input: text_input_at_end("alice@example.test"),
          message: "If an active account matches, reset instructions will be sent by email."
        })

      text = Login.render(state) |> flatten_text()

      assert text =~ "If an active account matches, reset instructions will be sent by email."
      assert_forbidden_copy_absent(text)
    end

    test "Register pending-approval copy does not promise email notification" do
      state =
        register_state(
          "sysop_approved",
          handle: "pendingcopy",
          email: "pendingcopy@example.test",
          password: "sekret01",
          confirm: "sekret01"
        )

      {:update, new_state, [{:terminate_after_modal, :pending_approval}]} =
        Register.handle_key(%{key: :enter}, state)

      assert new_state.modal.message ==
               "Your account has been created and is pending sysop approval."

      assert_forbidden_copy_absent(new_state.modal.message)
    end

    test "Verify prompt and resend copy describe verification instructions honestly" do
      Config.put!("delivery_mode", "email", nil)
      user = user_fixture()
      {:ok, _code} = Accounts.build_verify_code(user)
      state = verify_state(user)

      text = Verify.render(state) |> flatten_text()

      assert text =~ "verification code"
      assert text =~ "Enter the 6-character verification code:"
      assert_forbidden_copy_absent(text)

      {new_state, []} = Verify.handle_verify_event({:resend}, state)

      assert new_state.modal.message ==
               "If email delivery is available, new verification instructions have been sent."

      assert_email_sent(subject: "Your Foglet verification code")
      assert_forbidden_copy_absent(new_state.modal.message)
    end

    test "Sysop SiteForm surfaces delivery mode and no-email without false delivery promises" do
      Config.put!("delivery_mode", "no_email", nil)

      text =
        SiteForm.init([])
        |> SiteForm.render(Theme.default())
        |> flatten_text()

      assert text =~ "delivery_mode"
      assert text =~ "no_email"
      assert_forbidden_copy_absent(text)
    end

    test "reset task and delivery copy do not advertise browser reset URLs" do
      reset_task_source = File.read!("lib/mix/tasks/foglet.user.reset_password.ex")
      email_source = File.read!("lib/foglet_bbs/accounts/email.ex")

      assert reset_task_source =~ "Reset token:"
      assert reset_task_source =~ "operator-assisted SSH reset procedure"

      assert_forbidden_copy_absent(reset_task_source)
      assert_forbidden_copy_absent(email_source)
    end
  end

  defp assert_forbidden_copy_absent(text) do
    for phrase <- @forbidden_copy do
      refute text =~ phrase
    end
  end

  defp login_state(login_ss) do
    %Foglet.TUI.App{
      current_screen: :login,
      current_user: nil,
      session_context: %{registration_mode: "open"},
      terminal_size: {80, 24},
      screen_state: %{login: login_ss}
    }
    |> Map.from_struct()
  end

  defp register_state(mode, fields) do
    reg = %{
      mode: mode,
      step: :combined,
      focused_field: :confirm_password,
      invite_code_input: TextInput.init([]),
      handle_input: text_input_at_end(Keyword.fetch!(fields, :handle)),
      email_input: text_input_at_end(Keyword.fetch!(fields, :email)),
      password_input: text_input_at_end(Keyword.fetch!(fields, :password), mask_char: "*"),
      confirm_input: text_input_at_end(Keyword.fetch!(fields, :confirm), mask_char: "*"),
      collected: %{},
      error: nil
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

  defp verify_state(user) do
    %Foglet.TUI.App{
      current_screen: :verify,
      current_user: user,
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{
        verify: %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
      }
    }
    |> Map.from_struct()
  end

  defp text_input_at_end(value, opts \\ []) do
    input = opts |> Keyword.put(:value, value) |> TextInput.init()
    {input, _action} = TextInput.handle_event(%{key: :end}, input)
    input
  end
end

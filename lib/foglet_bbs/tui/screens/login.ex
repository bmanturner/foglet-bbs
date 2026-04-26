defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Sub-states (stored in state.screen_state[:login]):
    * :menu          — showing [L]/[R]/[F]/[Q] menu as allowed by config
    * :login_form    — collecting handle+password
    * :reset_request — collecting handle/email for reset delivery

  State shape is owned by `Foglet.TUI.Screens.Login.State`.

  ## Config.get Safety (D-07)

  Foglet.Config.get/1 calls in registration_mode/1 are safe for render paths —
  Foglet.Config is ETS read-through cached. No render-path change required.

  ## init_screen_state/1 (AUDIT-19)

  Returns minimal menu sub-state: %{sub: :menu}. TextInput structs are created
  lazily in enter_login_form/1 each time the user presses L — this keeps
  per-session memory footprint small.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.{Accounts, Config}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.FocusInput
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.TextInput

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}, {"Q", "Quit"}]
  @menu_keys_no_register [{"L", "Login"}, {"Q", "Quit"}]
  @reset_success_message "If an active account matches, reset instructions will be sent by email."
  @reset_unavailable_message "Password reset by email is unavailable on this Foglet."

  @impl true
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(_opts), do: LoginState.default()

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    mode = registration_mode(state)
    sub = LoginState.sub(state)
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [
          case sub do
            :login_form -> render_login_form(state, theme)
            :reset_request -> render_reset_request(state, theme)
            _ -> render_menu(mode, theme, state)
          end
        ]
      end

    ScreenFrame.render(state, "Login", content, keys_for(sub, mode))
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Route all keys through sub-state so form input gets every character.
  def handle_key(key, state) do
    case LoginState.sub(state) do
      :login_form -> handle_form_key(key, state)
      :reset_request -> handle_reset_key(key, state)
      _ -> handle_menu_key(key, state)
    end
  end

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["q", "Q"],
    do: {:update, state, [{:terminate, :user_quit}]}

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["l", "L"],
    do: enter_login_form(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: maybe_register(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["f", "F"],
    do: maybe_enter_reset_request(state)

  defp handle_menu_key(_key, _state), do: :no_match

  # --- Private ---

  # Key routing pattern (D-06): Screen intercepts Tab/Enter/Escape, delegates to TextInput.
  # This pattern is inherited by Phase 2 (Register) and Phase 7 (NewThread).

  # Tab cycles focus between :handle and :password
  defp handle_form_key(%{key: :tab}, state) do
    login_ss = LoginState.get(state)
    new_login_ss = LoginState.toggle_focus(login_ss)
    {:update, LoginState.put(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_form_key(%{key: :enter}, state) do
    login_ss = LoginState.get(state)

    if login_ss.focused_field == :password do
      submit_login(state)
    else
      new_login_ss = %{login_ss | focused_field: :password}
      {:update, LoginState.put(state, new_login_ss), []}
    end
  end

  # Escape: return to menu sub, clear form state
  defp handle_form_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # Everything else — delegate to focused TextInput
  defp handle_form_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp handle_reset_key(%{key: :enter}, state), do: submit_reset_request(state)

  defp handle_reset_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  defp handle_reset_key(event, state) do
    login_ss = LoginState.get(state)
    {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
    {:update, LoginState.put(state, %{login_ss | identifier_input: new_input}), []}
  end

  defp focused_input(state) do
    FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    login_ss = LoginState.get(state)
    new_login_ss = FocusInput.update_focused(login_ss, new_input, &LoginState.input_key/1, :handle)
    LoginState.put(state, new_login_ss)
  end

  defp keys_for(:login_form, _),
    do: [{"Tab", "Switch field"}, {"Enter", "Submit/Next"}, {"Esc", "Cancel"}]

  defp keys_for(:reset_request, _),
    do: [{"Enter", "Request reset"}, {"Esc", "Cancel"}]

  defp keys_for(_, mode), do: menu_keys(mode)

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  defp delivery_mode, do: Config.delivery_mode()

  defp render_menu(_mode, theme, state) do
    {_, terminal_height} = Map.get(state, :terminal_size, {80, 24})
    available = max(terminal_height - 8, 1)
    top_padding = div(available, 2)
    bottom_padding = max(available - top_padding - 1, 0)
    pad = text(" ", fg: theme.primary.fg)

    column style: %{gap: 0, align_items: :center} do
      List.duplicate(pad, top_padding) ++
        [text("Imagine something cool here", fg: theme.primary.fg)] ++
        List.duplicate(pad, bottom_padding)
    end
  end

  defp menu_keys(mode) do
    mode
    |> base_menu_keys()
    |> maybe_add_reset_key()
  end

  defp base_menu_keys("disabled"), do: @menu_keys_no_register
  defp base_menu_keys(_mode), do: @menu_keys

  defp maybe_add_reset_key(keys) do
    if delivery_mode() == "email" do
      List.insert_at(keys, max(length(keys) - 1, 0), {"F", "Forgot password"})
    else
      keys
    end
  end

  defp render_login_form(state, theme) do
    login_ss = LoginState.get(state)
    focused = Map.get(login_ss, :focused_field, :handle)

    handle_label_fg = if focused == :handle, do: theme.accent.fg, else: theme.primary.fg
    handle_label_style = if focused == :handle, do: [:bold], else: []

    password_label_fg = if focused == :password, do: theme.accent.fg, else: theme.primary.fg
    password_label_style = if focused == :password, do: [:bold], else: []

    error_items =
      if login_ss.error do
        [text(""), text(login_ss.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    column style: %{gap: 0} do
      [
        row style: %{gap: 0} do
          [
            text("Handle:   ", fg: handle_label_fg, style: handle_label_style),
            TextInput.render(login_ss.handle_input,
              bordered: false,
              focused: focused == :handle,
              theme: theme
            )
          ]
        end,
        row style: %{gap: 0} do
          [
            text("Password: ", fg: password_label_fg, style: password_label_style),
            TextInput.render(login_ss.password_input,
              bordered: false,
              focused: focused == :password,
              theme: theme
            )
          ]
        end
      ] ++ error_items
    end
  end

  defp render_reset_request(state, theme) do
    login_ss = LoginState.get(state)

    message_items =
      if login_ss.message do
        [text(""), text(login_ss.message, fg: theme.accent.fg)]
      else
        []
      end

    column style: %{gap: 0} do
      [
        text("Password reset", fg: theme.primary.fg, style: [:bold]),
        row style: %{gap: 0} do
          [
            text("Handle or email: ", fg: theme.accent.fg, style: [:bold]),
            TextInput.render(login_ss.identifier_input,
              bordered: false,
              focused: true,
              theme: theme
            )
          ]
        end
      ] ++ message_items
    end
  end

  defp enter_login_form(state) do
    {:update, LoginState.put(state, LoginState.login_form()), []}
  end

  defp maybe_register(state) do
    case registration_mode(state) do
      "disabled" ->
        :no_match

      _mode ->
        {:update, %{state | current_screen: :register}, []}
    end
  end

  defp maybe_enter_reset_request(state) do
    case delivery_mode() do
      "email" -> enter_reset_request(state)
      "no_email" -> :no_match
    end
  end

  defp enter_reset_request(state) do
    {:update, LoginState.put(state, LoginState.reset_request()), []}
  end

  defp submit_reset_request(state) do
    login_ss = LoginState.get(state)
    identifier = login_ss.identifier_input.raxol_state.value

    message =
      case Accounts.request_password_reset_delivery(identifier) do
        {:ok, :generic_response} -> @reset_success_message
        {:error, :unavailable} -> @reset_unavailable_message
      end

    {:update, LoginState.put(state, %{login_ss | message: message}), []}
  end

  defp submit_login(state) do
    login_ss = LoginState.get(state)
    handle_value = login_ss.handle_input.raxol_state.value
    password_value = login_ss.password_input.raxol_state.value

    # with chain (D-08): authenticate first, then dispatch on user status.
    # post_login_screen/1 returns :verify | :main_menu directly (no {:ok, _} wrapper).
    # Status check is inside the success branch — pending/suspended users authenticate
    # successfully but must not reach the main flow.
    with {:ok, user} <- Accounts.authenticate_by_password(handle_value, password_value),
         :active <- user.status do
      screen = Accounts.post_login_screen(user)
      handle_auth_success(state, user, screen)
    else
      {:error, :invalid_credentials} ->
        new_password_input = TextInput.init(mask_char: "*")

        new_login_ss = %{
          login_ss
          | error: "Invalid credentials.",
            password_input: new_password_input
        }

        {:update, LoginState.put(state, new_login_ss), []}

      :pending ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Your account is pending sysop approval."
        }

        {:update, %{state | modal: modal, screen_state: %{}}, []}

      :rejected ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Your registration was rejected. Contact the sysop."
        }

        {:update, %{state | modal: modal, screen_state: %{}}, []}

      :suspended ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Your account is suspended. Contact the sysop."
        }

        {:update, %{state | modal: modal, screen_state: %{}}, []}
    end
  end

  defp handle_auth_success(state, user, :verify) do
    start_verify_flow(state, user)
  end

  defp handle_auth_success(state, user, :main_menu) do
    {:update, %{state | screen_state: %{}}, [{:promote_session, user}]}
  end

  defp start_verify_flow(state, user) do
    case Accounts.deliver_verification_code(user) do
      {:ok, :attempted} ->
        {:update,
         %{
           state
           | current_user: user,
             current_screen: :verify,
             screen_state: Map.delete(state.screen_state || %{}, :verify)
         }, []}

      {:error, :unavailable} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Email verification is unavailable because email delivery is disabled."
        }

        {:update, %{state | modal: modal}, []}

      {:error, :delivery_failed} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Verification instructions could not be sent. Please try again later."
        }

        {:update, %{state | modal: modal}, []}

      {:error, %Ecto.Changeset{}} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Could not prepare verification instructions. Please try again."
        }

        {:update, %{state | modal: modal}, []}
    end
  end
end

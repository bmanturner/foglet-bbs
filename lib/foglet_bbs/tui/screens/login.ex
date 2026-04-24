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

  Login form state shape:
    %{
      sub: :login_form,
      focused_field: :handle | :password,
      handle_input: %TextInput{},
      password_input: %TextInput{},
      error: nil | "Invalid credentials."
    }

  Reset request state shape:
    %{
      sub: :reset_request,
      focused_field: :identifier,
      identifier_input: %TextInput{},
      message: nil | String.t()
    }

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
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.TextInput

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}, {"Q", "Quit"}]
  @menu_keys_no_register [{"L", "Login"}, {"Q", "Quit"}]
  @reset_success_message "If an active account matches, reset instructions will be sent by email."
  @reset_unavailable_message "Password reset by email is unavailable on this Foglet."

  @log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)

  @impl true
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(_opts), do: %{sub: :menu}

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    mode = registration_mode(state)
    sub = sub_state(state)
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [
          case sub do
            :login_form -> render_login_form(state, theme)
            :reset_request -> render_reset_request(state, theme)
            _ -> render_menu(mode, theme)
          end
        ]
      end

    ScreenFrame.render(state, "Login", content, keys_for(sub, mode))
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Route all keys through sub-state so form input gets every character.
  def handle_key(key, state) do
    case sub_state(state) do
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
    login_ss = get_login_ss(state)
    new_focused = if login_ss.focused_field == :handle, do: :password, else: :handle
    new_login_ss = %{login_ss | focused_field: new_focused}
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_form_key(%{key: :enter}, state) do
    login_ss = get_login_ss(state)

    if login_ss.focused_field == :password do
      submit_login(state)
    else
      new_login_ss = %{login_ss | focused_field: :password}
      {:update, put_login_ss(state, new_login_ss), []}
    end
  end

  # Escape: return to menu sub, clear form state
  defp handle_form_key(%{key: :escape}, state) do
    new_login_ss = %{sub: :menu}
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Everything else — delegate to focused TextInput
  defp handle_form_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp handle_reset_key(%{key: :enter}, state), do: submit_reset_request(state)

  defp handle_reset_key(%{key: :escape}, state) do
    {:update, put_login_ss(state, %{sub: :menu}), []}
  end

  defp handle_reset_key(event, state) do
    login_ss = get_login_ss(state)
    {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
    {:update, put_login_ss(state, %{login_ss | identifier_input: new_input}), []}
  end

  defp focused_input(state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    Map.get(login_ss, input_key(focused))
  end

  defp update_focused_input(state, new_input) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    new_login_ss = Map.put(login_ss, input_key(focused), new_input)
    put_login_ss(state, new_login_ss)
  end

  # Maps focused_field atom to the corresponding input map key.
  defp input_key(:handle), do: :handle_input
  defp input_key(:password), do: :password_input

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  defp delivery_mode, do: Config.delivery_mode()

  defp sub_state(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    Map.get(login_ss, :sub) || :menu
  end

  defp get_login_ss(state) do
    Map.get(state.screen_state || %{}, :login) ||
      %{focused_field: nil, handle_input: nil, password_input: nil, error: nil}
  end

  defp put_login_ss(state, login_ss) do
    new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
    %{state | screen_state: new_screen_state}
  end

  defp keys_for(:login_form, _),
    do: [{"Tab", "Switch field"}, {"Enter", "Submit/Next"}, {"Esc", "Cancel"}]

  defp keys_for(:reset_request, _),
    do: [{"Enter", "Request reset"}, {"Esc", "Cancel"}]

  defp keys_for(_, mode), do: menu_keys(mode)

  defp render_menu(mode, theme) do
    keys = menu_keys(mode)

    column style: %{gap: 0} do
      [text("Welcome.", fg: theme.primary.fg)] ++
        Enum.map(keys, fn {k, label} ->
          text("  [#{k}] #{label}", fg: theme.primary.fg)
        end)
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
    login_ss = get_login_ss(state)
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
            TextInput.render(login_ss.handle_input, bordered: false, theme: theme)
          ]
        end,
        row style: %{gap: 0} do
          [
            text("Password: ", fg: password_label_fg, style: password_label_style),
            TextInput.render(login_ss.password_input, bordered: false, theme: theme)
          ]
        end
      ] ++ error_items
    end
  end

  defp render_reset_request(state, theme) do
    login_ss = get_login_ss(state)

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
            TextInput.render(login_ss.identifier_input, bordered: false, theme: theme)
          ]
        end
      ] ++ message_items
    end
  end

  defp enter_login_form(state) do
    new_login_ss = %{
      sub: :login_form,
      focused_field: :handle,
      handle_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      error: nil
    }

    {:update, put_login_ss(state, new_login_ss), []}
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
    new_login_ss = %{
      sub: :reset_request,
      focused_field: :identifier,
      identifier_input: TextInput.init([]),
      message: nil
    }

    {:update, put_login_ss(state, new_login_ss), []}
  end

  defp submit_reset_request(state) do
    login_ss = get_login_ss(state)
    identifier = login_ss.identifier_input.raxol_state.value

    message =
      case Accounts.request_password_reset_delivery(identifier) do
        {:ok, :generic_response} -> @reset_success_message
        {:error, :unavailable} -> @reset_unavailable_message
      end

    {:update, put_login_ss(state, %{login_ss | message: message}), []}
  end

  defp submit_login(state) do
    login_ss = get_login_ss(state)
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

        {:update, put_login_ss(state, new_login_ss), []}

      :pending ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Your account is pending sysop approval. Please wait for sysop approval."
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
    case Accounts.build_verify_code(user) do
      {:ok, code} ->
        maybe_log_verify_code(user, code)

        {:update,
         %{
           state
           | current_user: user,
             current_screen: :verify,
             screen_state: Map.delete(state.screen_state || %{}, :verify)
         }, []}

      {:error, _cs} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Could not generate a verification code. Please try again."
        }

        {:update, %{state | modal: modal}, []}
    end
  end

  if @log_verify_codes do
    defp maybe_log_verify_code(user, code) do
      require Logger
      Logger.info("[verify] code for @#{user.handle}: #{code}")
    end
  else
    defp maybe_log_verify_code(_user, _code), do: :ok
  end
end

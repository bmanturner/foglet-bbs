defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Sub-states (stored in state.screen_state[:login]):
    * :menu          — showing [L]/[R]/[Q] menu
    * :login_form    — collecting handle+password

  Login form state shape:
    %{
      sub: :login_form,
      form: %{handle: "", password: "", error: nil},
      focused_field: :handle | :password
    }
  """

  alias Foglet.{Accounts, Config}
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}, {"Q", "Quit"}]
  @menu_keys_no_register [{"L", "Login"}, {"Q", "Quit"}]

  @log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)

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
            _ -> render_menu(mode, theme)
          end
        ]
      end

    ScreenFrame.render(state, "Login", content, keys_for(sub, mode))
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Route all keys through sub-state so form input gets every character.
  def handle_key(key, state) do
    case sub_state(state) do
      :login_form -> handle_form_key(key, state)
      _ -> handle_menu_key(key, state)
    end
  end

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["q", "Q"],
    do: {:update, state, [{:terminate, :user_quit}]}

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["l", "L"],
    do: enter_login_form(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: maybe_register(state)

  defp handle_menu_key(_key, _state), do: :no_match

  # --- Private ---

  # Form key handlers — only reached when sub == :login_form

  # Tab cycles focus between :handle and :password
  defp handle_form_key(%{key: :tab}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    new_focused = if focused == :handle, do: :password, else: :handle
    new_login_ss = Map.put(login_ss, :focused_field, new_focused)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_form_key(%{key: :enter}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)

    if focused == :password do
      submit_login(state)
    else
      new_login_ss = Map.put(login_ss, :focused_field, :password)
      {:update, put_login_ss(state, new_login_ss), []}
    end
  end

  # Backspace: delete last grapheme from focused field
  defp handle_form_key(%{key: :backspace}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    form = Map.get(login_ss, :form) || %{handle: "", password: "", error: nil}

    current_val = Map.get(form, focused, "")
    new_val = drop_last_grapheme(current_val)

    new_form = Map.put(form, focused, new_val)
    new_login_ss = Map.put(login_ss, :form, new_form)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Escape: return to menu sub, clear form state
  defp handle_form_key(%{key: :escape}, state) do
    new_login_ss = %{sub: :menu, form: %{handle: "", password: "", error: nil}}
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Typed character catch-all — Raxol native shape: %{key: :char, char: c}.
  # `c` is always a single grapheme string (guaranteed by InputParser).
  # Spacebar arrives as %{key: :char, char: " "} — no special-casing needed.
  defp handle_form_key(%{key: :char, char: c}, state) do
    append_to_focused(state, c)
  end

  defp handle_form_key(_key, _state), do: :no_match

  defp append_to_focused(state, char) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    form = Map.get(login_ss, :form) || %{handle: "", password: "", error: nil}

    current_val = Map.get(form, focused, "")
    new_form = Map.put(form, focused, current_val <> char)
    new_login_ss = Map.put(login_ss, :form, new_form)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  defp drop_last_grapheme(""), do: ""
  defp drop_last_grapheme(str), do: String.slice(str, 0, String.length(str) - 1)

  defp registration_mode(state) do
    ctx = Map.get(state, :session_context) || %{}

    case Map.get(ctx, :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp sub_state(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    Map.get(login_ss, :sub) || :menu
  end

  defp get_login_ss(state) do
    Map.get(state.screen_state || %{}, :login) || %{}
  end

  defp put_login_ss(state, login_ss) do
    new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
    %{state | screen_state: new_screen_state}
  end

  defp keys_for(:login_form, _),
    do: [{"Tab", "Switch field"}, {"Enter", "Submit/Next"}, {"Esc", "Cancel"}]

  defp keys_for(_, "disabled"), do: @menu_keys_no_register
  defp keys_for(_, _), do: @menu_keys

  defp render_menu(mode, theme) do
    keys = if mode == "disabled", do: @menu_keys_no_register, else: @menu_keys

    column style: %{gap: 0} do
      [text("Welcome.", fg: theme.primary.fg)] ++
        Enum.map(keys, fn {k, label} ->
          text("  [#{k}] #{label}", fg: theme.primary.fg)
        end)
    end
  end

  defp render_login_form(state, theme) do
    login_ss = get_login_ss(state)

    form =
      Map.get(login_ss, :form) ||
        %{handle: "", password: "", error: nil}

    focused = Map.get(login_ss, :focused_field, :handle)

    error_items =
      if form.error do
        [text(""), text(form.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    column style: %{gap: 0} do
      [
        text(
          format_input_line("Handle:   ", form.handle, focused == :handle),
          fg: input_fg(focused == :handle, theme),
          style: focus_style(focused == :handle)
        ),
        text(
          format_input_line("Password: ", mask_password(form.password), focused == :password),
          fg: input_fg(focused == :password, theme),
          style: focus_style(focused == :password)
        )
      ] ++ error_items
    end
  end

  # Returns a bold style list when focused, empty list otherwise.
  defp focus_style(true), do: [:bold]
  defp focus_style(false), do: []

  # Formats an input line as "Label<value><cursor?>"
  defp format_input_line(label, value, true), do: "#{label}#{value}█"
  defp format_input_line(label, value, false), do: "#{label}#{value}"

  # Accent when focused, primary otherwise.
  defp input_fg(true, theme), do: theme.accent.fg
  defp input_fg(false, theme), do: theme.primary.fg

  # Masks password characters with asterisks for display.
  defp mask_password(pw) when is_binary(pw), do: String.duplicate("*", String.length(pw))
  defp mask_password(_), do: ""

  defp enter_login_form(state) do
    new_login_ss = %{
      sub: :login_form,
      form: %{handle: "", password: "", error: nil},
      focused_field: :handle
    }

    {:update, put_login_ss(state, new_login_ss), []}
  end

  defp maybe_register(state) do
    case registration_mode(state) do
      "disabled" ->
        :no_match

      mode ->
        new_state = %{
          state
          | current_screen: :register,
            register_wizard: %{
              mode: mode,
              step: first_step_for_mode(mode),
              data: %{},
              error: nil,
              current_input: ""
            }
        }

        {:update, new_state, []}
    end
  end

  defp first_step_for_mode("invite_only"), do: :invite_code
  defp first_step_for_mode(_mode), do: :handle

  defp submit_login(state) do
    login_ss = get_login_ss(state)
    form = Map.get(login_ss, :form) || %{handle: "", password: ""}

    case Accounts.authenticate_by_password(form.handle, form.password) do
      {:ok, %{status: :active} = user} ->
        handle_active_user(state, user)

      {:ok, %{status: :pending}} ->
        modal = %{
          type: :error,
          message:
            "Your account is pending sysop approval. Please wait for an approval notification."
        }

        {:update, %{state | modal: modal, screen_state: %{}}, []}

      {:ok, %{status: :suspended}} ->
        modal = %{type: :error, message: "Your account is suspended. Contact the sysop."}
        {:update, %{state | modal: modal, screen_state: %{}}, []}

      {:error, :invalid_credentials} ->
        # Clear the password field but keep the handle for retry.
        form_with_error =
          form
          |> Map.put(:error, "Invalid credentials.")
          |> Map.put(:password, "")

        new_login_ss = Map.put(login_ss, :form, form_with_error)
        {:update, put_login_ss(state, new_login_ss), []}
    end
  end

  defp handle_active_user(state, user) do
    case Accounts.post_login_screen(user) do
      :verify ->
        start_verify_flow(state, user)

      :main_menu ->
        # Clear screen state and promote the session via the App's handler.
        # post_login_screen/1 returns :main_menu for confirmed users AND
        # unconfirmed users when require_email_verification is false
        # (VERIFY-01 retroactive bypass).
        {:update, %{state | screen_state: %{}}, [{:promote_session, user}]}
    end
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
             screen_state: %{},
             verify_state: %{
               buffer: "",
               attempts: 0,
               cooldown_until: nil,
               resend_cooldown_until: nil
             }
         }, []}

      {:error, _cs} ->
        modal = %{
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

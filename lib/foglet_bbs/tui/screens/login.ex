defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Sub-states (stored in state.screen_state[:login]):
    * :menu          — showing [L]/[R]/[F]/[T] menu as allowed by config
    * :login_form    — collecting handle+password
    * :reset_request — collecting handle/email for reset delivery
    * :reset_consume — collecting raw reset token + new password (Plan 31-03)

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
  alias Foglet.Accounts.{Auth, Verification}
  alias Foglet.TUI.Command
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.FocusInput
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.TextInput

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}]
  @menu_keys_no_register [{"L", "Login"}]
  @login_panel_width 40
  @login_panel_height 8
  @login_input_display_width 25

  # WR-001: email-shape validation is delegated to
  # `Foglet.Accounts.Verification.email_shape?/1` so the screen and the
  # boundary cannot drift. Local validation still happens before the
  # boundary call so malformed inputs never invoke
  # `Verification.request_password_reset_delivery/1` (D-02).

  @reset_email_dispatched_message "If an active account matches, reset instructions will be sent by email. To enter a reset token already in hand, return to the Login menu (Esc) and press [T] Enter reset token."
  @reset_invalid_email_message "Please enter an email address (for example: name@example.test)."
  @reset_no_email_intro "Email delivery is disabled on this Foglet. Contact a sysop or operator over SSH to request a reset token, then return to the Login menu (Esc) and press [T] Enter reset token to set a new password."
  @reset_no_email_no_sysops_fallback "No sysop contact email is published on this Foglet. Reach an operator through your invite or community channel."

  # D-10: Generic, non-leaking copy for any token-validation failure.
  # Identical for invalid, malformed, expired, and already-used tokens so the
  # screen never reveals which failure mode occurred.
  @reset_consume_invalid_or_expired_message "That reset token did not work. Ask the sysop for a new one."
  @reset_consume_password_mismatch_message "Passwords do not match. Re-enter the new password."
  # Generic copy for any password-changeset validation failure on the new
  # password. Honest enough to be actionable, but does not echo specific
  # validation reasons that could differ across users.
  @reset_consume_password_invalid_message "Your new password is not acceptable. Choose a different password and try again."

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
            :reset_consume -> render_reset_consume(state, theme)
            _ -> render_menu(mode, theme, state)
          end
        ]
      end

    ScreenFrame.render(state, "Login", content, keys_for(sub, mode))
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Route all keys through sub-state so form input gets every character.
  def handle_key(%{key: :char, char: c, ctrl: true}, state) when c in ["c", "C"],
    do: {:update, state, [{:terminate, :user_quit}]}

  def handle_key(key, state) do
    case LoginState.sub(state) do
      :login_form -> handle_form_key(key, state)
      :reset_request -> handle_reset_key(key, state)
      :reset_consume -> handle_reset_consume_key(key, state)
      _ -> handle_menu_key(key, state)
    end
  end

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["l", "L"],
    do: enter_login_form(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: maybe_register(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["f", "F"],
    do: maybe_enter_reset_request(state)

  # D-15: [T] Enter reset token is reachable directly from the Login menu so
  # users with an operator-issued raw reset token do not need to walk through
  # the Forgot Password flow first.
  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["t", "T"],
    do: enter_reset_consume(state)

  defp handle_menu_key(_key, _state), do: :no_match

  # --- Private ---

  @doc false
  @spec handle_login_result(map(), tuple()) :: {map(), list()}
  def handle_login_result(state, {:ok, user, :main_menu}) do
    {%{state | screen_state: %{}}, [{:promote_session, user}]}
  end

  def handle_login_result(state, {:ok, user, :verify, :attempted}) do
    complete_verify_login(state, user)
  end

  def handle_login_result(state, {:ok, _user, :verify, :unavailable}) do
    login_error_modal(
      state,
      "Email verification is unavailable because email delivery is disabled."
    )
  end

  def handle_login_result(state, {:ok, _user, :verify, :delivery_failed}) do
    login_error_modal(
      state,
      "Verification instructions could not be sent. Please try again later."
    )
  end

  def handle_login_result(state, {:ok, _user, :verify, :changeset_error}) do
    login_error_modal(state, "Could not prepare verification instructions. Please try again.")
  end

  def handle_login_result(state, {:error, :invalid_credentials}) do
    login_ss = LoginState.get(state)
    new_password_input = TextInput.init(mask_char: "*")

    new_login_ss =
      Map.merge(login_ss, %{
        error: "Invalid credentials.",
        password_input: new_password_input,
        submitting?: false
      })

    {LoginState.put(state, new_login_ss), []}
  end

  def handle_login_result(state, {:error, :pending}) do
    login_error_modal(state, "Your account is pending sysop approval.", clear?: true)
  end

  def handle_login_result(state, {:error, :rejected}) do
    login_error_modal(state, "Your registration was rejected. Contact the sysop.", clear?: true)
  end

  def handle_login_result(state, {:error, :suspended}) do
    login_error_modal(state, "Your account is suspended. Contact the sysop.", clear?: true)
  end

  # Key routing pattern (D-06): Screen intercepts Tab/Enter/Escape, delegates to TextInput.
  # This pattern is inherited by Phase 2 (Register) and Phase 7 (NewThread).

  defp handle_form_key(key, state) do
    login_ss = LoginState.get(state)

    if Map.get(login_ss, :submitting?, false) do
      {:update, state, []}
    else
      handle_unlocked_form_key(key, state)
    end
  end

  # Tab cycles focus between :handle and :password
  defp handle_unlocked_form_key(%{key: :tab}, state) do
    login_ss = LoginState.get(state)
    new_login_ss = LoginState.toggle_focus(login_ss)
    {:update, LoginState.put(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_unlocked_form_key(%{key: :enter}, state) do
    login_ss = LoginState.get(state)

    if login_ss.focused_field == :password do
      submit_login(state)
    else
      new_login_ss = %{login_ss | focused_field: :password}
      {:update, LoginState.put(state, new_login_ss), []}
    end
  end

  # Escape: return to menu sub, clear form state
  defp handle_unlocked_form_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # Everything else — delegate to focused TextInput
  defp handle_unlocked_form_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp handle_reset_key(%{key: :enter}, state), do: submit_reset_request(state)

  defp handle_reset_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # D-15 / CR-001: token-consume entry remains reachable from the Login menu
  # ([T] on `:menu`). The reset_request screen does *not* intercept bare `t`/`T`
  # because the identifier field is a free-text email input — any address
  # containing `t` or `T` (e.g. `taylor@example.com`, `bfturner@foglet.io`)
  # would otherwise have its keystrokes hijacked, jumping the screen into
  # `:reset_consume` and discarding the partially-typed identifier. Users on
  # the Forgot Password screen reach token entry via Esc → menu → [T].

  defp handle_reset_key(event, state) do
    login_ss = LoginState.get(state)
    {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
    {:update, LoginState.put(state, %{login_ss | identifier_input: new_input}), []}
  end

  # Reset-consume key handling (Plan 31-03 / D-04, D-06, D-07).
  #
  # Tab and :backtab cycle focus through the three fields in fixed order.
  # Enter submits the form. Escape returns to the menu and clears all
  # field state. Everything else is forwarded to the focused TextInput.

  defp handle_reset_consume_key(%{key: :tab}, state) do
    login_ss = LoginState.get(state)
    next_focus = LoginState.next_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: next_focus}), []}
  end

  defp handle_reset_consume_key(%{key: :backtab}, state) do
    login_ss = LoginState.get(state)
    prev_focus = LoginState.prev_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: prev_focus}), []}
  end

  # Some terminals send Shift+Tab as `:shift_tab` rather than `:backtab`;
  # accept both for symmetry with other Foglet forms.
  defp handle_reset_consume_key(%{key: :shift_tab}, state),
    do: handle_reset_consume_key(%{key: :backtab}, state)

  defp handle_reset_consume_key(%{key: :enter}, state), do: submit_reset_consume(state)

  defp handle_reset_consume_key(%{key: :escape}, state) do
    # D-07: Escape clears token/password fields and returns to the menu.
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  defp handle_reset_consume_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp focused_input(state) do
    FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    login_ss = LoginState.get(state)

    new_login_ss =
      FocusInput.update_focused(login_ss, new_input, &LoginState.input_key/1, :handle)

    LoginState.put(state, new_login_ss)
  end

  defp keys_for(:login_form, _),
    do: [{"Tab", "Switch field"}, {"Enter", "Submit/Next"}, {"Esc", "Cancel"}]

  defp keys_for(:reset_request, _),
    do: [{"Enter", "Request reset"}, {"Esc", "Cancel"}]

  # D-06, D-07: Reset-consume form advertises Tab/Shift+Tab focus cycle, Enter
  # to submit, Esc to cancel. The raw token value is intentionally not echoed
  # back through this hint set (D-11).
  defp keys_for(:reset_consume, _),
    do: [
      {"Tab", "Next field"},
      {"Shift+Tab", "Prev field"},
      {"Enter", "Submit"},
      {"Esc", "Cancel"}
    ]

  defp keys_for(_, mode), do: menu_commands(mode)

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  defp render_menu(_mode, theme, state) do
    {_, terminal_height} = Map.get(state, :terminal_size, {80, 24})
    available = max(terminal_height - 8, 1)
    top_padding = div(available, 2)
    bottom_padding = max(available - top_padding - 2, 0)
    pad = text(" ", fg: theme.primary.fg)

    column style: %{gap: 0, align_items: :center} do
      List.duplicate(pad, top_padding) ++
        [
          text("you are outside.", fg: theme.primary.fg),
          text("knock or hang up.", fg: theme.primary.fg)
        ] ++
        List.duplicate(pad, bottom_padding)
    end
  end

  defp menu_keys(mode) do
    mode
    |> base_menu_keys()
    |> add_reset_key()
    |> add_reset_consume_key()
  end

  defp menu_commands(mode) do
    [
      %{
        label: "",
        commands:
          mode
          |> menu_keys()
          |> Enum.map(fn {key, label} -> %{key: key, label: label, priority: 30} end)
      }
    ]
  end

  defp base_menu_keys("disabled"), do: @menu_keys_no_register
  defp base_menu_keys(_mode), do: @menu_keys

  # D-01: Forgot Password is always reachable, regardless of delivery_mode.
  # In email mode it dispatches reset delivery for valid email submissions; in
  # no_email mode it presents operator-assisted copy plus token-consume entry.
  defp add_reset_key(keys) do
    keys ++ [{"F", "Forgot password"}]
  end

  # D-15: [T] Enter reset token is advertised on the Login menu so users with
  # an operator-issued raw token can consume it without first walking through
  # the Forgot Password flow.
  defp add_reset_consume_key(keys) do
    List.insert_at(keys, max(length(keys) - 1, 0), {"T", "Reset token"})
  end

  defp render_login_form(state, theme) do
    login_ss = LoginState.get(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    {_, terminal_height} = Map.get(state, :terminal_size, {80, 24})
    submitting? = Map.get(login_ss, :submitting?, false)

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

    panel =
      %{
        type: :panel,
        attrs: %{
          title: "Identify Yourself",
          title_attrs: %{fg: theme.title.fg},
          border: :single,
          border_fg: theme.border.fg,
          width: @login_panel_width,
          height: @login_panel_height
        },
        children: [
          column style: %{gap: 2, padding: 1} do
            [
              row style: %{gap: 0} do
                [
                  text("Handle:   ", fg: handle_label_fg, style: handle_label_style),
                  TextInput.render(login_ss.handle_input,
                    bordered: false,
                    cap_display_width: @login_input_display_width,
                    disabled: submitting?,
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
                    cap_display_width: @login_input_display_width,
                    disabled: submitting?,
                    focused: focused == :password,
                    theme: theme
                  )
                ]
              end
            ] ++ error_items
          end
        ]
      }

    available = max(terminal_height - 8, 1)
    top_padding = div(max(available - @login_panel_height, 0), 2)
    pad = text(" ", fg: theme.primary.fg)

    column style: %{gap: 0, align_items: :center} do
      List.duplicate(pad, top_padding) ++ [panel]
    end
  end

  defp render_reset_request(state, theme) do
    login_ss = LoginState.get(state)
    wrap_width = reset_wrap_width(state)

    error_items =
      case Map.get(login_ss, :error) do
        nil ->
          []

        error_text ->
          [text("")] ++
            wrapped_text_rows(error_text, wrap_width, fg: theme.error.fg, style: [:bold])
      end

    message_items =
      case Map.get(login_ss, :message) do
        nil ->
          []

        message_text ->
          [text("")] ++ wrapped_text_rows(message_text, wrap_width, fg: theme.accent.fg)
      end

    column style: %{gap: 0} do
      [
        text("Password reset", fg: theme.primary.fg, style: [:bold]),
        row style: %{gap: 0} do
          [
            text("Email: ", fg: theme.accent.fg, style: [:bold]),
            TextInput.render(login_ss.identifier_input,
              bordered: false,
              focused: true,
              theme: theme
            )
          ]
        end
      ] ++ error_items ++ message_items
    end
  end

  # Reset-consume render (Plan 31-03 / D-04, D-05, D-06).
  #
  # Three rows: token, password, password confirmation. Password fields render
  # with the masked TextInput (mask_char is set on the struct itself by
  # `LoginState.reset_consume/0`). Each label highlights when its field is
  # focused. Inline error text renders below the form as a single wrapped
  # block; D-11 forbids the raw token value from appearing in any chrome,
  # status, or hint text — and the error copy here is generic by design.
  defp render_reset_consume(state, theme) do
    login_ss = LoginState.get(state)
    focused = Map.get(login_ss, :focused_field, :token)
    wrap_width = reset_wrap_width(state)

    token_label = field_label("Token:           ", focused == :token, theme)
    password_label = field_label("New password:    ", focused == :password, theme)

    confirmation_label =
      field_label("Confirm password:", focused == :password_confirmation, theme)

    error_items =
      case Map.get(login_ss, :error) do
        nil ->
          []

        error_text ->
          [text("")] ++
            wrapped_text_rows(error_text, wrap_width, fg: theme.error.fg, style: [:bold])
      end

    column style: %{gap: 0} do
      [
        text("Enter reset token", fg: theme.primary.fg, style: [:bold]),
        row style: %{gap: 0} do
          [
            token_label,
            TextInput.render(login_ss.token_input,
              bordered: false,
              focused: focused == :token,
              theme: theme
            )
          ]
        end,
        row style: %{gap: 0} do
          [
            password_label,
            TextInput.render(login_ss.password_input,
              bordered: false,
              focused: focused == :password,
              theme: theme
            )
          ]
        end,
        row style: %{gap: 0} do
          [
            confirmation_label,
            TextInput.render(login_ss.password_confirmation_input,
              bordered: false,
              focused: focused == :password_confirmation,
              theme: theme
            )
          ]
        end
      ] ++ error_items
    end
  end

  defp field_label(label, true, theme),
    do: text(label <> " ", fg: theme.accent.fg, style: [:bold])

  defp field_label(label, false, theme),
    do: text(label <> " ", fg: theme.primary.fg)

  # Returns one wrapped text/2 node per line emitted by TextWidth.wrap/2 so
  # compact terminal widths render readable multi-row copy instead of a single
  # long node that the engine would silently truncate (D-12, AUTH-02).
  defp wrapped_text_rows(text_value, width, opts) when is_binary(text_value) do
    text_value
    |> TextWidth.wrap(width)
    |> Enum.map(&text(&1, opts))
  end

  # Wrap target = inside content width. ScreenFrame uses (terminal_width - 2)
  # for inside_width; the reset request column lives inside that with no
  # additional indent, so the same budget applies. Defaults to 78 if no
  # terminal_size is set (matches the historical 80-col default minus border).
  defp reset_wrap_width(state) do
    case Map.get(state, :terminal_size) do
      {width, _height} when is_integer(width) and width > 0 -> max(width - 2, 1)
      _other -> 78
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

  # D-01: Forgot Password is unconditionally reachable; the reset request
  # sub-state handles delivery-mode branching at submit time.
  defp maybe_enter_reset_request(state) do
    {:update, LoginState.put(state, LoginState.reset_request()), []}
  end

  # D-04, D-15: Enter the reset-consume sub-state from any prior sub-state.
  # Always builds a fresh form so prior fields cannot leak across entries.
  defp enter_reset_consume(state) do
    {:update, LoginState.put(state, LoginState.reset_consume()), []}
  end

  defp submit_reset_request(state) do
    login_ss = LoginState.get(state)
    identifier = login_ss.identifier_input.raxol_state.value
    trimmed = String.trim(identifier)

    new_login_ss =
      if email_shape?(trimmed) do
        dispatch_reset_request(login_ss, trimmed)
      else
        # D-02: malformed local input never invokes Accounts reset delivery.
        %{
          login_ss
          | error: @reset_invalid_email_message,
            message: nil,
            message_category: :invalid_email
        }
      end

    {:update, LoginState.put(state, new_login_ss), []}
  end

  defp email_shape?(value), do: Verification.email_shape?(value)

  # Valid email shape — branch on delivery mode at the boundary level.
  # In email mode the same generic outward message_category is set whether or
  # not the email belongs to an active user (D-03). In no-email mode we present
  # operator-assisted copy with active sysop emails (D-14, AUTH-03).
  defp dispatch_reset_request(login_ss, email) do
    case Foglet.Config.delivery_mode() do
      "email" ->
        # Discard return value: the boundary is generic by contract.
        _ = Verification.request_password_reset_delivery(email)

        %{
          login_ss
          | error: nil,
            message: @reset_email_dispatched_message,
            message_category: :email_dispatched
        }

      "no_email" ->
        %{
          login_ss
          | error: nil,
            message: no_email_operator_message(),
            message_category: :no_email_operator_assisted
        }
    end
  end

  defp no_email_operator_message do
    sysops = Verification.active_sysop_contact_emails()

    sysop_line =
      case sysops do
        [] -> @reset_no_email_no_sysops_fallback
        emails -> "Sysop contacts: " <> Enum.join(emails, ", ") <> "."
      end

    @reset_no_email_intro <> "\n\n" <> sysop_line
  end

  # Reset-consume submission (Plan 31-03 / D-07, D-08, D-09, D-10).
  #
  # 1. Compare new password to confirmation locally; on mismatch set inline
  #    error and bail without calling Accounts. Token is *not* consumed.
  # 2. Otherwise call Verification.consume_reset_token/2 which atomically
  #    verifies, claims the token row, updates the password, and deletes
  #    other outstanding reset tokens for the user.
  # 3. On success return to the logged-out Login menu and clear all field
  #    state (D-07). On any token failure render the generic invalid/expired
  #    copy (D-10). On password-changeset failure render generic password
  #    failure copy (still token-consumed-once because consume runs in a
  #    transaction; if the password update fails the consume rolls back).
  defp submit_reset_consume(state) do
    login_ss = LoginState.get(state)
    raw_token = login_ss.token_input.raxol_state.value
    new_password = login_ss.password_input.raxol_state.value
    confirmation = login_ss.password_confirmation_input.raxol_state.value

    if new_password != confirmation do
      # D-07/D-10 mismatch: keep state, surface a generic mismatch error,
      # and do *not* call into Accounts. Token row is preserved so the user
      # can correct their password and try again.
      new_login_ss = %{login_ss | error: @reset_consume_password_mismatch_message}
      {:update, LoginState.put(state, new_login_ss), []}
    else
      case Verification.consume_reset_token(raw_token, %{password: new_password}) do
        {:ok, _user} ->
          # D-07: success returns to the logged-out Login menu and drops
          # token/password field state. Subsequent renders see %{sub: :menu}.
          {:update, LoginState.put(state, LoginState.default()), []}

        {:error, :invalid_or_expired} ->
          # D-10: identical generic copy for invalid/malformed/expired/used.
          new_login_ss = %{login_ss | error: @reset_consume_invalid_or_expired_message}
          {:update, LoginState.put(state, new_login_ss), []}

        {:error, %Ecto.Changeset{}} ->
          # Password failed validation; token was rolled back inside the
          # Accounts transaction so the user can retry without a new token.
          new_login_ss = %{login_ss | error: @reset_consume_password_invalid_message}
          {:update, LoginState.put(state, new_login_ss), []}
      end
    end
  end

  defp submit_login(state) do
    login_ss = LoginState.get(state)
    handle_value = login_ss.handle_input.raxol_state.value
    password_value = login_ss.password_input.raxol_state.value
    submitting_ss = Map.merge(login_ss, %{error: nil, submitting?: true})
    submitting_state = LoginState.put(state, submitting_ss)

    command =
      Command.task(:login, fn ->
        {:login_result, authenticate_login(handle_value, password_value)}
      end)

    {:update, submitting_state, [command]}
  end

  defp authenticate_login(handle_value, password_value) do
    # with chain (D-08): authenticate first, then dispatch on user status.
    # post_login_screen/1 returns :verify | :main_menu directly (no {:ok, _} wrapper).
    # Status check is inside the success branch — pending/suspended users authenticate
    # successfully but must not reach the main flow.
    with {:ok, user} <- Auth.authenticate_by_password(handle_value, password_value),
         :active <- user.status do
      screen = Accounts.post_login_screen(user)
      login_success_result(user, screen)
    else
      {:error, :invalid_credentials} ->
        {:error, :invalid_credentials}

      status when status in [:pending, :rejected, :suspended] ->
        {:error, status}
    end
  end

  defp login_success_result(user, :main_menu), do: {:ok, user, :main_menu}

  defp login_success_result(user, :verify) do
    case Verification.deliver_verification_code(user) do
      {:ok, :attempted} -> {:ok, user, :verify, :attempted}
      {:error, :unavailable} -> {:ok, user, :verify, :unavailable}
      {:error, :delivery_failed} -> {:ok, user, :verify, :delivery_failed}
      {:error, %Ecto.Changeset{}} -> {:ok, user, :verify, :changeset_error}
    end
  end

  defp complete_verify_login(state, user) do
    {
      %{
        state
        | current_user: user,
          current_screen: :verify,
          screen_state: Map.delete(state.screen_state || %{}, :verify)
      },
      []
    }
  end

  defp login_error_modal(state, message, opts \\ []) do
    modal = %Foglet.TUI.Modal{type: :error, message: message}

    if Keyword.get(opts, :clear?, false) do
      {%{state | modal: modal, screen_state: %{}}, []}
    else
      {state |> unlock_login_form() |> Map.put(:modal, modal), []}
    end
  end

  defp unlock_login_form(state) do
    login_ss = LoginState.get(state)

    if Map.get(login_ss, :sub) == :login_form do
      LoginState.put(state, Map.put(login_ss, :submitting?, false))
    else
      state
    end
  end
end

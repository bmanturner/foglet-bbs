defmodule Foglet.TUI.Screens.Login.Render do
  @moduledoc """
  Pure render entry point for the Login screen.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.Login.{MenuScramble, State}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.AppStateBridge
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Auth.AuthForm
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.TextInput

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}]
  @menu_keys_no_register [{"L", "Login"}]
  @login_panel_width AuthForm.default_width()
  @login_panel_height 9
  @auth_card_inner_width @login_panel_width - 4
  @login_input_display_width 25
  @recovery_pane_width 46
  @recovery_pane_base_height 7
  @recovery_pane_inner_width @recovery_pane_width - 4
  @recovery_request_input_width 32
  @recovery_token_input_width 22

  @spec render(map(), Context.t()) :: any()
  def render(local_state, %Context{} = context) do
    state = app_state_from_local(local_state, context)
    mode = registration_mode(state)
    sub = LoginState.sub(state)
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [
          case sub do
            :login_form -> render_login_form(state, theme)
            :reset_recovery -> render_reset_recovery(state, theme)
            :reset_request -> render_reset_request(state, theme)
            :reset_consume -> render_reset_consume(state, theme)
            _ -> render_menu(mode, theme, state)
          end
        ]
      end

    ScreenFrame.render(
      state,
      %{breadcrumb_parts: ["Foglet", "Login"]},
      content,
      keys_for(sub, mode, state)
    )
  end

  defp app_state_from_local(local_state, %Context{} = context) do
    AppStateBridge.from_context(local_state, context, :login, &LoginState.default/0)
  end

  defp keys_for(:login_form, _, _) do
    [
      %{
        label: "Field",
        commands: [%{key: "Tab", label: "Switch field", priority: 10}]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Submit/Next", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  defp keys_for(:reset_recovery, _, state) do
    login_ss = LoginState.get(state)
    active = Map.get(login_ss, :active_pane, :request)

    field_commands =
      case active do
        :token ->
          [
            %{key: "Tab", label: "Next token field", priority: 10},
            %{key: "Shift+Tab", label: "Prev token field", priority: 10}
          ]

        _request ->
          [%{key: "→", label: "Switch pane", priority: 10}]
      end

    primary_label = if active == :token, do: "Set password", else: "Request token"

    [
      %{
        label: "Pane",
        commands: field_commands ++ [%{key: "←/→", label: "Switch pane", priority: 20}]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Esc", label: "Back", priority: 0},
          %{key: "Enter", label: primary_label, priority: 5}
        ]
      }
    ]
  end

  defp keys_for(:reset_request, _, _) do
    [
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Request reset", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  # D-06, D-07: Reset-consume form advertises Tab/Shift+Tab focus cycle, Enter
  # to submit, Esc to cancel. The raw token value is intentionally not echoed
  # back through this hint set (D-11).
  defp keys_for(:reset_consume, _, _) do
    [
      %{
        label: "Field",
        commands: [
          %{key: "Tab", label: "Next field", priority: 10},
          %{key: "Shift+Tab", label: "Prev field", priority: 10}
        ]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Submit", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  defp keys_for(_, mode, state), do: menu_commands(mode, state)

  defp registration_mode(state) do
    login_ss = LoginState.get(state)

    Map.get(login_ss, :registration_mode) ||
      Map.get(session_ctx(state), :registration_mode) ||
      "open"
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  defp render_menu(_mode, theme, state) do
    {_, terminal_height} = Map.get(state, :terminal_size, {80, 24})
    # WR-05: floor `available` at 2 so `available - top_padding - 2`
    # cannot underflow (top_padding == div(available, 2) ≤ available/2,
    # so available - top_padding - 2 ≥ -1 only if available < 2).
    # SizeGate is expected to intercept anything below the contract
    # minimum, but this keeps the arithmetic locally non-negative even
    # if a too-small frame slips through.
    available = max(terminal_height - 8, 2)
    top_padding = div(available, 2)
    bottom_padding = max(available - top_padding - 2, 0)
    pad = text(" ", fg: theme.primary.fg)

    column style: %{gap: 0, align_items: :center} do
      List.duplicate(pad, top_padding) ++
        MenuScramble.render(State.get(state), theme) ++
        List.duplicate(pad, bottom_padding)
    end
  end

  defp menu_keys(mode, state) do
    mode
    |> base_menu_keys()
    |> maybe_add_guest_key(state)
    |> add_reset_key()
  end

  defp menu_commands(mode, state) do
    [
      %{
        label: "",
        commands:
          mode
          |> menu_keys(state)
          |> Enum.map(fn {key, label} -> %{key: key, label: label, priority: 30} end)
      }
    ]
  end

  defp base_menu_keys("disabled"), do: @menu_keys_no_register
  defp base_menu_keys(_mode), do: @menu_keys

  defp maybe_add_guest_key(keys, state) do
    if Guest.guest_mode_enabled?(session_ctx(state)), do: keys ++ [{"G", "Guest"}], else: keys
  end

  defp add_reset_key(keys) do
    keys ++ [{"F", "Forgot password"}]
  end

  defp render_login_form(state, theme) do
    login_ss = LoginState.get(state)
    focused = Map.get(login_ss, :focused_field, :handle)
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
      AuthForm.render(
        "Back on the board",
        AuthForm.helper_text(
          "Enter your handle and password to pick up where you left off.",
          theme,
          @auth_card_inner_width
        ) ++
          [
            text(""),
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
          ] ++ error_items,
        theme,
        width: @login_panel_width,
        height: max(@login_panel_height, 7 + length(error_items))
      )

    AuthForm.centered(panel, state, theme, @login_panel_height)
  end

  defp render_reset_recovery(state, theme) do
    login_ss = LoginState.get(state)
    active = Map.get(login_ss, :active_pane, :request)
    {terminal_width, _terminal_height} = Map.get(state, :terminal_size, {80, 24})

    intro =
      wrapped_text_rows(
        "Need a reset token? Request one on the left. Already have one from email or your sysop? Use it on the right.",
        reset_wrap_width(state),
        fg: theme.dim.fg
      )

    request_active? = active == :request
    token_active? = active == :token
    request_feedback? = request_active? and has_recovery_message?(login_ss)
    token_feedback? = token_active? and has_recovery_error?(login_ss)

    request_pane =
      recovery_pane(
        "Request reset token",
        request_active?,
        theme,
        recovery_pane_height(:request, login_ss, @recovery_pane_inner_width, request_feedback?),
        render_reset_request(
          state,
          theme,
          request_active?,
          @recovery_pane_inner_width,
          request_feedback?
        )
      )

    token_pane =
      recovery_pane(
        "Use reset token",
        token_active?,
        theme,
        recovery_pane_height(:token, login_ss, @recovery_pane_inner_width, token_feedback?),
        render_reset_consume(
          state,
          theme,
          token_active?,
          @recovery_pane_inner_width,
          @recovery_token_input_width,
          token_feedback?
        )
      )

    body =
      recovery_body(
        terminal_width,
        request_pane,
        token_pane,
        request_active?,
        token_active?,
        request_feedback? or token_feedback?,
        theme
      )

    column style: %{gap: 0} do
      [text("Recover your signal", fg: theme.primary.fg, style: [:bold])] ++
        intro ++ [text("")] ++ body
    end
  end

  defp recovery_body(
         terminal_width,
         request_pane,
         token_pane,
         _request_active?,
         _token_active?,
         _feedback?,
         _theme
       )
       when terminal_width >= 96 do
    [
      row style: %{gap: 2, align_items: :start} do
        [request_pane, token_pane]
      end
    ]
  end

  defp recovery_body(
         _terminal_width,
         request_pane,
         _token_pane,
         true,
         _token_active?,
         true,
         theme
       ),
       do: [request_pane, compact_other_pane_hint(:token, theme)]

  defp recovery_body(
         _terminal_width,
         _request_pane,
         token_pane,
         _request_active?,
         true,
         true,
         theme
       ),
       do: [token_pane, compact_other_pane_hint(:request, theme)]

  defp recovery_body(
         _terminal_width,
         request_pane,
         token_pane,
         _request_active?,
         _token_active?,
         _feedback?,
         _theme
       ),
       do: [request_pane, text(""), token_pane]

  defp recovery_pane(title, active?, theme, height, content) do
    marker = if active?, do: "> ", else: "  "
    border_fg = if active?, do: theme.accent.fg, else: theme.border.fg

    %{
      type: :panel,
      attrs: %{
        title: marker <> title,
        title_attrs: %{fg: if(active?, do: theme.accent.fg, else: theme.title.fg)},
        border: :single,
        border_fg: border_fg,
        width: @recovery_pane_width,
        height: height
      },
      children: [content]
    }
  end

  defp compact_other_pane_hint(:token, theme),
    do: text("Use ←/→ to switch to the reset-token pane.", fg: theme.dim.fg)

  defp compact_other_pane_hint(:request, theme),
    do: text("Use ←/→ to switch to the request-token pane.", fg: theme.dim.fg)

  defp recovery_pane_height(_pane, _login_ss, _wrap_width, false), do: @recovery_pane_base_height

  defp recovery_pane_height(:request, login_ss, wrap_width, true) do
    message_rows = feedback_row_count(Map.get(login_ss, :message), wrap_width)
    max(@recovery_pane_base_height, 2 + 3 + 1 + 1 + message_rows)
  end

  defp recovery_pane_height(:token, login_ss, wrap_width, true) do
    error_rows = feedback_row_count(Map.get(login_ss, :error), wrap_width)
    max(@recovery_pane_base_height, 2 + 2 + 3 + 1 + error_rows)
  end

  defp has_recovery_message?(login_ss), do: is_binary(Map.get(login_ss, :message))
  defp has_recovery_error?(login_ss), do: is_binary(Map.get(login_ss, :error))

  defp feedback_row_count(nil, _wrap_width), do: 0

  defp feedback_row_count(text_value, wrap_width) when is_binary(text_value) do
    text_value
    |> TextWidth.wrap(wrap_width)
    |> length()
  end

  defp render_reset_request(state, theme) do
    login_ss = LoginState.get(state)
    wrap_width = @auth_card_inner_width
    content = render_reset_request(state, theme, true, wrap_width, true)

    panel_height =
      max(
        12,
        8 + feedback_row_count(Map.get(login_ss, :error), wrap_width) +
          feedback_row_count(Map.get(login_ss, :message), wrap_width)
      )

    panel =
      AuthForm.render("Request reset token", [content], theme,
        width: @login_panel_width,
        height: panel_height
      )

    AuthForm.centered(panel, state, theme, panel_height)
  end

  defp render_reset_request(state, theme, focused?, wrap_width, show_feedback?) do
    login_ss = LoginState.get(state)

    error_items =
      if show_feedback? do
        case Map.get(login_ss, :error) do
          nil ->
            []

          error_text ->
            [text("")] ++
              wrapped_text_rows(error_text, wrap_width, fg: theme.error.fg, style: [:bold])
        end
      else
        []
      end

    message_items =
      if show_feedback? do
        case Map.get(login_ss, :message) do
          nil ->
            []

          message_text ->
            [text("")] ++ wrapped_text_rows(message_text, wrap_width, fg: theme.accent.fg)
        end
      else
        []
      end

    column style: %{gap: 0} do
      [
        wrapped_text_rows(
          "Enter your account email. If it matches a user here, reset instructions will be sent.",
          wrap_width,
          fg: theme.dim.fg
        ),
        row style: %{gap: 0} do
          [
            text("Email: ", fg: theme.accent.fg, style: [:bold]),
            TextInput.render(login_ss.identifier_input,
              bordered: false,
              cap_display_width: @recovery_request_input_width,
              focused: focused?,
              theme: theme
            )
          ]
        end
      ]
      |> List.flatten()
      |> Kernel.++(error_items)
      |> Kernel.++(message_items)
    end
  end

  defp render_reset_consume(state, theme) do
    content = render_reset_consume(state, theme, true, @auth_card_inner_width, nil, true)

    panel =
      AuthForm.render("Use reset token", [content], theme, width: @login_panel_width, height: 11)

    AuthForm.centered(panel, state, theme, 11)
  end

  defp render_reset_consume(state, theme, pane_active?, wrap_width, input_width, show_feedback?) do
    login_ss = LoginState.get(state)
    focused = if pane_active?, do: Map.get(login_ss, :focused_field, :token), else: nil

    token_label = field_label("Token:           ", focused == :token, theme)
    password_label = field_label("New password:    ", focused == :password, theme)

    confirmation_label =
      field_label("Confirm password:", focused == :password_confirmation, theme)

    error_items =
      if show_feedback? do
        case Map.get(login_ss, :error) do
          nil ->
            []

          error_text ->
            [text("")] ++
              wrapped_text_rows(error_text, wrap_width, fg: theme.error.fg, style: [:bold])
        end
      else
        []
      end

    column style: %{gap: 0} do
      [
        wrapped_text_rows(
          "Paste your reset token, then choose a new password.",
          wrap_width,
          fg: theme.dim.fg
        ),
        row style: %{gap: 0} do
          [
            token_label,
            TextInput.render(
              login_ss.token_input,
              text_input_opts(
                bordered: false,
                cap_display_width: input_width,
                focused: focused == :token,
                theme: theme
              )
            )
          ]
        end,
        row style: %{gap: 0} do
          [
            password_label,
            TextInput.render(
              login_ss.password_input,
              text_input_opts(
                bordered: false,
                cap_display_width: input_width,
                focused: focused == :password,
                theme: theme
              )
            )
          ]
        end,
        row style: %{gap: 0} do
          [
            confirmation_label,
            TextInput.render(
              login_ss.password_confirmation_input,
              text_input_opts(
                bordered: false,
                cap_display_width: input_width,
                focused: focused == :password_confirmation,
                theme: theme
              )
            )
          ]
        end
      ]
      |> List.flatten()
      |> Kernel.++(error_items)
    end
  end

  defp field_label(label, true, theme),
    do: text(label <> " ", fg: theme.accent.fg, style: [:bold])

  defp field_label(label, false, theme),
    do: text(label <> " ", fg: theme.primary.fg)

  defp text_input_opts(opts) do
    case Keyword.fetch!(opts, :cap_display_width) do
      nil -> Keyword.delete(opts, :cap_display_width)
      _width -> opts
    end
  end

  defp wrapped_text_rows(text_value, width, opts) when is_binary(text_value) do
    text_value
    |> TextWidth.wrap(width)
    |> Enum.map(&text(&1, opts))
  end

  defp reset_wrap_width(state) do
    case Map.get(state, :terminal_size) do
      {width, _height} when is_integer(width) and width > 0 -> max(width - 2, 1)
      _other -> 78
    end
  end
end

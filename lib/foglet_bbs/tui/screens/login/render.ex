defmodule Foglet.TUI.Screens.Login.Render do
  @moduledoc """
  Pure render entry point for the Login screen.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.Login.{MenuScramble, State}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.AppStateBridge
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
  @recovery_pane_width 46
  @recovery_pane_height 7
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
          [%{key: "→", label: "Token pane", priority: 10}]
      end

    primary_label = if active == :token, do: "Set password", else: "Request token"

    [
      %{
        label: "Pane",
        commands:
          field_commands ++ [%{key: "←/→", label: "Switch pane at field edge", priority: 20}]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: primary_label, priority: 30},
          %{key: "Esc", label: "Back", priority: 30}
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

  defp keys_for(_, mode, _state), do: menu_commands(mode)

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

  defp add_reset_key(keys) do
    keys ++ [{"F", "Forgot password"}]
  end

  defp add_reset_consume_key(keys) do
    List.insert_at(keys, max(length(keys) - 1, 0), {"T", "Enter reset token"})
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
          title: "Identify yourself",
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

  defp render_reset_recovery(state, theme) do
    login_ss = LoginState.get(state)
    active = Map.get(login_ss, :active_pane, :request)
    {terminal_width, _terminal_height} = Map.get(state, :terminal_size, {80, 24})

    intro =
      wrapped_text_rows(
        "Need a token? Request one on the left. Already have one from email or a sysop? Use it on the right.",
        reset_wrap_width(state),
        fg: theme.dim.fg
      )

    request_pane =
      recovery_pane(
        "Request reset token",
        active == :request,
        theme,
        render_reset_request(state, theme, active == :request, @recovery_pane_inner_width)
      )

    token_pane =
      recovery_pane(
        "Use reset token",
        active == :token,
        theme,
        render_reset_consume(
          state,
          theme,
          active == :token,
          @recovery_pane_inner_width,
          @recovery_token_input_width
        )
      )

    body =
      if terminal_width >= 96 do
        [
          row style: %{gap: 2, align_items: :start} do
            [request_pane, token_pane]
          end
        ]
      else
        [request_pane, text(""), token_pane]
      end

    column style: %{gap: 0} do
      [text("Password recovery", fg: theme.primary.fg, style: [:bold])] ++
        intro ++ [text("")] ++ body
    end
  end

  defp recovery_pane(title, active?, theme, content) do
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
        height: @recovery_pane_height
      },
      children: [content]
    }
  end

  defp render_reset_request(state, theme), do: render_reset_request(state, theme, true)

  defp render_reset_request(state, theme, focused?),
    do: render_reset_request(state, theme, focused?, reset_wrap_width(state))

  defp render_reset_request(state, theme, focused?, wrap_width) do
    login_ss = LoginState.get(state)

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

  defp render_reset_consume(state, theme), do: render_reset_consume(state, theme, true)

  defp render_reset_consume(state, theme, pane_active?),
    do: render_reset_consume(state, theme, pane_active?, reset_wrap_width(state), nil)

  defp render_reset_consume(state, theme, pane_active?, wrap_width, input_width) do
    login_ss = LoginState.get(state)
    focused = if pane_active?, do: Map.get(login_ss, :focused_field, :token), else: nil

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

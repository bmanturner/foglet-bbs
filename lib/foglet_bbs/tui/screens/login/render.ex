defmodule Foglet.TUI.Screens.Login.Render do
  @moduledoc """
  Pure render entry point for the Login screen.
  """

  alias Foglet.TUI.Context
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
      keys_for(sub, mode)
    )
  end

  defp app_state_from_local(local_state, %Context{} = context) do
    AppStateBridge.from_context(local_state, context, :login, &LoginState.default/0)
  end

  defp keys_for(:login_form, _) do
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

  defp keys_for(:reset_request, _) do
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
  defp keys_for(:reset_consume, _) do
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

  defp keys_for(_, mode), do: menu_commands(mode)

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
        text("Forgot password", fg: theme.primary.fg, style: [:bold]),
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

defmodule Foglet.TUI.Screens.MainMenu.Render do
  @moduledoc """
  Pure render entry point for the MainMenu screen.
  """

  alias Foglet.TerminalText
  alias Foglet.TUI.Context
  alias Foglet.TUI.Layout
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.Handle

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}
  @oneliner_display_limit 5
  @oneliner_handle_limit 12
  # Body limit keeps a selected row within the right panel inner width at the
  # narrowest canonical terminal size: marker + "@" + handle + separator + body
  # = 2+1+12+2+17 = 34 columns at 64-wide.
  @oneliner_body_limit 17

  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = local_state, %Context{} = context) do
    state = frame_state(local_state, context)
    theme = Theme.from_state(state)

    destinations = MainMenu.visible_destination_entries(state)
    actions = MainMenu.visible_actions(state)

    inner_width = nav_inner_width(state)
    menu_panel = nav_panel(destinations, theme, inner_width)
    content = dashboard_content(state, theme, menu_panel)

    ScreenFrame.render(
      state,
      %{breadcrumb_parts: Foglet.AppName.breadcrumb(["Home"])},
      content,
      actions
    )
  end

  defp nav_inner_width(state) do
    cond do
      Layout.spacious?(state.terminal_size) -> 32
      Layout.enhanced?(state.terminal_size) -> 42
      true -> MainMenu.__nav_panel_inner_width__(state)
    end
  end

  defp dashboard_content(state, theme, menu_panel) do
    activity_panel = board_activity_panel(state, theme)

    cond do
      Layout.spacious?(state.terminal_size) ->
        primary = enhanced_dashboard(menu_panel, activity_panel, continue_panel(state, theme))

        Layout.spacious_rail(primary, utility_panel(state, theme),
          terminal_size: state.terminal_size,
          ratio: {5, 1}
        )

      Layout.enhanced?(state.terminal_size) ->
        enhanced_dashboard(menu_panel, activity_panel, continue_panel(state, theme))

      true ->
        standard_dashboard(menu_panel, oneliners_panel(state, theme))
    end
  end

  # Keep the legacy 80x24 Home contract as a compact navigation + oneliner split.
  # `Layout.left_heavy_split/3` intentionally omits detail below 120x36 for new
  # list/detail screens, so Home owns this standard-tier two-column fallback.
  defp standard_dashboard(menu_panel, oneliners_panel_widget) do
    split_pane(
      direction: :horizontal,
      ratio: {2, 3},
      min_size: 18,
      divider_char: " ",
      children: [menu_panel, oneliners_panel_widget]
    )
  end

  defp enhanced_dashboard(menu_panel, activity_panel, continue_panel_widget) do
    right_stack =
      split_pane(
        direction: :vertical,
        ratio: {2, 1},
        min_size: 8,
        divider_char: " ",
        children: [activity_panel, continue_panel_widget]
      )

    Layout.left_heavy_split(
      menu_panel,
      right_stack,
      terminal_size: {120, 36},
      ratio: {2, 3},
      min_size: 18,
      divider_char: " "
    )
  end

  defp frame_state(%State{} = local_state, %Context{} = context) do
    %{
      current_screen: :main_menu,
      current_user: context.current_user,
      unread_count: context.unread_count,
      session_context: context.session_context,
      domain: context.domain,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      screen_state: %{main_menu: local_state},
      recent_oneliners: local_state.recent_oneliners,
      selected_oneliner_index: local_state.selected_oneliner_index,
      pending_hide_oneliner_id: local_state.pending_hide_oneliner_id
    }
  end

  # Note: Raxol's `:panel` measure_panel/2 shrinks the panel to
  # `children_size + double_border` unless `:width`/`:height` are explicitly
  # set (vendor/raxol/.../panels.ex:171-201). Without explicit size attrs the
  # panel will not fill the split_pane allocation, leaving the title segment
  # truncated and the right border drawn at the children-measured edge instead
  # of the chrome-allocated edge. We pass sentinel large values; `apply_constraints/2`
  # clamps to `available_space.width`/`height`, so the panel fills the pane.
  defp nav_panel(destinations, theme, inner_width) do
    %{
      type: :panel,
      attrs: %{
        title: "Navigation",
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          Enum.map(destinations, &nav_row(&1, theme, inner_width))
        end
      ]
    }
  end

  # Multi-node row composition (D-06, MENU-03):
  # - Leading text node carries the normal row fg and includes the one-column
  #   inner indent (D-09, MENU-04), the destination glyph, the label, and the
  #   right-align padding.
  # - Online Now splits the label into normal chrome (`Online Now (` and `)`) and
  #   a count-only color node so low/activity color does not wash over the full
  #   row label.
  # - Trailing text node carries `theme.accent.fg` and renders the bracketed
  #   key token `[X]` (D-08, D-10 — color only, no style).
  # Width budget at 64x22 (inner_width = 20):
  #   indent(1) + glyph(1) + space(1) + "Moderation"(10) + "[M]"(3) = 16,
  #   leaving 4 cols of trailing padding.
  defp nav_row(%{key: key, label: label, glyph: glyph} = destination, theme, inner_width) do
    indent = " "
    bracketed_key = "[" <> key <> "]"

    prefix_text = indent <> glyph <> " " <> label
    prefix_width = TextWidth.display_width(prefix_text)
    bracketed_key_width = TextWidth.display_width(bracketed_key)

    padding_width = max(inner_width - prefix_width - bracketed_key_width, 1)
    padding = TextWidth.pad_trailing("", padding_width)

    # NOTE: must pass an explicit opts arg (`[]`) so the `Raxol.Core.Renderer.View.row/2`
    # MACRO is invoked. Calling `row do ... end` without an opts arg matches the
    # `row/1` FUNCTION instead, which silently drops the do-block contents and
    # returns a flex with `children: []` (vendor/raxol/lib/raxol/core/renderer/view.ex
    # line 87 vs. line 92).
    row [] do
      nav_row_segments(destination, prefix_text, padding, bracketed_key, theme)
    end
  end

  defp nav_row_segments(
         %{key: "I", unread_count: count},
         prefix_text,
         padding,
         bracketed_key,
         theme
       ) do
    badge = inbox_badge_text(count)

    if badge == nil do
      [
        text(prefix_text <> padding, fg: theme.primary.fg),
        text(bracketed_key, fg: theme.accent.fg)
      ]
    else
      badge_width = TextWidth.display_width(badge)

      row_padding =
        TextWidth.pad_trailing("", max(TextWidth.display_width(padding) - badge_width - 1, 1))

      [
        text(prefix_text, fg: theme.primary.fg),
        text(row_padding, fg: theme.primary.fg),
        text(badge, fg: inbox_count_fg(count, theme)),
        text(" ", fg: theme.primary.fg),
        text(bracketed_key, fg: theme.accent.fg)
      ]
    end
  end

  defp nav_row_segments(
         %{key: "N", online_count: count},
         _prefix_text,
         padding,
         bracketed_key,
         theme
       ) do
    [
      text(" ◌ Online Now (", fg: theme.primary.fg),
      text(to_string(count), fg: online_count_fg(count, theme)),
      text(")" <> padding, fg: theme.primary.fg),
      text(bracketed_key, fg: theme.accent.fg)
    ]
  end

  defp nav_row_segments(_destination, prefix_text, padding, bracketed_key, theme) do
    [
      text(prefix_text <> padding, fg: theme.primary.fg),
      text(bracketed_key, fg: theme.accent.fg)
    ]
  end

  defp inbox_count_fg(0, theme), do: theme.dim.fg
  defp inbox_count_fg(_count, theme), do: theme.accent.fg

  defp inbox_badge_text(count) when is_integer(count) and count > 0 do
    display = if count > 99, do: "99+", else: Integer.to_string(count)
    "[#{display}]"
  end

  defp inbox_badge_text(_count), do: nil

  defp online_count_fg(count, theme) when count in [0, 1], do: theme.error.fg
  defp online_count_fg(_count, theme), do: theme.accent.fg

  defp oneliners_panel(state, theme) do
    %{
      type: :panel,
      attrs: %{
        title: "Oneliners",
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          oneliner_rows(state, theme)
        end
      ]
    }
  end

  defp board_activity_panel(state, theme) do
    %{
      type: :panel,
      attrs: panel_attrs("Board activity", theme),
      children: [
        column style: %{gap: 0} do
          board_activity_rows(state, theme) ++
            [text(""), text("Oneliners", fg: theme.title.fg)] ++
            oneliner_rows(state, theme)
        end
      ]
    }
  end

  defp continue_panel(state, theme) do
    inbox_count = Map.get(state, :unread_count, 0) || 0
    online_count = safe_online_now_count(state)

    rows = [
      {"Last board", "/general"},
      {"Last thread", "Welcome — read me first"},
      {"Unread waiting", "#{inbox_count} inbox • board posts"},
      {"Next likely", "B Boards • I Inbox"},
      {"Online", "#{online_count} callers visible"}
    ]

    %{
      type: :panel,
      attrs: panel_attrs("Continue", theme),
      children: [
        column style: %{gap: 0} do
          Enum.map(rows, fn {label, value} ->
            row [] do
              [
                text(TextWidth.pad_trailing(label, 15), fg: theme.dim.fg),
                text(value, fg: theme.primary.fg)
              ]
            end
          end)
        end
      ]
    }
  end

  defp utility_panel(state, theme) do
    count = safe_online_now_count(state)

    %{
      type: :panel,
      attrs: panel_attrs("Utility", theme),
      children: [
        column style: %{gap: 0} do
          [
            text("Boards     B", fg: theme.primary.fg),
            text("Inbox      I", fg: theme.primary.fg),
            text("Compose    C", fg: theme.primary.fg),
            text("Online  #{count}", fg: theme.primary.fg),
            text(""),
            text("Recent", fg: theme.title.fg),
            text("/general", fg: theme.dim.fg),
            text("/lounge", fg: theme.dim.fg)
          ]
        end
      ]
    }
  end

  defp panel_attrs(title, theme) do
    %{
      title: title,
      title_attrs: %{fg: theme.title.fg},
      border: :single,
      border_fg: theme.border.fg,
      width: 9999,
      height: 9999
    }
  end

  defp board_activity_rows(state, theme) do
    inbox_count = Map.get(state, :unread_count, 0) || 0

    [
      activity_row("> /general", "Welcome — read me first", unread_label(inbox_count), theme),
      activity_row("  /lounge", "What is everyone working on?", "1 unread", theme),
      activity_row("  /tech", "Thread renderer ASCII tool", "all read", theme)
    ]
  end

  defp activity_row(board, title, status, theme) do
    row [] do
      [
        text(TextWidth.pad_trailing(board, 12), fg: theme.accent.fg),
        text(TextWidth.pad_trailing(title, 32), fg: theme.primary.fg),
        text(status, fg: theme.dim.fg)
      ]
    end
  end

  defp unread_label(count) when is_integer(count) and count > 0, do: "#{count} unread"
  defp unread_label(_count), do: "all read"

  defp safe_online_now_count(state) do
    state
    |> Map.get(:domain, %{})
    |> Map.get(:online_now, Foglet.Sessions.OnlineNow)
    |> then(& &1.count())
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp oneliner_rows(state, theme) do
    entries = visible_oneliners(state)
    selected_index = selected_oneliner_index(state, entries)

    case entries do
      [] ->
        [text("No oneliners yet.", fg: theme.primary.fg)]

      entries ->
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} ->
          marker = if index == selected_index, do: "> ", else: "  "
          oneliner_row(entry, marker, theme)
        end)
    end
  end

  defp oneliner_row(entry, marker, theme) do
    user = Map.get(entry, :user)

    handle =
      user
      |> user_handle()
      |> TerminalText.sanitize_plain_text()
      |> single_line()
      |> clip(@oneliner_handle_limit)

    body =
      entry
      |> Map.get(:body, "")
      |> TerminalText.sanitize_plain_text()
      |> single_line()
      |> clip(@oneliner_body_limit)

    row style: %{gap: 0} do
      [
        text(marker <> "@" <> handle, fg: Handle.color_for(user, theme)),
        text("  " <> body, fg: theme.primary.fg)
      ]
    end
  end

  defp visible_oneliners(state) do
    state
    |> Map.get(:recent_oneliners, [])
    |> Kernel.||([])
    |> Enum.take(@oneliner_display_limit)
  end

  defp selected_oneliner_index(_state, []), do: 0

  defp selected_oneliner_index(state, entries) do
    state
    |> Map.get(:selected_oneliner_index, 0)
    |> normalize_index()
    |> clamp(0, length(entries) - 1)
  end

  defp normalize_index(index) when is_integer(index), do: index
  defp normalize_index(_other), do: 0

  defp clamp(value, lower, upper) do
    value
    |> Kernel.max(lower)
    |> Kernel.min(upper)
  end

  defp user_handle(nil), do: "unknown"

  defp user_handle(user) do
    user
    |> Map.get(:handle, "unknown")
    |> case do
      handle when is_binary(handle) and handle != "" -> handle
      _other -> "unknown"
    end
  end

  defp single_line(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clip(value, limit) do
    TextWidth.slice_to_width(value, limit)
  end
end

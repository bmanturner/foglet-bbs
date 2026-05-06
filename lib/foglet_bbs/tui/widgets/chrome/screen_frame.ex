defmodule Foglet.TUI.Widgets.Chrome.ScreenFrame do
  @moduledoc """
  Outer screen chrome widget for Foglet BBS (FRAME-01, FRAME-02).

  Wraps every screen with:
    top border/status row → content_element → bottom border/commands row

  Signature (locked — D-05):
    ScreenFrame.render(state, chrome, content_element, commands)

  Where:
    state           — full app state; ScreenFrame reads current_user.handle
                      and session_context.theme internally (D-07)
    chrome          — Chrome V2 model (`%{breadcrumb_parts: [...], ...}`)
    content_element — pre-built Raxol element from caller (result of
                      column/row/box do...end block in the screen module)
    commands        — Chrome V2 grouped command list
                      (`[%{label: ..., commands: [%{key, label, priority}, ...]}, ...]`)

  The border rows embed Chrome V2 text directly in the border line:
    ┌ Foglet ▸ Breadcrumb ───────── @handle | time ┐
    └ Commands ────────────────────────────────────┘
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.{TextWidth, Theme}
  alias Foglet.TUI.Widgets.Chrome.{BreadcrumbBar, CommandBar, StatusBar}

  @border %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─"
  }

  @doc """
  Renders the full screen chrome wrapping the caller-provided content.
  """
  @spec render(map(), map(), any(), [map()]) :: any()
  def render(state, chrome_input, content_element, commands) do
    theme = Theme.from_state(state)
    chrome = chrome_model(state, chrome_input, commands)
    frame_width = frame_width(state)

    top_segments = top_border_segments(chrome, theme, frame_width)
    bottom_segments = bottom_border_segments(chrome, theme, frame_width)

    %{
      type: :foglet_screen_frame,
      content: content_element,
      top_segments: top_segments,
      bottom_segments: bottom_segments,
      children: [
        segment_row(top_segments),
        content_element,
        segment_row(bottom_segments)
      ],
      border_fg: theme.border.fg
    }
  end

  defp segment_row(segments), do: %{type: :row, attrs: %{gap: 0}, children: segments}

  defp border_segment(content, theme) do
    text(content, fg: theme.border.fg)
  end

  defp status_segment(content, theme) do
    text(content,
      fg: Map.get(theme.status_bar, :fg),
      bg: Map.get(theme.status_bar, :bg),
      style: Map.get(theme.status_bar, :style, [])
    )
  end

  defp top_border_segments(chrome, theme, nil) do
    [
      border_segment(@border.top_left <> " ", theme),
      BreadcrumbBar.render(theme, chrome.breadcrumb_parts),
      border_segment(" ", theme),
      status_segment(status(chrome), theme),
      border_segment(" " <> @border.top_right, theme)
    ]
  end

  defp top_border_segments(chrome, theme, width) do
    inside_width = max(width - 2, 0)
    raw_status = status(chrome)
    status_width = TextWidth.display_width(raw_status)
    breadcrumb_width = max(inside_width - status_width - 4, 0)

    breadcrumb_node =
      BreadcrumbBar.render(theme, chrome.breadcrumb_parts, width: breadcrumb_width)

    breadcrumb_width = node_width(breadcrumb_node)
    status_width = min(status_width, max(inside_width - breadcrumb_width - 4, 0))

    status_node =
      raw_status
      |> TextWidth.truncate(status_width)
      |> status_segment(theme)

    content_width = breadcrumb_width + node_width(status_node) + 4
    fill_width = max(inside_width - content_width, 0)

    [
      border_segment(@border.top_left <> " ", theme),
      breadcrumb_node,
      border_segment(" " <> String.duplicate(@border.horizontal, fill_width) <> " ", theme),
      status_node,
      border_segment(" " <> @border.top_right, theme)
    ]
  end

  defp bottom_border_segments(chrome, theme, nil) do
    command_nodes = command_segments(theme, chrome.command_groups)

    [
      border_segment(@border.bottom_left <> " ", theme),
      command_nodes,
      border_segment(" " <> @border.bottom_right, theme)
    ]
    |> List.flatten()
  end

  defp bottom_border_segments(chrome, theme, width) do
    inside_width = max(width - 2, 0)

    command_nodes =
      command_segments(theme, chrome.command_groups, width: max(inside_width - 2, 0))

    command_width = nodes_width(command_nodes)

    {leading, trailing, fill_width} =
      if command_width > 0 do
        {" ", " ", max(inside_width - command_width - 2, 0)}
      else
        {"", "", inside_width}
      end

    [
      border_segment(@border.bottom_left <> leading, theme),
      command_nodes,
      border_segment(
        trailing <> String.duplicate(@border.horizontal, fill_width) <> @border.bottom_right,
        theme
      )
    ]
    |> List.flatten()
  end

  defp command_segments(theme, groups, opts \\ []) do
    theme
    |> CommandBar.render(groups, opts)
    |> Map.get(:children, [])
  end

  defp status(chrome), do: chrome.status_atoms |> Enum.join(" | ")

  defp node_width(node), do: node |> node_text() |> TextWidth.display_width()

  defp nodes_width(nodes) do
    nodes
    |> List.flatten()
    |> Enum.map(&node_width/1)
    |> Enum.sum()
  end

  defp node_text(node), do: Map.get(node, :content, Map.get(node, :text, ""))

  defp frame_width(state) do
    case Map.get(state, :terminal_size) do
      {width, _height} when is_integer(width) and width > 0 -> width
      _other -> nil
    end
  end

  defp chrome_model(state, chrome_input, commands) do
    chrome_input
    |> normalize_chrome(state)
    |> Map.put_new(:command_groups, command_groups(commands))
  end

  defp normalize_chrome(%{} = chrome, state) do
    chrome
    |> Map.put_new(:breadcrumb_parts, Foglet.AppName.breadcrumb())
    |> Map.put_new(:status_atoms, StatusBar.status_atoms(state))
  end

  defp command_groups(commands) when is_list(commands) do
    CommandBar.normalize_groups(commands)
  end
end

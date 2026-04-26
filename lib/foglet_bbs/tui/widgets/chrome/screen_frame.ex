defmodule Foglet.TUI.Widgets.Chrome.ScreenFrame do
  @moduledoc """
  Outer screen chrome widget for Foglet BBS (FRAME-01, FRAME-02).

  Wraps every screen with:
    top border/status row → content_element → bottom border/commands row

  Signature (locked — D-05):
    ScreenFrame.render(state, title_or_chrome, content_element, commands)

  Where:
    state           — full app state; ScreenFrame reads current_user.handle
                      and session_context.theme internally (D-07)
    title_or_chrome — legacy screen/page title string or Chrome V2 model
    content_element — pre-built Raxol element from caller (result of
                      column/row/box do...end block in the screen module)
    commands        — grouped Chrome V2 commands or legacy key tuples

  The border rows embed Chrome V2 text directly in the border line:
    ┌ Foglet ▸ Breadcrumb ───────── @handle | time ┐
    └ Commands ────────────────────────────────────┘
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.{TextWidth, Theme}
  alias Foglet.TUI.Widgets.Chrome.{BreadcrumbBar, CommandBar, Normalizer, StatusBar}

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
  @spec render(map(), String.t() | map(), any(), list()) :: any()
  def render(state, title_or_chrome, content_element, commands) do
    theme = Theme.from_state(state)
    chrome = chrome_model(state, title_or_chrome, commands)
    frame_width = frame_width(state)

    column style: %{gap: 0, justify_content: :space_between} do
      [
        column style: %{gap: 0} do
          [
            border_text(top_border(chrome, frame_width), theme),
            content_box(content_element)
          ]
        end,
        border_text(bottom_border(chrome, frame_width), theme)
      ]
    end
  end

  defp content_box(content_element) do
    box style: %{padding: 1} do
      content_element
    end
  end

  defp border_text(content, theme) do
    text(content, fg: theme.border.fg)
  end

  defp top_border(chrome, nil) do
    @border.top_left <>
      " " <>
      breadcrumb(chrome, nil) <>
      " " <>
      status(chrome) <>
      " " <>
      @border.top_right
  end

  defp top_border(chrome, width) do
    inside_width = max(width - 2, 0)
    left = " " <> breadcrumb(chrome, max(inside_width - 2, 0)) <> " "
    right = status(chrome) |> status_segment()

    @border.top_left <> fitted_top_inside(left, right, inside_width) <> @border.top_right
  end

  defp fitted_top_inside(left, right, inside_width) do
    left_width = TextWidth.display_width(left)
    right_width = TextWidth.display_width(right)

    if left_width + right_width <= inside_width do
      fill = String.duplicate(@border.horizontal, inside_width - left_width - right_width)
      left <> fill <> right
    else
      right = TextWidth.truncate(right, min(right_width, div(inside_width, 2)))
      right_width = TextWidth.display_width(right)
      left = TextWidth.truncate(left, max(inside_width - right_width, 0))
      left <> right
    end
  end

  defp bottom_border(chrome, nil) do
    commands = CommandBar.render_text(chrome.command_groups)

    @border.bottom_left <> " " <> commands <> " " <> @border.bottom_right
  end

  defp bottom_border(chrome, width) do
    inside_width = max(width - 2, 0)

    command_segment =
      chrome.command_groups
      |> CommandBar.render_text(width: max(inside_width - 2, 0))
      |> case do
        "" -> ""
        commands -> " " <> commands <> " "
      end

    command_width = TextWidth.display_width(command_segment)

    inside =
      if command_width <= inside_width do
        command_segment <> String.duplicate(@border.horizontal, inside_width - command_width)
      else
        TextWidth.truncate(command_segment, inside_width)
      end

    @border.bottom_left <> inside <> @border.bottom_right
  end

  defp breadcrumb(chrome, width), do: BreadcrumbBar.format(chrome.breadcrumb_parts, width: width)

  defp status(chrome), do: chrome.status_atoms |> Enum.join(" | ")

  defp status_segment(""), do: ""
  defp status_segment(status), do: " " <> status <> " "

  defp frame_width(state) do
    case Map.get(state, :terminal_size) do
      {width, _height} when is_integer(width) and width > 0 -> width
      _other -> nil
    end
  end

  defp chrome_model(state, title_or_chrome, commands) do
    title_or_chrome
    |> normalize_chrome(state)
    |> Map.put_new(:command_groups, command_groups(commands))
  end

  defp normalize_chrome(%{} = chrome, state) do
    chrome
    |> Map.put_new(:breadcrumb_parts, BreadcrumbBar.parts_for(state))
    |> Map.put_new(:status_atoms, StatusBar.status_atoms(state))
  end

  defp normalize_chrome(_legacy_title, state) do
    %{
      breadcrumb_parts: BreadcrumbBar.parts_for(state),
      status_atoms: StatusBar.status_atoms(state)
    }
  end

  defp command_groups(commands) when is_list(commands) do
    if grouped_commands?(commands) do
      CommandBar.normalize_groups(commands)
    else
      Normalizer.commands(commands)
    end
  end

  defp grouped_commands?(commands) do
    Enum.all?(commands, fn
      %{commands: nested} when is_list(nested) -> true
      _other -> false
    end)
  end
end

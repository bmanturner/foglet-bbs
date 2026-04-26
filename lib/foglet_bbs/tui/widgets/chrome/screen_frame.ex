defmodule Foglet.TUI.Widgets.Chrome.ScreenFrame do
  @moduledoc """
  Outer screen chrome widget for Foglet BBS (FRAME-01, FRAME-02).

  Wraps every screen with:
    outer bordered box with top title → column → content_element → CommandBar

  Signature (locked — D-05):
    ScreenFrame.render(state, title_or_chrome, content_element, commands)

  Where:
    state           — full app state; ScreenFrame reads current_user.handle
                      and session_context.theme internally (D-07)
    title_or_chrome — legacy screen/page title string or Chrome V2 model
    content_element — pre-built Raxol element from caller (result of
                      column/row/box do...end block in the screen module)
    commands        — grouped Chrome V2 commands or legacy key tuples

  Internal layout:
    outer bordered box with title → column → content_element → CommandBar
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.{BreadcrumbBar, CommandBar, Normalizer, StatusBar}

  @doc """
  Renders the full screen chrome wrapping the caller-provided content.
  """
  @spec render(map(), String.t() | map(), any(), list()) :: any()
  def render(state, title_or_chrome, content_element, commands) do
    theme = Theme.from_state(state)
    chrome = chrome_model(state, title_or_chrome, commands)
    inner_width = inner_width(state)

    title = frame_title(state, chrome, inner_width)

    box_opts = [
      style: %{border: :single, padding: 1, border_fg: theme.border.fg, fg: theme.status_bar.fg},
      title: title
    ]

    box box_opts do
      # Kept `justify_content: :space_between` over `spacer()` per 08-06 audit —
      # would require knowing `content_element`'s height at call time.
      column style: %{gap: 0, justify_content: :space_between} do
        [content_element, CommandBar.render(theme, chrome.command_groups, width: inner_width)]
      end
    end
  end

  defp frame_title(state, chrome, width) do
    title = BreadcrumbBar.format(chrome.breadcrumb_parts, width: width)
    status_atoms = Map.get(chrome, :status_atoms, StatusBar.status_atoms(state))
    status = Enum.join(status_atoms, " | ")

    format_frame_title(title, status, width)
  end

  defp format_frame_title(left, right, nil), do: combine_title_parts(left, right)

  defp format_frame_title(left, right, width) when is_integer(width) do
    right_width = TextWidth.display_width(right)

    case right do
      "" ->
        TextWidth.truncate(left, width)

      _ ->
        left_space = max(width - right_width - 1, 0)

        truncated_left = TextWidth.truncate(left, left_space)
        truncated_left_width = TextWidth.display_width(truncated_left)
        padding = max(width - truncated_left_width - right_width - 1, 0)

        truncated_left <> String.duplicate(" ", padding) <> " " <> right
    end
  end

  defp combine_title_parts(left, ""), do: left
  defp combine_title_parts(left, right), do: left <> " " <> right

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

  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {width, _height} when is_integer(width) -> max(width - 4, 0)
      _other -> nil
    end
  end
end

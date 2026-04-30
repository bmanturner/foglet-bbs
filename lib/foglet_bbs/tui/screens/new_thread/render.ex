defmodule Foglet.TUI.Screens.NewThread.Render do
  @moduledoc """
  Pure render entry point for the NewThread screen.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Composer.EditorFrame
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Post.MarkdownBody

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192
  @default_max_thread_title_length 60
  @default_terminal_size {80, 24}

  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)

    case state.step do
      :board -> render_board_step(frame_state, state)
      :compose -> render_compose_step(frame_state, state)
    end
  end

  defp render_board_step(state, ss) do
    theme = Theme.from_state(state)

    board_content =
      case ss.boards do
        nil ->
          column style: %{gap: 0} do
            [text("Loading boards…", fg: theme.dim.fg)]
          end

        [] ->
          column style: %{gap: 0} do
            [text(empty_board_message(ss), fg: theme.warning.fg)]
          end

        boards ->
          SelectionList.render(boards, ss.selected_board_index, fn {board, _idx, selected} ->
            ListRow.render(board.name, selected, theme)
          end)
      end

    ScreenFrame.render(state, new_thread_chrome(ss), board_content, [
      %{
        label: "Navigate",
        commands: [
          %{key: "j/k", label: "Select", priority: 10},
          %{key: "Enter", label: "Choose", priority: 10}
        ]
      },
      %{
        label: "Actions",
        commands: [%{key: "Esc", label: "Cancel", priority: 30}]
      }
    ])
  end

  defp render_compose_step(state, ss) do
    theme = Theme.from_state(state)
    {width, height} = state.terminal_size || @default_terminal_size
    cap = max_thread_title_length(ss)
    title_value = ss.title_input_state.raxol_state.value
    body_value = ss.body_input_state.value

    content =
      EditorFrame.render(
        mode: ss.mode,
        focused?: ss.focused == :body and ss.mode == :edit,
        context: compose_context(ss, title_value, width, theme),
        title: render_title_input(ss, theme),
        body: render_body_section(state, ss, theme),
        budgets: [
          %{label: "Title", count: String.length(title_value), limit: cap},
          %{label: "Body", count: String.length(body_value), limit: max_body_length(ss, state)}
        ],
        error: ss.error,
        width: max(width - 4, 20),
        height: max(height - 6, 10),
        theme: theme
      )

    ScreenFrame.render(state, new_thread_chrome(ss), content, [
      %{
        label: "Field",
        commands: [%{key: "Tab", label: compose_tab_hint(ss), priority: 10}]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Ctrl+S", label: "Submit", priority: 30},
          %{key: "Ctrl+C", label: "Cancel", priority: 30}
        ]
      }
    ])
  end

  defp new_thread_chrome(ss) do
    %{breadcrumb_parts: ["Foglet", board_label(ss), "New Thread"]}
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(_), do: "Boards"

  defp empty_board_message(%State{active_board_count: 0}) do
    "No active boards are available."
  end

  defp empty_board_message(%State{active_board_count: count})
       when is_integer(count) and count > 0 do
    "You aren't subscribed to any boards. Subscribe from Boards."
  end

  defp empty_board_message(_ss) do
    "You aren't subscribed to any boards. Subscribe from Boards."
  end

  defp compose_tab_hint(%{focused: :body, mode: :edit}), do: "Preview"
  defp compose_tab_hint(%{focused: :body, mode: :preview}), do: "Edit"
  defp compose_tab_hint(_ss), do: "Switch field"

  defp compose_context(ss, title_value, width, theme) do
    available = max(width - 10, 20)
    board_name = ss.board && Map.get(ss.board, :name, "Unknown board")

    [
      text("Board #{TextWidth.truncate(board_name || "Unknown board", available)}",
        fg: theme.dim.fg
      ),
      title_context(title_value, available, theme)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp title_context("", _available, _theme), do: nil

  defp title_context(title_value, available, theme) do
    text("Draft #{TextWidth.truncate(title_value, available)}", fg: theme.dim.fg)
  end

  defp render_title_input(ss, theme) do
    title_focused = ss.focused == :title
    title_label_fg = if title_focused, do: theme.accent.fg, else: theme.primary.fg
    title_label_style = if title_focused, do: [:bold], else: []

    row style: %{gap: 0} do
      [
        text("Title: ", fg: title_label_fg, style: title_label_style),
        TextInput.render(ss.title_input_state,
          bordered: false,
          focused: title_focused,
          theme: theme
        )
      ]
    end
  end

  defp render_body_section(state, ss, theme) do
    body_focused = ss.focused == :body
    {w, _h} = state.terminal_size || @default_terminal_size
    body_width = max(w - 4, 20)

    case ss.mode do
      :edit ->
        # D-09: delegate to shared widget. NewThread preserves its legacy
        # single-space placeholder for empty lines (see Plan 04-01's opt).
        render_body_input(ss.body_input_state, body_focused, theme, body_width)

      :preview ->
        MarkdownBody.render(ss.body_input_state.value, body_width, theme)
    end
  end

  defp render_body_input(input, focused?, theme, width),
    do: Compose.render_input(input, focused?, theme, width: width, empty_line_placeholder: " ")

  defp frame_state(%State{} = _state, %Context{} = context) do
    %{
      current_screen: :new_thread,
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route: context.route,
      route_params: context.route_params
    }
  end

  defp max_thread_title_length(%State{max_thread_title_length: n})
       when is_integer(n) and n > 0,
       do: n

  defp max_thread_title_length(_state), do: @default_max_thread_title_length

  defp max_body_length(ss, state) do
    sc = Map.get(state, :session_context) || %{}

    case Map.get(sc, :max_post_length) do
      n when is_integer(n) and n > 0 ->
        n

      _other ->
        max_body_length_from_state(ss)
    end
  end

  defp max_body_length_from_state(%State{max_post_length: n}) when is_integer(n) and n > 0,
    do: n

  defp max_body_length_from_state(_ss), do: @default_max_post_length
end

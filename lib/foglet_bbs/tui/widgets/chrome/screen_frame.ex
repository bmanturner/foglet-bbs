defmodule Foglet.TUI.Widgets.Chrome.ScreenFrame do
  @moduledoc """
  Outer screen chrome widget for Foglet BBS (FRAME-01, FRAME-02).

  Wraps every screen with:
    outer bordered box → column → StatusBar → divider → content_element → KeyBar

  Signature (locked — D-05):
    ScreenFrame.render(state, title, content_element, key_list)

  Where:
    state           — full app state; ScreenFrame reads current_user.handle
                      and session_context.theme internally (D-07)
    title           — screen/page title string (e.g., "Boards")
    content_element — pre-built Raxol element from caller (result of
                      column/row/box do...end block in the screen module)
    key_list        — [{key_label, description}] list passed to KeyBar

  Internal layout (locked — D-06):
    outer bordered box → column → StatusBar → divider → content_element → KeyBar
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.StatusBar
  alias Foglet.TUI.Widgets.Chrome.KeyBar

  @doc """
  Renders the full screen chrome wrapping the caller-provided content.
  """
  @spec render(map(), String.t(), any(), [{String.t(), String.t()}]) :: any()
  def render(state, title, content_element, key_list) do
    theme = get_in(state, [:session_context, :theme]) || Theme.default()

    box style: %{border: :single, padding: 1, border_color: theme.border.fg} do
      column style: %{gap: 0, justify_content: :space_between} do
        [
          column style: %{gap: 0} do
            [
              StatusBar.render(state, title),
              divider(),
              content_element
            ]
          end,
          KeyBar.render(theme, key_list)
        ]
      end
    end
  end
end

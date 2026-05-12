defmodule Foglet.TUI.Widgets.Chrome.StatusBar do
  @moduledoc """
  Themed top-of-screen status bar for Foglet BBS (FRAME-02).

  Renders a full-width row: "Foglet BBS — {title}" on the left,
  "@{handle}" or a clock-only guest state on the right. Background and text colors
  come from the theme's status_bar slot (reverse-video bar effect).

  Called by Chrome.ScreenFrame — screens do not call this directly.

  Copywriting contract (UI-SPEC):
    StatusBar left:  "Foglet BBS — {Screen Title}"
    StatusBar right (authed):  "@{handle}"
    StatusBar right (guest):   clock only
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.{BreadcrumbBar, ClockFormatter}

  @doc """
  Renders the status bar with Chrome V2 breadcrumb data.

  `state` — the full app state. Reads `state.current_user.handle` and
             `state.session_context.theme` (falls back to Theme.default()).
  `title` — a list of breadcrumb parts (e.g., `["Foglet", "Home"]`) or a
             chrome model map containing `:breadcrumb_parts` or `:parts`.
  `opts`  — keyword list forwarded to `BreadcrumbBar.format/2`
             (e.g., `width: 80`).

  Shape: a `row` with `justify_content: :space_between`. Parent columns
  in ScreenFrame must set `align_items: :stretch` so this row receives
  the full container width; `:space_between` then pushes the handle to
  the right edge. `bg` on each `text` (when the theme sets one) paints
  behind the visible characters only — the gap between stays the
  terminal default.
  """
  def render(state, title, opts) do
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    left = left_text(title, opts)
    right = status_atoms(state) |> Enum.join(" | ")

    fg = Map.get(theme.status_bar, :fg)
    bg = Map.get(theme.status_bar, :bg)

    # Kept `justify_content: :space_between` over `spacer()` per 08-06 audit —
    # spacer/1 is fixed-size (vendor/raxol/lib/raxol/view/components.ex:164),
    # cannot reproduce the flex-grow push-to-opposite-ends behavior without
    # caller-computed widths.
    row style: %{justify_content: :space_between} do
      [
        text(" #{left}", fg: fg, bg: bg),
        text("#{right} ", fg: fg, bg: bg)
      ]
    end
  end

  @doc """
  Returns ordered right-side status atoms for the state's presentation mode.

  Presentation mode is display metadata only; this function does not authorize
  or unlock any operator behavior.
  """
  @spec status_atoms(map()) :: [String.t()]
  def status_atoms(state) when is_map(state) do
    mode = Presentation.mode_for!(Map.get(state, :current_screen))

    case authenticated_user(state) do
      nil -> [ClockFormatter.format(clock_instant(state), nil)]
      user -> user_status_atoms(state, user, mode)
    end
  end

  defp left_text(parts, opts) when is_list(parts), do: BreadcrumbBar.format(parts, opts)

  defp left_text(%{} = model, opts) do
    cond do
      is_list(Map.get(model, :breadcrumb_parts)) ->
        BreadcrumbBar.format(Map.get(model, :breadcrumb_parts), opts)

      is_list(Map.get(model, :parts)) ->
        BreadcrumbBar.format(Map.get(model, :parts), opts)

      true ->
        BreadcrumbBar.format([], opts)
    end
  end

  defp user_status_atoms(state, user, :bbs) do
    [
      user_atom(user),
      unread_atom(state),
      present_string(Map.get(state, :activity_label)),
      ClockFormatter.format(clock_instant(state), user)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp user_status_atoms(state, user, :operator) do
    [
      user_atom(user),
      scope_atom(state),
      present_string(Map.get(state, :system_status)),
      ClockFormatter.format(clock_instant(state), user)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp authenticated_user(%{current_user: %{handle: handle} = user}) when is_binary(handle),
    do: user

  defp authenticated_user(_state), do: nil

  defp user_atom(%{handle: handle}), do: "@#{handle}"

  defp unread_atom(%{unread_notifications_count: count}) when is_integer(count) and count > 0,
    do: "N #{count}"

  defp unread_atom(_state), do: nil

  defp scope_atom(%{operator_scope: scope}), do: present_string(scope, "scope ")
  defp scope_atom(_state), do: nil

  defp present_string(value, prefix \\ "")
  defp present_string(value, _prefix) when value in [nil, ""], do: nil
  defp present_string(value, prefix), do: prefix <> to_string(value)

  defp clock_instant(state) do
    session_context = Map.get(state, :session_context) || %{}

    case Map.get(session_context, :clock_now) do
      %DateTime{} = instant -> instant
      _ -> DateTime.utc_now()
    end
  end
end

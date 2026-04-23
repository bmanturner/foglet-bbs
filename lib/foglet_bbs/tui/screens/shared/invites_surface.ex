defmodule Foglet.TUI.Screens.Shared.InvitesSurface do
  @moduledoc """
  Shared INVITES surface primitive for Account, Moderation, and Sysop shells
  (Phase 0 Success Criterion 3; D-06, D-07).

  Phase 0 scope (D-13): placeholder/loading/error scaffolding ONLY. No live
  invite generation, revocation, or persistence. Later phases (3 activates
  persistence, 4 activates the surface) attach real behavior without
  modifying any consuming shell.

  Visibility rules (D-02, research Pattern 4):
    * `:sysop` — always visible (Phase 0 convention)
    * `:mod`   — visible when `invite_code_generators == "mods"`
    * `:user`  — visible when `invite_code_generators == "any_user"`
    * otherwise — hidden

  Pitfall 3 (RESEARCH.md): menu visibility is NOT authorization — this predicate
  controls UI rendering only. Real authz enforcement is owned by Phase 1.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Progress.Spinner

  @title "INVITES"

  @spec title() :: String.t()
  def title, do: @title

  @spec default_state() :: InvitesState.t()
  def default_state, do: InvitesState.new([])

  @spec visible?(map() | nil, String.t() | nil) :: boolean()
  def visible?(nil, _policy), do: false
  def visible?(%{role: :sysop}, _policy), do: true
  def visible?(%{role: :mod}, "mods"), do: true
  def visible?(%{role: :user}, "any_user"), do: true
  def visible?(_, _), do: false

  @spec render(map(), Theme.t()) :: any()
  def render(%{items: nil, frame: frame}, %Theme{} = theme) when is_integer(frame),
    do: render_loading(frame, theme)

  def render(%{items: nil}, %Theme{} = theme), do: render_loading(current_frame(), theme)

  def render(%{items: []}, %Theme{} = theme), do: render_placeholder(theme)

  def render(%{items: [_ | _] = items}, %Theme{} = theme),
    do: render_future_placeholder(items, theme)

  # Monotonic-clock fallback frame when the caller does not supply one.
  # Kept so Phase 0 callers (which pass no :frame) still see an animated
  # spinner. Later phases that want deterministic / snapshot-friendly
  # rendering should thread :frame through state (e.g. from a
  # subscribe_interval tick) and avoid this branch.
  defp current_frame do
    System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())
  end

  defp render_loading(frame, theme) when is_integer(frame) do
    spinner_el = Spinner.render(frame, style: :line, theme: theme)
    loading_el = text("Loading…", fg: theme.dim.fg)

    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [spinner_el, loading_el]
        end
      ]
    end
  end

  defp render_placeholder(theme) do
    column style: %{gap: 0} do
      [text("Invite management is scaffolded for a later phase.", fg: theme.warning.fg)]
    end
  end

  defp render_future_placeholder(items, theme) do
    column style: %{gap: 0} do
      [
        text(
          "Invites scaffold — #{length(items)} entries will render once Phase 4 activates this tab.",
          fg: theme.dim.fg
        )
      ]
    end
  end
end

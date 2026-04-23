defmodule Foglet.TUI.Screens.Shared.InvitesState do
  @moduledoc """
  Screen-local state shared by Account, Moderation, and Sysop shells for the
  future-facing INVITES tab (D-06, D-07).

  Placeholder/loading/error semantics (D-12):
    * `items: []`  — scaffold-only placeholder branch (default)
    * `items: nil` — loading branch (Spinner in `InvitesSurface.render/2`)

  Phase 0 never mutates this state from fake operator actions (D-13); later
  phases (3, 4) will populate `items` with real `%Foglet.Invites.Invite{}`
  records.

  See `Foglet.TUI.Screens.Shared.InvitesSurface` for rendering and visibility
  logic that consumes this struct.
  """

  # TODO(phase-4): tighten :items to [%Foglet.Invites.Invite{}] and add
  # per-element validation in validate_items!/1. Phase 0 never looks inside
  # items, but persistence activation (Phase 4) will silently accept garbage
  # without tighter shape checks.
  @type t :: %__MODULE__{items: list() | nil}
  defstruct items: []

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    items = Keyword.get(opts, :items, [])
    validate_items!(items)
    %__MODULE__{items: items}
  end

  defp validate_items!(nil), do: :ok
  defp validate_items!(items) when is_list(items), do: :ok

  defp validate_items!(other) do
    raise ArgumentError,
          "Foglet.TUI.Screens.Shared.InvitesState :items must be a list or nil; got #{inspect(other)}"
  end
end

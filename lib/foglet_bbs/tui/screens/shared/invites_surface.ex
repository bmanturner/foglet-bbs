defmodule Foglet.TUI.Screens.Shared.InvitesSurface do
  @moduledoc """
  Shared live INVITES surface primitive for Account, Moderation, and Sysop
  shells (D-06, D-07).

  Visibility rules (D-02, research Pattern 4):
    * `:sysop` — always visible
    * `:mod`   — visible when `invite_code_generators == "mods"`
    * `:user`  — visible when `invite_code_generators == "any_user"`
    * otherwise — hidden

  Pitfall 3 (RESEARCH.md): menu visibility is NOT authorization — this predicate
  controls UI rendering only. Real authz enforcement is owned by Phase 1.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner

  @title "INVITES"
  @key_hints "G Generate   R Refresh   D Revoke   ↑/↓ Select"

  @spec title() :: String.t()
  def title, do: @title

  @spec default_state() :: InvitesState.t()
  def default_state, do: InvitesState.new()

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

  def render(%{items: []} = state, %Theme{} = theme), do: render_items(state, theme)

  def render(%{items: [_ | _]} = state, %Theme{} = theme), do: render_items(state, theme)

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

  defp render_items(%{items: items} = state, theme) when is_list(items) do
    selected_index = Map.get(state, :selected_index, 0)
    last_generated_code = Map.get(state, :last_generated_code)
    error = Map.get(state, :error)

    column style: %{gap: 1} do
      [
        maybe_banner(last_generated_code, theme),
        maybe_error(error, theme),
        invite_rows(items, selected_index, theme),
        text(@key_hints, fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp maybe_banner(nil, _theme), do: nil

  defp maybe_banner(code, theme) when is_binary(code) do
    text("New invite code: #{code}", fg: theme.accent.fg)
  end

  defp maybe_error(nil, _theme), do: nil

  defp maybe_error(error, theme) when is_binary(error) do
    text(error, fg: theme.error.fg)
  end

  defp invite_rows([], _selected_index, theme) do
    text("No invites issued yet.", fg: theme.dim.fg)
  end

  defp invite_rows(items, selected_index, theme) do
    SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
      item
      |> row_label()
      |> ListRow.render(selected?, theme)
    end)
  end

  defp row_label(item) do
    base = [
      field(item, :code),
      "status: #{field(item, :status)}",
      "issuer_id: #{field(item, :issuer_id)}",
      "inserted_at: #{timestamp_field(item, :inserted_at)}"
    ]

    item
    |> lifecycle_fields()
    |> then(&(base ++ &1))
    |> Enum.join(" | ")
  end

  defp lifecycle_fields(%{status: :consumed} = item) do
    [
      "consumed_at: #{timestamp_field(item, :consumed_at)}",
      "consumed_by_user_id: #{field(item, :consumed_by_user_id)}"
    ]
  end

  defp lifecycle_fields(%{status: :revoked} = item) do
    ["revoked_at: #{timestamp_field(item, :revoked_at)}"]
  end

  defp lifecycle_fields(_item), do: []

  defp field(item, key) do
    item
    |> Map.get(key)
    |> to_string()
  end

  defp timestamp_field(item, key) do
    case Map.get(item, key) do
      %DateTime{} = timestamp -> Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%SZ")
      nil -> ""
      other -> to_string(other)
    end
  end
end

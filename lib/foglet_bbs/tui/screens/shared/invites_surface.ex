defmodule Foglet.TUI.Screens.Shared.InvitesSurface do
  @moduledoc """
  Shared live INVITES surface primitive for Account, Moderation, and Sysop
  shells (D-06, D-07).

  Visibility rules (D-02, research Pattern 4; FOG-615):
    * `registration_mode == "invite_only"` is required for this UI to be shown.
    * `:sysop` — visible in invite-only mode for operator invite management.
    * `:mod`   — visible in invite-only mode when `invite_code_generators == "mods"`.
    * `:user`  — visible in invite-only mode when `invite_code_generators == "any_user"`.
    * `"open"` and `"sysop_approved"` modes hide INVITES everywhere; those
      onboarding modes do not ask a normal user for an invite code.
    * otherwise — hidden

  Pitfall 3 (RESEARCH.md): menu visibility is NOT authorization — this predicate
  controls UI rendering only. Real authz enforcement remains in the Accounts/
  Invites domain actions even if UI visibility drifts.

  Phase 25 Plan 03: listing renders through `Display.ConsoleTable` with selection
  ownership inside the widget (D-05). The bespoke SelectionList+ListRow render
  is replaced; both Account and Moderation benefit from a single code path.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner

  @title "INVITES"
  @key_hints "G Generate invite   R Refresh   D Revoke invite   ↑/↓ Select"

  @spec title() :: String.t()
  def title, do: @title

  @spec default_state() :: InvitesState.t()
  def default_state, do: InvitesState.new()

  @spec visible?(map() | nil, String.t() | nil, String.t() | nil) :: boolean()
  def visible?(nil, _policy, _registration_mode), do: false
  def visible?(_user, _policy, mode) when mode != "invite_only", do: false
  def visible?(%{role: :sysop}, _policy, "invite_only"), do: true
  def visible?(%{role: :mod}, "mods", "invite_only"), do: true
  def visible?(%{role: :user}, "any_user", "invite_only"), do: true
  def visible?(_, _, _), do: false

  @spec render(map(), Theme.t(), keyword()) :: any()
  def render(state, theme, opts \\ [])

  def render(%InvitesState{mode: :confirm_revoke} = state, %Theme{} = theme, _opts),
    do: render_confirm_revoke(state, theme)

  def render(%{items: nil, frame: frame}, %Theme{} = theme, _opts) when is_integer(frame),
    do: render_loading(frame, theme)

  def render(%{items: nil}, %Theme{} = theme, _opts), do: render_loading(current_frame(), theme)

  def render(%{items: []} = state, %Theme{} = theme, opts), do: render_items(state, theme, opts)

  def render(%{items: [_ | _]} = state, %Theme{} = theme, opts),
    do: render_items(state, theme, opts)

  # FOG-164: destructive confirmation for revoking an invite (Moderation+Account).
  defp render_confirm_revoke(%InvitesState{confirm_target: target}, theme) do
    code = (target && target.code) || ""

    column style: %{gap: 1} do
      [
        text("Revoke invite #{code}?", fg: theme.accent.fg),
        text(
          "Code #{code} will stop working. Existing accounts stay intact.",
          fg: theme.primary.fg
        ),
        text("Enter Revoke invite   Esc Keep invite", fg: theme.dim.fg)
      ]
    end
  end

  # Monotonic-clock fallback frame when the caller does not supply one.
  defp current_frame do
    System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())
  end

  defp render_loading(frame, theme) when is_integer(frame) do
    spinner_el = Spinner.render(frame, style: :line, theme: theme)
    loading_el = text("Loading invites…", fg: theme.dim.fg)

    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [spinner_el, loading_el]
        end
      ]
    end
  end

  # InvitesState struct path — renders the ConsoleTable header (so column
  # labels remain visible) and bespoke focus-aware text rows for the row
  # content. Phase 29 D-24: focused INVITES row carries theme.selected.fg/bg
  # styling at 80×24 SSH; the upstream Raxol Table widget flattens cell
  # styles into `style: [...]` rather than the top-level `:fg`/`:bg`, which
  # is not visibly distinct on the ANSI-stripped renderer.
  defp render_items(%InvitesState{items: []} = state, theme, _opts) do
    last_generated_code = state.last_generated_code
    error = state.error
    table = state.table || InvitesState.build_table([])

    column style: %{gap: 1} do
      [
        maybe_banner(last_generated_code, theme),
        maybe_error(error, theme),
        ConsoleTable.render(table, theme: theme),
        text(@key_hints, fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_items(
         %InvitesState{items: items, selected_index: selected_index} = state,
         theme,
         opts
       )
       when is_list(items) do
    last_generated_code = state.last_generated_code
    error = state.error

    column style: %{gap: 1} do
      [
        maybe_banner(last_generated_code, theme),
        maybe_error(error, theme),
        render_boxed_table(items, theme, opts),
        focused_invite_indicator(items, selected_index, theme),
        text(@key_hints, fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  # Legacy raw-map path — preserves SelectionList+ListRow rendering for backward
  # compatibility with callers and tests that pass plain maps (D-19).
  defp render_items(%{items: items} = state, theme, _opts) when is_list(items) do
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

  defp invite_rows([], _selected_index, theme) do
    text("No invites yet. Generate one when someone is ready to join.", fg: theme.dim.fg)
  end

  # Phase 29 D-24 (SYSOP-06): focused INVITES row carries theme.selected.fg/bg
  # so the operator can see which row is focused at 80×24 SSH. Unfocused rows
  # render with theme.primary.fg via ListRow's `selected?: false` path. This
  # mirrors the canonical idiom at users_view.ex:189-198. No leading marker
  # (D-24 explicit rejection).
  defp invite_rows(items, selected_index, theme) do
    SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
      label = row_label(item)

      if selected? do
        text(label, fg: theme.selected.fg, bg: theme.selected.bg)
      else
        ListRow.render(label, false, theme)
      end
    end)
  end

  defp row_label(item) do
    base = [
      field(item, :code),
      "status: #{field(item, :status)}",
      "issued by: #{field(item, :issuer_id)}",
      "issued: #{timestamp_field(item, :inserted_at)}"
    ]

    item
    |> lifecycle_fields()
    |> then(&(base ++ &1))
    |> Enum.join(" | ")
  end

  defp lifecycle_fields(%{status: :consumed} = item) do
    [
      "used: #{timestamp_field(item, :consumed_at)}",
      "used by: #{field(item, :consumed_by_user_id)}"
    ]
  end

  defp lifecycle_fields(%{status: :revoked} = item) do
    ["revoked: #{timestamp_field(item, :revoked_at)}"]
  end

  defp lifecycle_fields(_item), do: []

  # Phase 29 D-24 (SYSOP-06): the upstream Raxol Table flattens the
  # `selected_row` style into nested `style: [...]` entries that aren't
  # surfaced as visibly-distinct text fg/bg at 80×24 SSH after layout. We
  # emit a focus-aware status line below the table so the operator can see
  # which invite row is focused. The line carries `theme.selected.fg/bg`
  # styling, mirroring the UsersView idiom at users_view.ex:189-198. No
  # leading per-row marker is emitted (D-24 rejects glyph-marker designs).
  defp focused_invite_indicator([], _selected_index, _theme), do: nil

  defp focused_invite_indicator(items, selected_index, theme)
       when is_list(items) and is_integer(selected_index) do
    case Enum.at(items, selected_index) do
      nil ->
        nil

      item ->
        label = "Selected invite: #{focused_row_label(item)}"
        text(label, fg: theme.selected.fg, bg: theme.selected.bg)
    end
  end

  defp focused_invite_indicator(_items, _selected_index, _theme), do: nil

  # A compact one-line summary of the focused invite — friendly labels per
  # FOG-127 (no schema names like consumed_by_user_id / revoked_at).
  defp focused_row_label(item) do
    code = field(item, :code)
    status = field(item, :status)

    base = "#{code} — #{status}"

    case item do
      %{status: :consumed} ->
        base <> " — used by #{field(item, :consumed_by_user_id)}"

      %{status: :revoked} ->
        base <> " — revoked #{timestamp_field(item, :revoked_at)}"

      _ ->
        base
    end
  end

  defp field(item, key) do
    item |> Map.get(key) |> to_string()
  end

  defp timestamp_field(item, key) do
    case Map.get(item, key) do
      %DateTime{} = timestamp -> Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%SZ")
      nil -> ""
      other -> to_string(other)
    end
  end

  defp maybe_banner(nil, _theme), do: nil

  defp maybe_banner(code, theme) when is_binary(code) do
    text("Invite code ready: #{code}. Share it once.", fg: theme.accent.fg)
  end

  defp maybe_error(nil, _theme), do: nil

  defp maybe_error(error, theme) when is_binary(error) do
    text(error, fg: theme.error.fg)
  end

  defp render_boxed_table(items, theme, opts) do
    width = Keyword.get(opts, :width, 72)
    visible_items = Enum.take(items, visible_row_capacity(opts))

    header =
      [
        pad_cell("Code", 26),
        pad_cell("Status", 10),
        pad_cell("Issued", 10),
        pad_cell("Used by", max(width - 46, 0))
      ]
      |> Enum.join()

    rows = Enum.map(visible_items, &table_row_line(&1, width))

    box style: %{border_fg: theme.border.fg, padding: 0} do
      column style: %{gap: 0} do
        [text(header, fg: theme.title.fg) | Enum.map(rows, &text(&1, fg: theme.primary.fg))]
      end
    end
  end

  defp table_row_line(item, width) do
    [
      pad_cell(field(item, :code), 26),
      pad_cell(field(item, :status), 10),
      pad_cell(short_timestamp_field(item, :inserted_at), 10),
      pad_cell(field(item, :consumed_by_user_id), max(width - 46, 0))
    ]
    |> Enum.join()
  end

  defp pad_cell(value, width) when width > 0 do
    value
    |> to_string()
    |> String.slice(0, width)
    |> String.pad_trailing(width)
  end

  defp pad_cell(_value, _width), do: ""

  defp visible_row_capacity(opts) do
    case Keyword.get(opts, :height) do
      height when is_integer(height) and height > 3 -> max(height - 3, 1)
      _ -> 10
    end
  end

  defp short_timestamp_field(item, key) do
    case Map.get(item, key) do
      %DateTime{} = timestamp -> Calendar.strftime(timestamp, "%Y-%m-%d")
      nil -> ""
      other -> to_string(other)
    end
  end
end

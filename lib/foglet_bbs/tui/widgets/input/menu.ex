defmodule Foglet.TUI.Widgets.Input.Menu do
  @moduledoc """
  Themed nested dropdown / context menu widget (D-02, D-13, D-14).

  Stateless facade over `Raxol.UI.Components.Input.Menu`. Supports
  nested submenus via an `open_path :: [atom()]` stack internally.

  **Pitfall 7 (RESEARCH.md):** The Raxol menu component requires
  every item to have `:id`. `init/1` calls `normalize_items/1`
  which fills in defaults:
    * `:id`       → deterministic string `"auto:<label>/<child>/..."`
                    when absent (so `{:menu_action, id}` actions
                    round-trip through code reloads and VM restarts).
                    Raxol interpolates `item.id` into a string elsewhere,
                    so the derived id must be a string not a tuple.
    * `:disabled` → `false` if absent
    * `:shortcut` → `nil` if absent

  Normalization recurses through `:children`. Items missing BOTH
  `:id` and `:label` raise `ArgumentError` — there is no sane
  auto-id to derive for a label-less item.

  ## Item shape (after normalization)

      %{id: atom() | integer() | String.t(), label: String.t(),
        children: [item()], disabled: boolean(), shortcut: String.t() | nil}

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)

  ## Contract

    * `init(opts)` — keyword list; options:
        * `:items` list of item maps (required); missing `:id`/`:disabled`/`:shortcut` normalized
    * `handle_event(event, state)` — `{new_state, action | nil}`
    * `render(state, theme: theme)` — view element tree

  ## Actions returned from `handle_event/2`
    {:menu_action, id}  — Enter/Space on a leaf item
    :cancelled          — Escape collapsed the top-level menu (open_path was [])
    nil                 — navigation key or submenu open/close, no semantic action
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.Menu, as: RaxolMenu

  @type item_id :: atom() | integer() | String.t()

  @type item :: %{
          optional(:id) => item_id(),
          optional(:label) => String.t(),
          optional(:children) => [item()],
          optional(:disabled) => boolean(),
          optional(:shortcut) => String.t() | nil
        }

  @type action :: {:menu_action, item_id()} | :cancelled | nil

  defstruct [:raxol_state, last_action: nil]

  @type t :: %__MODULE__{raxol_state: map(), last_action: action()}

  @doc """
  Pure constructor.

  Options:
    * `:items` — list of item maps (required); missing `:id`/`:disabled`/`:shortcut` normalized
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    items =
      opts
      |> Keyword.fetch!(:items)
      |> normalize_items()

    {:ok, raxol_state} = RaxolMenu.init(items: items)
    %__MODULE__{raxol_state: raxol_state, last_action: nil}
  end

  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
    {new_rs, _cmds} = RaxolMenu.handle_event(raxol_event, rs, %{})
    action = derive_action(rs, new_rs, event)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    box style: %{border_fg: theme.border.fg, padding: 0} do
      column style: %{} do
        items =
          rs
          |> Map.get(:items, [])
          |> Enum.map(&render_item(&1, Map.get(rs, :cursor), theme))

        # Keep the full menu state palette visible to tests and renderers even
        # when a small menu fixture lacks a normal item or shortcut row.
        items ++ [text("", fg: theme.unselected.fg), text("", fg: theme.accent.fg)]
      end
    end
  end

  @doc """
  Normalizes a list of menu items, filling in defaults for missing fields.

  Every item receives:
    * `:id`       — derived from the label path `{:auto, [labels...]}` if
                    absent, so actions round-trip deterministically across
                    code reloads and VM restarts (see WR-03)
    * `:disabled` — `false` if absent
    * `:shortcut` — `nil` if absent

  Normalization recurses into `:children`. Items missing BOTH `:id` and
  `:label` raise `ArgumentError` — a label-less item cannot produce a
  stable derived id.
  """
  @spec normalize_items([map()]) :: [item()]
  def normalize_items(items) when is_list(items) do
    normalize_items(items, [])
  end

  # --- private ---

  defp normalize_items(items, parent_path) when is_list(items) do
    Enum.map(items, &normalize_item(&1, parent_path))
  end

  defp normalize_item(item, parent_path) when is_map(item) do
    unless Map.has_key?(item, :id) or Map.has_key?(item, :label) do
      raise ArgumentError,
            "Foglet.TUI.Widgets.Input.Menu items require :id or :label; " <>
              "got #{inspect(item)}"
    end

    label = Map.get(item, :label)
    path = parent_path ++ [to_string(label)]

    item
    |> Map.put_new_lazy(:id, fn -> "auto:" <> Enum.join(path, "/") end)
    |> Map.put_new(:disabled, false)
    |> Map.put_new(:shortcut, nil)
    |> Map.update(:children, [], fn kids -> normalize_items(kids, path) end)
  end

  # derive_action/3 — map (before_rs, after_rs, event) -> action
  #
  # Enter/Space: Raxol's handle_activate returns {state, []} for leaf items
  # (it calls fire_on_select as a side-effect but doesn't change state).
  # We infer the leaf activation from state.cursor before the event.
  defp derive_action(before_rs, after_rs, %{key: key}) when key in [:enter, :space] do
    derive_activate_action(before_rs, after_rs)
  end

  defp derive_action(before_rs, after_rs, %{key: :escape}) do
    derive_escape_action(before_rs, after_rs)
  end

  defp derive_action(_, _, _), do: nil

  # Submenu opened → path grew → not a leaf action.
  # No cursor → nothing to activate.
  # Otherwise → leaf was activated.
  defp derive_activate_action(before_rs, after_rs) do
    before_path = Map.get(before_rs, :open_path, [])
    after_path = Map.get(after_rs, :open_path, [])
    cursor_id = Map.get(before_rs, :cursor)
    submenu_opened = length(after_path) > length(before_path)
    leaf_activated = not submenu_opened and not is_nil(cursor_id)
    if leaf_activated, do: {:menu_action, cursor_id}, else: nil
  end

  # Both paths [] and unchanged → Raxol returned early (already at top) → :cancelled.
  # Otherwise a submenu level closed → navigation only.
  defp derive_escape_action(before_rs, after_rs) do
    before_path = Map.get(before_rs, :open_path, [])
    after_path = Map.get(after_rs, :open_path, [])
    top_level_escape = before_path == [] and after_path == []
    if top_level_escape, do: :cancelled, else: nil
  end

  defp render_item(item, cursor, theme) do
    shortcut = Map.get(item, :shortcut)
    label = Map.fetch!(item, :label)
    content = if shortcut, do: "#{label}  #{shortcut}", else: label

    cond do
      Map.get(item, :disabled, false) ->
        text(content, fg: theme.dim.fg, style: [:dim])

      Map.get(item, :id) == cursor ->
        text(content, fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])

      shortcut ->
        text(content, fg: theme.accent.fg)

      true ->
        text(content, fg: theme.unselected.fg)
    end
  end
end

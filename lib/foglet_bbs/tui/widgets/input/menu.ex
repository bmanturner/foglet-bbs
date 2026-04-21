defmodule Foglet.TUI.Widgets.Input.Menu do
  @moduledoc """
  Themed nested dropdown / context menu widget (D-02, D-13, D-14).

  Stateless facade over `Raxol.UI.Components.Input.Menu`. Supports
  nested submenus via an `open_path :: [atom()]` stack internally.

  **Pitfall 7 (RESEARCH.md):** The Raxol menu component requires
  every item to have `:id`. `init/1` calls `normalize_items/1`
  which fills in defaults:
    * `:id`       → `:erlang.unique_integer([:positive])` if absent
    * `:disabled` → `false` if absent
    * `:shortcut` → `nil` if absent

  Normalization recurses through `:children`.

  ## Item shape (after normalization)

      %{id: atom() | integer(), label: String.t(),
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

  @type item :: %{
          optional(:id) => atom() | integer(),
          required(:label) => String.t(),
          optional(:children) => [item()],
          optional(:disabled) => boolean(),
          optional(:shortcut) => String.t() | nil
        }

  @type action :: {:menu_action, atom() | integer()} | :cancelled | nil

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

    rs_with_theme = %{rs | theme: build_menu_theme(theme)}

    box style: %{border_fg: theme.border.fg, padding: 0} do
      RaxolMenu.render(rs_with_theme, %{})
    end
  end

  @doc """
  Normalizes a list of menu items, filling in defaults for missing fields.

  Every item receives:
    * `:id`       — `:erlang.unique_integer([:positive])` if absent
    * `:disabled` — `false` if absent
    * `:shortcut` — `nil` if absent

  Normalization recurses into `:children`.
  """
  @spec normalize_items([map()]) :: [item()]
  def normalize_items(items) when is_list(items) do
    Enum.map(items, &normalize_item/1)
  end

  # --- private ---

  defp normalize_item(item) when is_map(item) do
    item
    |> Map.put_new_lazy(:id, fn -> :erlang.unique_integer([:positive]) end)
    |> Map.put_new(:disabled, false)
    |> Map.put_new(:shortcut, nil)
    |> Map.update(:children, [], &normalize_items/1)
  end

  # derive_action/3 — map (before_rs, after_rs, event) -> action
  #
  # Enter/Space: Raxol's handle_activate returns {state, []} for leaf items
  # (it calls fire_on_select as a side-effect but doesn't change state).
  # We infer the leaf activation from state.cursor before the event.
  defp derive_action(before_rs, after_rs, %{key: key}) when key in [:enter, :space] do
    cursor_id = Map.get(before_rs, :cursor)
    before_path = Map.get(before_rs, :open_path, [])
    after_path = Map.get(after_rs, :open_path, [])

    cond do
      # Submenu was opened — cursor moved into children; not a leaf action
      length(after_path) > length(before_path) ->
        nil

      # Cursor is on a leaf item with a known id
      is_nil(cursor_id) ->
        nil

      true ->
        {:menu_action, cursor_id}
    end
  end

  defp derive_action(before_rs, after_rs, %{key: :escape}) do
    before_path = Map.get(before_rs, :open_path, [])
    after_path = Map.get(after_rs, :open_path, [])

    cond do
      # State didn't change — Raxol returned early because path was already []
      before_path == [] and after_path == [] -> :cancelled
      # A submenu level was closed — navigate up, no semantic action
      true -> nil
    end
  end

  defp derive_action(_, _, _), do: nil

  defp build_menu_theme(%Theme{} = t) do
    %{
      item: %{fg: t.primary.fg},
      active_item: %{fg: t.selected.fg, bg: t.selected.bg, style: [:bold]},
      disabled_item: %{fg: t.dim.fg, style: [:dim]},
      shortcut: %{fg: t.accent.fg}
    }
  end
end

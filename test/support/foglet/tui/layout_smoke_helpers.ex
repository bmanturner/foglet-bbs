defmodule Foglet.TUI.LayoutSmokeHelpers do
  @moduledoc """
  Test-support helpers for per-tab size-contract smoke tests added in Phase 25
  (D-09, D-11). Plans 02/03/04 use `set_active_tab/2` to activate a named tab
  inside a screen_state map before rendering.
  """

  alias Foglet.TUI.Widgets.Input.Tabs

  @doc """
  Set the active tab on a screen state struct by tab label string.

  Tab name is the upcased label as it appears in the screen's `@base_tabs`
  list (e.g. "PROFILE", "PREFS", "SSH KEYS", "QUEUE", "LOG", "USERS",
  "BOARDS", "INVITES", "SITE", "LIMITS", "SYSTEM").

  Returns the updated screen state struct. Raises if the tab label is not
  found in the state's tab_labels list.

  All three operator screens use `:active_tab` (integer index) and `:tabs`
  (Foglet.TUI.Widgets.Input.Tabs struct). This helper reinitialises the Tabs
  widget at the target index and sets active_tab accordingly.
  """
  @spec set_active_tab(map(), String.t()) :: map()
  def set_active_tab(screen_state, tab_name) when is_binary(tab_name) do
    labels = screen_state.tab_labels

    idx =
      Enum.find_index(labels, &(&1 == tab_name)) ||
        raise ArgumentError,
              "set_active_tab: tab #{inspect(tab_name)} not found in #{inspect(labels)}"

    tabs = Tabs.init(tabs: labels, active: idx)
    %{screen_state | active_tab: idx, tabs: tabs}
  end
end

defmodule Foglet.TUI.Theme do
  @moduledoc """
  Theme registry and per-session flat snapshot for Foglet BBS TUI.

  Two responsibilities:

  1. **Registry** — Palettes are defined as `Raxol.UI.Theming.Theme` structs
     and registered via `Raxol.UI.Theming.Theme.register/1` on app boot.
     Each Foglet slot (`border`, `primary`, `status_bar`, ...) is stored
     under the Raxol theme's `:component_styles`. This lets future
     Raxol-aware widgets read the same theme definitions, and gives us a
     painless upgrade path to user-selectable themes later.

  2. **Session snapshot** — `%Foglet.TUI.Theme{}` is a flat struct held in
     `state.session_context.theme`. Screens read slots as `theme.border.fg`
     etc., which is fast in render paths and keeps widget code terse.
     `resolve/1` looks up the registered Raxol theme and projects its
     component styles into the flat struct.

  Slots (locked in UI-SPEC D-01/D-02):
    border, primary, dim, accent, title, error, warning,
    selected, unselected, status_bar

  Call `Foglet.TUI.Theme.register_all/0` on app boot (see
  `Foglet.Application.start/2`). `resolve/1` falls back to a static
  palette if the Raxol registry has not been populated yet (e.g. in
  tests that don't boot the application).
  """

  alias Raxol.UI.Theming.Theme, as: RaxolTheme

  @type style_map :: %{
          optional(:fg) => String.t(),
          optional(:bg) => String.t(),
          optional(:style) => [atom()]
        }

  @type t :: %__MODULE__{
          border: style_map(),
          primary: style_map(),
          dim: style_map(),
          accent: style_map(),
          title: style_map(),
          error: style_map(),
          warning: style_map(),
          selected: style_map(),
          unselected: style_map(),
          status_bar: style_map()
        }

  defstruct border: %{},
            primary: %{},
            dim: %{},
            accent: %{},
            title: %{},
            error: %{},
            warning: %{},
            selected: %{},
            unselected: %{},
            status_bar: %{}

  @slot_keys [
    :border,
    :primary,
    :dim,
    :accent,
    :title,
    :error,
    :warning,
    :selected,
    :unselected,
    :status_bar
  ]

  # Static palette definitions — the source of truth in code.
  # Registered into the Raxol theme system on app boot.

  @gray_slots %{
    border: %{fg: "#555555"},
    primary: %{fg: "#cccccc"},
    dim: %{fg: "#888888"},
    accent: %{fg: "#ffb000", style: [:bold]},
    title: %{fg: "#ffb000", style: [:bold]},
    error: %{fg: "#ff5555", style: [:bold]},
    warning: %{fg: "#ffff55"},
    selected: %{fg: "#000000", bg: "#aaaaaa", style: [:bold]},
    unselected: %{fg: "#cccccc"},
    status_bar: %{fg: "#ffb000"}
  }

  @green_slots %{
    border: %{fg: "#22aa44"},
    primary: %{fg: "#33ff66"},
    dim: %{fg: "#22aa44"},
    accent: %{fg: "#ffb000", style: [:bold]},
    title: %{fg: "#33ff66", style: [:bold]},
    error: %{fg: "#ff5555", style: [:bold]},
    warning: %{fg: "#ffff55"},
    selected: %{fg: "#000000", bg: "#33ff66", style: [:bold]},
    unselected: %{fg: "#33ff66"},
    status_bar: %{fg: "#33ff66"}
  }

  @amber_slots %{
    border:     %{fg: "#aa7700"},
    primary:    %{fg: "#ffb000"},
    dim:        %{fg: "#aa7700"},
    accent:     %{fg: "#ffcc44", style: [:bold]},
    title:      %{fg: "#ffcc44", style: [:bold]},
    error:      %{fg: "#ff5555", style: [:bold]},
    warning:    %{fg: "#ffff55"},
    selected:   %{fg: "#000000", bg: "#ffb000", style: [:bold]},
    unselected: %{fg: "#ffb000"},
    status_bar: %{fg: "#ffcc44"}
  }

  @cyan_slots %{
    border:     %{fg: "#0000aa"},
    primary:    %{fg: "#55ffff"},
    dim:        %{fg: "#00aaaa"},
    accent:     %{fg: "#ffff55", style: [:bold]},
    title:      %{fg: "#ffffff", style: [:bold]},
    error:      %{fg: "#ff5555", style: [:bold]},
    warning:    %{fg: "#ffff55"},
    selected:   %{fg: "#000000", bg: "#55ffff", style: [:bold]},
    unselected: %{fg: "#55ffff"},
    status_bar: %{fg: "#ffff55"}
  }

  @paper_slots %{
    border:     %{fg: "#555555"},
    primary:    %{fg: "#000000"},
    dim:        %{fg: "#555555"},
    accent:     %{fg: "#aa0000", style: [:bold]},
    title:      %{fg: "#000000", style: [:bold]},
    error:      %{fg: "#aa0000", style: [:bold]},
    warning:    %{fg: "#aa5500"},
    selected:   %{fg: "#cccccc", bg: "#000000", style: [:bold]},
    unselected: %{fg: "#000000"},
    status_bar: %{fg: "#000000"}
  }

  @magenta_slots %{
    border:     %{fg: "#aa00aa"},
    primary:    %{fg: "#ff55ff"},
    dim:        %{fg: "#aa00aa"},
    accent:     %{fg: "#55ffff", style: [:bold]},
    title:      %{fg: "#ff55ff", style: [:bold]},
    error:      %{fg: "#ff5555", style: [:bold]},
    warning:    %{fg: "#ffff55"},
    selected:   %{fg: "#000000", bg: "#ff55ff", style: [:bold]},
    unselected: %{fg: "#ff55ff"},
    status_bar: %{fg: "#ff55ff"}
  }

  @danger_slots %{
    border:     %{fg: "#aa0000"},
    primary:    %{fg: "#ffffff"},
    dim:        %{fg: "#888888"},
    accent:     %{fg: "#ff5555", style: [:bold]},
    title:      %{fg: "#ff5555", style: [:bold]},
    error:      %{fg: "#ffff55", style: [:bold]},
    warning:    %{fg: "#ffb000"},
    selected:   %{fg: "#000000", bg: "#ff5555", style: [:bold]},
    unselected: %{fg: "#ffffff"},
    status_bar: %{fg: "#ff5555"}
  }

  @ice_slots %{
    border:     %{fg: "#5555ff"},
    primary:    %{fg: "#aaaaaa"},
    dim:        %{fg: "#5555ff"},
    accent:     %{fg: "#55ffff", style: [:bold]},
    title:      %{fg: "#ffffff", style: [:bold]},
    error:      %{fg: "#ff5555", style: [:bold]},
    warning:    %{fg: "#ffff55"},
    selected:   %{fg: "#000000", bg: "#55ffff", style: [:bold]},
    unselected: %{fg: "#aaaaaa"},
    status_bar: %{fg: "#55ffff"}
  }

  @mono_slots %{
    border:     %{fg: "#555555"},
    primary:    %{fg: "#ffffff"},
    dim:        %{fg: "#888888"},
    accent:     %{fg: "#ffffff", style: [:bold]},
    title:      %{fg: "#ffffff", style: [:bold]},
    error:      %{fg: "#ffffff", style: [:bold]},
    warning:    %{fg: "#aaaaaa", style: [:bold]},
    selected:   %{fg: "#000000", bg: "#ffffff", style: [:bold]},
    unselected: %{fg: "#ffffff"},
    status_bar: %{fg: "#ffffff"}
  }

  # All theme id → slot-map pairs. Single source of truth for both
  # `register_all/0` and the `static_slots/1` test/pre-boot fallback.
  @themes %{
    gray: @gray_slots,
    green: @green_slots,
    amber: @amber_slots,
    cyan: @cyan_slots,
    paper: @paper_slots,
    magenta: @magenta_slots,
    danger: @danger_slots,
    ice: @ice_slots,
    mono: @mono_slots
  }

  @doc """
  Registers all Foglet TUI themes with Raxol's theme registry.
  Idempotent — safe to call multiple times. Call from
  `Foglet.Application.start/2`.
  """
  @spec register_all() :: :ok
  def register_all do
    Enum.each(@themes, fn {id, slots} ->
      :ok = RaxolTheme.register(build_raxol_theme(id, slots))
    end)

    :ok
  end

  @doc "List of registered theme ids."
  @spec ids() :: [atom()]
  def ids, do: Map.keys(@themes)

  @doc "Default theme (`:gray`) for v1.0.1."
  @spec default() :: t()
  def default, do: resolve(:gray)

  @doc "Returns a flat `%Foglet.TUI.Theme{}` snapshot for the given id."
  @spec resolve(atom()) :: t()
  def resolve(id) when is_atom(id) do
    raxol_theme = RaxolTheme.get(id)

    slots =
      if raxol_theme.id == id do
        Enum.into(@slot_keys, %{}, fn slot ->
          {slot, RaxolTheme.get_component_style(raxol_theme, slot)}
        end)
      else
        # Raxol returned the fallback default_theme — our registry is empty.
        # Use the static palette so tests and pre-boot calls still work.
        static_slots(id)
      end

    struct(__MODULE__, slots)
  end

  # --- private ---

  defp build_raxol_theme(id, slots) do
    RaxolTheme.new(%{
      id: id,
      name: Atom.to_string(id),
      component_styles: slots
    })
  end

  defp static_slots(id), do: Map.get(@themes, id, @gray_slots)
end

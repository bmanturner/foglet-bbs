defmodule Foglet.TUI.Theme do
  @moduledoc """
  Per-session theme struct for Foglet BBS TUI (v1.0.1).

  Resolved once per session in CLIHandler.build_context/3 and stored in
  state.session_context.theme. Screens read theme slots directly —
  no Raxol ThemeManager is used.

  Slots:
    border     — outer box border, divider lines
    primary    — body text, unselected list row text
    dim        — secondary labels, metadata text
    accent     — key hint brackets [K], highlighted labels
    title      — screen/section headings
    error      — error messages, validation failures
    warning    — warning/notice text
    selected   — selected list row (reverse-video)
    unselected — non-selected list rows
    status_bar — StatusBar reverse-video bar
  """

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

  defstruct [
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

  @doc "Returns the default theme (`:gray`) used for v1.0.1."
  @spec default() :: t()
  def default, do: gray()

  @doc "Gray/amber theme — the active theme for v1.0.1."
  @spec gray() :: t()
  def gray do
    %__MODULE__{
      border: %{fg: "#555555"},
      primary: %{fg: "#cccccc"},
      dim: %{fg: "#888888"},
      accent: %{fg: "#ffb000", style: [:bold]},
      title: %{fg: "#ffb000", style: [:bold]},
      error: %{fg: "#ff5555", style: [:bold]},
      warning: %{fg: "#ffff55"},
      selected: %{fg: "#000000", bg: "#aaaaaa", style: [:bold]},
      unselected: %{fg: "#cccccc"},
      status_bar: %{fg: "#000000", bg: "#aaaaaa"}
    }
  end

  @doc "Green phosphor theme — defined but inactive in v1.0.1."
  @spec green() :: t()
  def green do
    %__MODULE__{
      border: %{fg: "#22aa44"},
      primary: %{fg: "#33ff66"},
      dim: %{fg: "#22aa44"},
      accent: %{fg: "#ffb000", style: [:bold]},
      title: %{fg: "#33ff66", style: [:bold]},
      error: %{fg: "#ff5555", style: [:bold]},
      warning: %{fg: "#ffff55"},
      selected: %{fg: "#000000", bg: "#33ff66", style: [:bold]},
      unselected: %{fg: "#33ff66"},
      status_bar: %{fg: "#000000", bg: "#33ff66"}
    }
  end

  @doc "Resolve a theme by name atom. Unknown names fall back to :gray."
  @spec resolve(atom()) :: t()
  def resolve(:gray), do: gray()
  def resolve(:green), do: green()
  def resolve(_), do: gray()
end

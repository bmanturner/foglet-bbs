defmodule Foglet.TUI.Widgets.Chrome.BreadcrumbBar do
  @moduledoc """
  Shared Chrome V2 breadcrumb formatter for Foglet TUI screens.

  Stateless formatter (Phase 39 R3 / D-12): callers pass an explicit list of
  breadcrumb parts. The formatter is responsible only for join/separator
  selection and width-aware truncation. Screen modules build their own parts
  lists from local state and supply them via the chrome map they pass to
  `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @separator " ▸ "
  @ascii_separator " > "

  @doc """
  Formats breadcrumb parts with the default Unicode separator or ASCII fallback.
  """
  @spec format([term()], keyword()) :: String.t()
  def format(parts, opts \\ []) when is_list(parts) do
    separator = if Keyword.get(opts, :ascii?, false), do: @ascii_separator, else: @separator
    formatted = parts |> normalize_parts() |> Enum.join(separator)

    case Keyword.get(opts, :width) do
      width when is_integer(width) -> TextWidth.truncate(formatted, width)
      _ -> formatted
    end
  end

  @doc """
  Renders the breadcrumb using the explicit theme. `parts` MUST be a list.
  """
  @spec render(Theme.t(), [term()], keyword()) :: any()
  def render(%Theme{} = theme, parts, opts \\ []) when is_list(parts) do
    content = format(parts, opts)
    slot = breadcrumb_slot(theme)

    text(content,
      fg: Map.get(slot, :fg),
      bg: Map.get(slot, :bg),
      style: Map.get(slot, :style, [])
    )
  end

  defp normalize_parts(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp breadcrumb_slot(theme) do
    case theme.title do
      slot when slot in [nil, %{}] -> theme.status_bar
      slot -> slot
    end
  end
end

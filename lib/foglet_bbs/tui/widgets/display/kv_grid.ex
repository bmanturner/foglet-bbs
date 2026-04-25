defmodule Foglet.TUI.Widgets.Display.KvGrid do
  @moduledoc """
  Width-safe key/value grid for operator-console primitives.

  Honours:
    * D-02 — lives under the Display widget bucket as a primitive.
    * D-09 — renders caller-provided rows only, with no domain inference.
    * D-10 — uses `Foglet.TUI.TextWidth` for alignment and truncation.
    * D-11 — supports Account, Sysop, settings, runtime, and status rows.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Badge

  @default_width 80
  @default_label_width 16
  @default_gap 2

  @doc """
  Renders caller-provided key/value entries.

  Options:
    * `:theme` - required `%Foglet.TUI.Theme{}`
    * `:width` - maximum row width, defaults to 80
    * `:label_width` - label column width, defaults to 16
    * `:gap` - spaces between label and value, defaults to 2
  """
  @spec render([map() | keyword()], keyword()) :: any()
  def render(entries, opts) when is_list(entries) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = opts |> Keyword.get(:width, @default_width) |> normalize_width()
    label_width = opts |> Keyword.get(:label_width, @default_label_width) |> normalize_width()
    gap = opts |> Keyword.get(:gap, @default_gap) |> normalize_width()

    entries
    |> Enum.map(&render_entry(&1, theme, width, label_width, gap))
    |> Enum.intersperse(text("\n"))
  end

  defp render_entry(entry, %Theme{} = theme, width, label_width, gap) do
    entry = normalize_entry(entry)
    label = format_label(entry.label, label_width)
    gap_text = TextWidth.pad_trailing("", gap)
    badge = badge_for(entry, theme)
    badge_width = badge_width(entry)
    separator_width = if badge_width > 0, do: 1, else: 0

    value_width =
      width
      |> Kernel.-(label_width)
      |> Kernel.-(gap)
      |> Kernel.-(badge_width)
      |> Kernel.-(separator_width)
      |> max(0)

    value = TextWidth.truncate(entry.value, value_width)

    text(label <> gap_text <> value <> badge_separator(badge_width),
      fg: theme.dim.fg
    )
    |> append_badge(badge)
  end

  defp append_badge(prefix, nil), do: prefix
  defp append_badge(prefix, badge), do: [prefix, badge]

  defp format_label(label, label_width) do
    label
    |> TextWidth.truncate(label_width)
    |> TextWidth.pad_trailing(label_width)
  end

  defp badge_for(%{badge: state}, theme) when not is_nil(state),
    do: Badge.render(state, theme: theme)

  defp badge_for(%{state: state}, theme) when not is_nil(state),
    do: Badge.render(state, theme: theme)

  defp badge_for(_entry, _theme), do: nil

  defp badge_width(%{badge: state}) when not is_nil(state), do: badge_text_width(state)
  defp badge_width(%{state: state}) when not is_nil(state), do: badge_text_width(state)
  defp badge_width(_entry), do: 0

  defp badge_text_width(state), do: TextWidth.display_width("[#{state}]")

  defp badge_separator(0), do: ""
  defp badge_separator(_width), do: " "

  defp normalize_entry(entry) when is_map(entry) do
    %{
      label: Map.get(entry, :label, ""),
      value: Map.get(entry, :value, ""),
      badge: Map.get(entry, :badge),
      state: Map.get(entry, :state)
    }
  end

  defp normalize_entry(entry) when is_list(entry) do
    %{
      label: Keyword.get(entry, :label, ""),
      value: Keyword.get(entry, :value, ""),
      badge: Keyword.get(entry, :badge),
      state: Keyword.get(entry, :state)
    }
  end

  defp normalize_width(width) when is_integer(width), do: max(width, 0)
end

defmodule Foglet.TUI.Widgets.Composer.EditorFrame do
  @moduledoc """
  Shared stateless composer shell for Phase 23 (D-01, D-04, D-06, D-13, D-16).

  `EditorFrame` frames pre-rendered editor or preview children. It does not own
  input state, does not update `MultiLineInput`, and does not call domain
  contexts or submit paths. Screens remain responsible for key handling,
  validation, preview construction, and mutations.

  Honours:
    * D-01 — one shared composer widget boundary
    * D-04 — visible Edit/Preview segmented row inside the shell
    * D-06 — compact text-first character budget counters
    * D-13 — existing composer key behavior remains screen-owned
    * D-16 — stateless `render/1` helper only
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Theme

  @default_width 80
  @default_height 12
  @modes [:edit, :preview]

  @type mode :: :edit | :preview
  @type budget :: %{
          required(:label) => String.t(),
          required(:count) => non_neg_integer(),
          required(:limit) => pos_integer()
        }
  @type rendered_frame :: %{
          required(:type) => :box,
          required(:children) => list(),
          required(:title) => term(),
          required(:padding) => tuple(),
          required(:margin) => tuple(),
          required(:border) => term(),
          required(:fg) => term(),
          required(:bg) => term(),
          required(:size) => term(),
          required(:style) => term()
        }

  @doc """
  Renders a composer frame around already-rendered child content.

  Required options:

    * `:mode` — `:edit` or `:preview`
    * `:body` — rendered editor or preview child
    * `:theme` — `%Foglet.TUI.Theme{}`

  Optional options:

    * `:focused?` — controls frame color, defaults to `false`
    * `:context` — rendered context child or children
    * `:title` — rendered title child or children
    * `:budgets` — list of `%{label:, count:, limit:}` maps
    * `:error` — inline error string
    * `:width` / `:height` — shell sizing hints
  """
  @spec render(keyword()) :: rendered_frame()
  def render(opts) when is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    mode = Keyword.fetch!(opts, :mode)
    body = Keyword.fetch!(opts, :body)

    unless mode in @modes do
      raise ArgumentError, "unknown composer mode: #{inspect(mode)}"
    end

    focused? = Keyword.get(opts, :focused?, false)
    budgets = Keyword.get(opts, :budgets, [])
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    mappings = Presentation.theme_mappings().editor

    frame_slot =
      if focused?, do: slot(theme, mappings.focused), else: slot(theme, mappings.unfocused)

    rows =
      []
      |> append_node(render_header(mode, theme, mappings, frame_slot))
      |> append_optional(Keyword.get(opts, :context))
      |> append_optional(Keyword.get(opts, :title))
      |> append_node(render_body(body, theme, mappings))
      |> append_many(render_budgets(budgets, theme, mappings))
      |> append_optional(render_error(Keyword.get(opts, :error), theme, mappings))

    box style: %{border: :single, padding: 1, width: width, height: height, fg: frame_slot.fg} do
      column style: %{gap: 0} do
        rows
      end
    end
  end

  defp render_header(mode, theme, mappings, frame_slot) do
    row style: %{gap: 1} do
      [
        text("Composer", fg: frame_slot.fg),
        text("[", fg: frame_slot.fg),
        render_mode_label(:edit, mode, theme, mappings),
        text("|", fg: frame_slot.fg),
        render_mode_label(:preview, mode, theme, mappings),
        text("]", fg: frame_slot.fg)
      ]
    end
  end

  defp render_mode_label(label_mode, active_mode, theme, mappings) do
    label = label_mode |> Atom.to_string() |> String.capitalize()

    if label_mode == active_mode do
      text("▸ #{label}", fg: slot(theme, mappings.focused).fg)
    else
      text(label, fg: slot(theme, mappings.unfocused).fg)
    end
  end

  defp render_body(body, theme, mappings) do
    column style: %{gap: 0, fg: slot(theme, mappings.input).fg} do
      List.wrap(body)
    end
  end

  defp render_budgets(budgets, theme, mappings) do
    Enum.map(budgets, fn budget ->
      label = Map.fetch!(budget, :label)
      count = Map.fetch!(budget, :count)
      limit = Map.fetch!(budget, :limit)
      slot = counter_slot(count, limit, theme, mappings)

      text("#{label} #{count} / #{limit} chars", fg: slot.fg)
    end)
  end

  defp render_error(nil, _theme, _mappings), do: nil
  defp render_error("", _theme, _mappings), do: nil

  defp render_error(error, theme, mappings),
    do: text(error, fg: slot(theme, mappings.counter_error).fg)

  defp counter_slot(count, limit, theme, mappings) when count > limit,
    do: slot(theme, mappings.counter_error)

  defp counter_slot(count, limit, theme, mappings) when count / limit >= 0.8,
    do: slot(theme, mappings.counter_warning)

  defp counter_slot(_count, _limit, theme, mappings),
    do: slot(theme, mappings.counter)

  defp slot(%Theme{} = theme, slot_name), do: Map.fetch!(theme, slot_name)

  defp append_optional(rows, nil), do: rows
  defp append_optional(rows, []), do: rows
  defp append_optional(rows, node), do: append_node(rows, node)

  defp append_node(rows, nil), do: rows
  defp append_node(rows, nodes) when is_list(nodes), do: rows ++ nodes
  defp append_node(rows, node), do: rows ++ [node]

  defp append_many(rows, nodes), do: rows ++ nodes
end

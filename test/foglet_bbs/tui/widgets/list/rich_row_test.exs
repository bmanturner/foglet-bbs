defmodule Foglet.TUI.Widgets.List.RichRowTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [
      flatten_text: 1,
      assert_text_run: 3,
      color_atom_leaked?: 2,
      color_names: 0,
      text_runs: 1
    ]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.RichRow

  @cluster_width 4
  @metadata "@alice · 3 posts · 2h ago"

  setup do
    %{theme: Theme.default()}
  end

  describe "render/1 - selection x state x metadata matrix (RICHROW-01)" do
    test "unselected, no state, with metadata renders left-padded title and right-aligned metadata",
         %{theme: theme} do
      tree = render_row(theme, selected: false, state_cluster: [], title: "Plain")
      flat = flatten_text(tree)

      assert String.starts_with?(flat, "      Plain")
      assert String.ends_with?(flat, @metadata)
      assert TextWidth.display_width(flat) == 80
    end

    test "unselected, [:unread], with metadata applies emphasis and accent fg to title",
         %{theme: theme} do
      tree = render_row(theme, selected: false, state_cluster: [:unread], title: "Unread")

      assert flatten_text(tree) =~ "◆"
      assert_text_run(tree, "Unread", fg: theme.accent.fg, style: [:bold])
    end

    test "unselected, [:sticky], with metadata routes sticky glyph through theme.info.fg",
         %{theme: theme} do
      tree = render_row(theme, selected: false, state_cluster: [:sticky], title: "Sticky")

      assert_text_run(tree, "●", fg: theme.info.fg)
    end

    test "unselected, [:locked], with metadata routes locked glyph through theme.warning.fg",
         %{theme: theme} do
      tree = render_row(theme, selected: false, state_cluster: [:locked], title: "Locked")

      assert_text_run(tree, "⚿", fg: theme.warning.fg)
    end

    test "selected, no state, with metadata renders focus marker and selected style",
         %{theme: theme} do
      tree = render_row(theme, selected: true, state_cluster: [], title: "Selected")

      assert flatten_text(tree) |> String.starts_with?("▌ ")

      assert_text_run(tree, "Selected",
        fg: theme.selected.fg,
        bg: theme.selected.bg,
        style: [:bold]
      )
    end

    test "selected, [:unread], with metadata stacks selection bg over unread accent fg",
         %{theme: theme} do
      tree = render_row(theme, selected: true, state_cluster: [:unread], title: "Unread")

      assert_text_run(tree, "◆", fg: theme.accent.fg, bg: theme.selected.bg, style: [:bold])
    end

    test "selected, [:sticky, :locked], with metadata renders both glyphs in cluster",
         %{theme: theme} do
      tree = render_row(theme, selected: true, state_cluster: [:sticky, :locked], title: "Both")
      flat = flatten_text(tree)

      assert flat =~ "●"
      assert flat =~ "⚿"
    end

    test "unselected, no state, no metadata renders title without metadata text", %{theme: theme} do
      tree =
        RichRow.render(title: "No metadata", state_cluster: [], selected: false, theme: theme)

      refute metadata_run?(tree)
      assert flatten_text(tree) =~ "No metadata"
    end
  end

  describe "render/1 - focused-row uniqueness (THREADS-02)" do
    test "focused unread row has styling not shared by non-focused unread row", %{theme: theme} do
      selected = render_row(theme, selected: true, state_cluster: [:unread], title: "Unread")
      unselected = render_row(theme, selected: false, state_cluster: [:unread], title: "Unread")

      assert selected |> text_runs() |> Enum.any?(&(Map.get(&1, :bg) == theme.selected.bg))
      refute unselected |> text_runs() |> Enum.any?(&(Map.get(&1, :bg) == theme.selected.bg))
    end

    test "focused read row has styling not shared by non-focused read row", %{theme: theme} do
      selected = render_row(theme, selected: true, state_cluster: [], title: "Read")
      unselected = render_row(theme, selected: false, state_cluster: [], title: "Read")

      assert selected |> text_runs() |> Enum.any?(&(Map.get(&1, :bg) == theme.selected.bg))
      refute unselected |> text_runs() |> Enum.any?(&(Map.get(&1, :bg) == theme.selected.bg))
    end
  end

  describe "render/1 - cluster-width invariant" do
    test "cluster width stays fixed across known, empty, and unknown state atoms", %{theme: theme} do
      for states <- [
            [],
            [:unread],
            [:sticky],
            [:locked],
            [:unread, :sticky],
            [:unread, :locked],
            [:sticky, :locked],
            [:unread, :sticky, :locked],
            [:subscribed, :required]
          ] do
        cluster = rendered_cluster(theme, states)
        assert TextWidth.display_width(cluster) == @cluster_width
      end
    end

    test "generic state atoms render without domain coupling and keep cluster width", %{
      theme: theme
    } do
      empty = rendered_cluster(theme, [])
      generic = rendered_cluster(theme, [:subscribed, :required])

      assert TextWidth.display_width(generic) == TextWidth.display_width(empty)
      refute rendered_cluster(theme, [:subscribed, :required]) =~ "subscribed"
    end
  end

  describe "render/1 - width contract" do
    test "64-cell long title preserves cluster and metadata while truncating title", %{
      theme: theme
    } do
      tree =
        render_row(theme,
          title: String.duplicate("Long title ", 8),
          state_cluster: [:unread, :sticky, :locked],
          width: 64
        )

      flat = flatten_text(tree)
      assert flat =~ "◆●⚿ "
      assert flat =~ @metadata
      assert flat =~ "…"
      assert TextWidth.display_width(flat) <= 64
    end

    test "20-cell minimum title attempt is preserved when budget allows", %{theme: theme} do
      tree =
        render_row(theme,
          title: "12345678901234567890-extra",
          metadata: "@a",
          state_cluster: [],
          width: 30
        )

      flat = flatten_text(tree)
      assert flat =~ "1234567890123456789…"
      assert TextWidth.display_width(flat) <= 30
    end
  end

  describe "render/1 - theme-routing hygiene" do
    test "no hardcoded color atom leaks for selection, state, or metadata combinations", %{
      theme: theme
    } do
      for selected <- [true, false],
          states <- [[], [:unread], [:sticky], [:locked], [:unread, :sticky, :locked]],
          metadata <- [@metadata, "", nil] do
        serialized =
          theme
          |> render_row(selected: selected, state_cluster: states, metadata: metadata)
          |> inspect(printable_limit: :infinity, limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color), "leaked :#{color} atom"
        end
      end
    end
  end

  describe "render/1 - focus marker and glyph identity" do
    test "selected row begins with focus marker and unselected row begins with gutter", %{
      theme: theme
    } do
      assert theme |> render_row(selected: true) |> flatten_text() |> String.starts_with?("▌ ")
      assert theme |> render_row(selected: false) |> flatten_text() |> String.starts_with?("  ")
    end

    test "unread cluster contains diamond glyph", %{theme: theme} do
      assert rendered_cluster(theme, [:unread]) =~ "◆"
    end

    test "sticky cluster contains circle glyph", %{theme: theme} do
      assert rendered_cluster(theme, [:sticky]) =~ "●"
    end

    test "locked cluster contains lock glyph", %{theme: theme} do
      assert rendered_cluster(theme, [:locked]) =~ "⚿"
    end
  end

  describe "render/1 - selection versus state glyph precedence" do
    test "selected unread glyph keeps accent foreground over selected background", %{theme: theme} do
      tree = render_row(theme, selected: true, state_cluster: [:unread])

      assert_text_run(tree, "◆", fg: theme.accent.fg, bg: theme.selected.bg, style: [:bold])
    end

    test "selected sticky glyph keeps info foreground over selected background", %{theme: theme} do
      tree = render_row(theme, selected: true, state_cluster: [:sticky])

      assert_text_run(tree, "●", fg: theme.info.fg, bg: theme.selected.bg)
    end

    test "selected locked glyph keeps warning foreground over selected background", %{
      theme: theme
    } do
      tree = render_row(theme, selected: true, state_cluster: [:locked])

      assert_text_run(tree, "⚿", fg: theme.warning.fg, bg: theme.selected.bg)
    end
  end

  describe "render/1 - optional metadata" do
    test "omitting metadata renders without metadata text run", %{theme: theme} do
      tree = RichRow.render(title: "Plain", state_cluster: [], selected: false, theme: theme)

      refute metadata_run?(tree)
    end

    test "nil metadata is equivalent to omitting metadata", %{theme: theme} do
      omitted = RichRow.render(title: "Plain", state_cluster: [], selected: false, theme: theme)
      nil_metadata = render_row(theme, title: "Plain", metadata: nil, state_cluster: [])

      assert flatten_text(nil_metadata) == flatten_text(omitted)
      refute metadata_run?(nil_metadata)
    end

    test "empty metadata emits no metadata run or reserved metadata gap", %{theme: theme} do
      tree = render_row(theme, title: "Plain", metadata: "", state_cluster: [], width: 32)
      flat = flatten_text(tree)

      refute metadata_run?(tree)
      assert TextWidth.display_width(flat) == 32
      assert String.ends_with?(flat, " ")
    end
  end

  defp render_row(theme, opts) do
    opts =
      [
        title: Keyword.get(opts, :title, "Thread title"),
        metadata: Keyword.get(opts, :metadata, @metadata),
        state_cluster: Keyword.get(opts, :state_cluster, []),
        selected: Keyword.get(opts, :selected, false),
        theme: theme,
        width: Keyword.get(opts, :width, 80)
      ]

    RichRow.render(opts)
  end

  defp rendered_cluster(theme, states) do
    theme
    |> render_row(title: "Title", metadata: "", state_cluster: states, selected: false)
    |> flatten_text()
    |> String.slice(2, @cluster_width)
  end

  defp metadata_run?(tree) do
    tree
    |> text_runs()
    |> Enum.any?(fn run ->
      content = Map.get(run, :content) || Map.get(run, :text) || ""
      String.match?(content, ~r/@\w+/)
    end)
  end
end

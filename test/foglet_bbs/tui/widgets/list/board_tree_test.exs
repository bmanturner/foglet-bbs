defmodule Foglet.TUI.Widgets.List.BoardTreeTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [
      flatten_text: 1,
      text_runs: 1,
      color_atom_leaked?: 2,
      color_names: 0
    ]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.BoardTree

  @glyph_required "⚿"
  @glyph_subscribed "✓"
  @glyph_available "+"
  @glyph_unread "◆"
  @glyph_no_age "—"
  @glyph_category_expanded "▾"
  @glyph_category_collapsed "▸"

  setup do
    %{theme: Theme.default()}
  end

  # Timestamps are built at runtime so wall-clock drift between compile and
  # execution does not flip minute magnitudes on slower CI runs.
  defp ten_min_ago, do: DateTime.add(DateTime.utc_now(), -600, :second)
  defp two_hours_ago, do: DateTime.add(DateTime.utc_now(), -7_200, :second)
  defp three_days_ago, do: DateTime.add(DateTime.utc_now(), -86_400 * 3, :second)
  defp five_min_ago, do: DateTime.add(DateTime.utc_now(), -300, :second)

  defp directory_with_one_board(board_attrs, category_name \\ "Public") do
    defaults = %{
      board: %{id: "b1", name: "general", slug: "general"},
      subscribed?: true,
      required_subscription?: false,
      unread_count: 3,
      last_post_at: ten_min_ago()
    }

    [
      %{
        category: %{id: "c1", name: category_name},
        boards: [Map.merge(defaults, board_attrs)]
      }
    ]
  end

  defp large_directory(count \\ 24) do
    boards =
      for index <- 1..count do
        %{
          board: %{
            id: "b#{index}",
            name: "Board #{String.pad_leading(Integer.to_string(index), 2, "0")}",
            slug: "board-#{index}"
          },
          subscribed?: true,
          required_subscription?: false,
          unread_count: rem(index, 4),
          last_post_at: ten_min_ago()
        }
      end

    [%{category: %{id: "c-large", name: "Large"}, boards: boards}]
  end

  defp render_text(state, theme, opts \\ []) do
    BoardTree.render(state, [theme: theme] ++ opts) |> flatten_text()
  end

  # Returns one flattened-text string per rendered row. The BoardTree column
  # has no in-band row separators (rows are separated by layout, not text), so
  # tests that need per-row inspection walk the column's children directly.
  defp render_rows(state, theme, opts \\ []) do
    BoardTree.render(state, [theme: theme] ++ opts)
    |> Map.get(:children, [])
    |> Enum.map(&flatten_text/1)
  end

  describe "init/1 - public contract" do
    test "accepts :directory and returns a struct ready for render", %{theme: theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-init")

      assert is_struct(state)
      tree = BoardTree.render(state, theme: theme)
      assert flatten_text(tree) != ""
    end

    test "raises when :directory is missing" do
      assert_raise KeyError, fn ->
        BoardTree.init(id: "bt-missing")
      end
    end
  end

  describe "focused_board_entry/1 - public encapsulation API (D-13)" do
    test "returns nil before any navigation when cursor is on a category", %{theme: _theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-focus-cat")

      assert BoardTree.focused_board_entry(state) == nil
    end

    test "returns the focused board entry map after navigating onto a board row",
         %{theme: _theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-focus-board")
      {state, _action} = BoardTree.handle_event(%{key: :down}, state)

      entry = BoardTree.focused_board_entry(state)
      assert is_map(entry)
      assert entry.board.id == "b1"
      assert entry.subscribed? == true
      refute Map.has_key?(entry, :kind)
    end

    test "returns nil when the cursor is on a category", %{theme: _theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-focus-cat-explicit")

      assert BoardTree.focused_board_entry(state) == nil
    end
  end

  describe "render/2 - category rows (BOARDS-01)" do
    test "expanded category row contains ▾ glyph and category name", %{theme: theme} do
      dir = directory_with_one_board(%{}, "Town Square")
      state = BoardTree.init(directory: dir, id: "bt-cat-expanded")

      text = render_text(state, theme)

      assert text =~ @glyph_category_expanded
      assert text =~ "Town Square"
    end

    test "collapsed category row contains ▸ glyph and hides board children", %{theme: theme} do
      dir = directory_with_one_board(%{}, "Town Square")
      state = BoardTree.init(directory: dir, id: "bt-cat-collapsed")
      {state, _action} = BoardTree.handle_event(%{key: :left}, state)

      text = render_text(state, theme)

      assert text =~ @glyph_category_collapsed
      assert text =~ "Town Square"
      refute text =~ "general"
    end

    test "category rows do not contain subscription glyphs or age column", %{theme: theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-cat-clean")

      cat_line =
        state
        |> render_rows(theme)
        |> Enum.find(&String.contains?(&1, @glyph_category_expanded))

      assert cat_line, "expected a category row in render output"
      refute cat_line =~ @glyph_required
      refute cat_line =~ @glyph_subscribed
      refute cat_line =~ @glyph_available
      refute cat_line =~ @glyph_no_age
    end

    test "category row with very long name fits within width and truncates with …",
         %{theme: theme} do
      long = String.duplicate("a", 80)
      dir = directory_with_one_board(%{}, long)
      state = BoardTree.init(directory: dir, id: "bt-cat-trunc")

      cat_line =
        state
        |> render_rows(theme, width: 60)
        |> Enum.find(&String.contains?(&1, @glyph_category_expanded))

      assert cat_line, "expected a category line in render output"

      assert TextWidth.display_width(cat_line) <= 60,
             "category line exceeded 60 cells: #{inspect(cat_line)}"

      assert cat_line =~ "…",
             "expected category long-name truncation marker in #{inspect(cat_line)}"
    end
  end

  describe "render/2 - title carries indented name only (NO glyph prefix) (BOARDS-02)" do
    test "required board: title text run starts with the board name (no `⚿ ` prefix)",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          board: %{id: "b1", name: "announcements", slug: "announcements"},
          subscribed?: true,
          required_subscription?: true
        })

      state = BoardTree.init(directory: dir, id: "bt-required-title")
      tree = BoardTree.render(state, theme: theme, width: 60)
      text = flatten_text(tree)

      assert text =~ @glyph_required, "expected ⚿ in cluster, got: #{inspect(text)}"
      assert text =~ "announcements"

      refute text =~ "⚿ announcements",
             "subscription glyph must NOT prefix the title; it rides in :state_cluster"
    end

    test "subscribed (non-required) board: title is the name only", %{theme: theme} do
      dir =
        directory_with_one_board(%{
          board: %{id: "b1", name: "general", slug: "general"},
          subscribed?: true,
          required_subscription?: false
        })

      state = BoardTree.init(directory: dir, id: "bt-subscribed-title")
      text = render_text(state, theme, width: 60)

      assert text =~ @glyph_subscribed
      assert text =~ "general"
      refute text =~ "✓ general"
    end

    test "unsubscribed board: title is the name only", %{theme: theme} do
      dir =
        directory_with_one_board(%{
          board: %{id: "b1", name: "tech", slug: "tech"},
          subscribed?: false,
          required_subscription?: false,
          unread_count: nil
        })

      state = BoardTree.init(directory: dir, id: "bt-available-title")
      text = render_text(state, theme, width: 60)

      assert text =~ @glyph_available
      assert text =~ "tech"
      refute text =~ "+ tech"
    end

    test "no board row contains literal subscription-state words (required/subscribed/subscribe)",
         %{theme: theme} do
      dir = [
        %{
          category: %{id: "c1", name: "Public"},
          boards: [
            %{
              board: %{id: "b1", name: "general", slug: "general"},
              subscribed?: true,
              required_subscription?: false,
              unread_count: 3,
              last_post_at: ten_min_ago()
            },
            %{
              board: %{id: "b2", name: "tech", slug: "tech"},
              subscribed?: false,
              required_subscription?: false,
              unread_count: nil,
              last_post_at: nil
            },
            %{
              board: %{id: "b3", name: "rules", slug: "rules"},
              subscribed?: true,
              required_subscription?: true,
              unread_count: 0,
              last_post_at: two_hours_ago()
            }
          ]
        }
      ]

      state = BoardTree.init(directory: dir, id: "bt-no-text-labels")
      text = render_text(state, theme, width: 80)

      refute text =~ ~r/\brequired\b/i
      refute text =~ ~r/\bsubscribed\b/i
      refute text =~ ~r/\bsubscribe\b/i
      refute text =~ "[required]"
      refute text =~ "[subscribed]"
      refute text =~ "[unsubscribed]"
    end
  end

  describe "render/2 - read-state cluster cell (BOARDS-02)" do
    test "unread board (unread_count >= 1) row contains ◆ in cluster", %{theme: theme} do
      dir = directory_with_one_board(%{unread_count: 5})
      state = BoardTree.init(directory: dir, id: "bt-unread")
      text = render_text(state, theme, width: 60)

      assert text =~ @glyph_unread
    end

    test "read board (unread_count == 0) row does NOT contain ◆ in cluster", %{theme: theme} do
      dir = directory_with_one_board(%{unread_count: 0})
      state = BoardTree.init(directory: dir, id: "bt-read")
      text = render_text(state, theme, width: 60)

      refute text =~ @glyph_unread
    end

    test "unsubscribed board (unread_count == nil) row does NOT contain ◆", %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: false,
          required_subscription?: false,
          unread_count: nil
        })

      state = BoardTree.init(directory: dir, id: "bt-unsub-unread")
      text = render_text(state, theme, width: 60)

      refute text =~ @glyph_unread
    end

    test "no board row contains the `◇` glyph (read board = whitespace cluster slot)",
         %{theme: theme} do
      dir = [
        %{
          category: %{id: "c1", name: "Public"},
          boards: [
            %{
              board: %{id: "b1", name: "general", slug: "general"},
              subscribed?: true,
              required_subscription?: false,
              unread_count: 3,
              last_post_at: ten_min_ago()
            },
            %{
              board: %{id: "b2", name: "tech", slug: "tech"},
              subscribed?: false,
              required_subscription?: false,
              unread_count: nil,
              last_post_at: nil
            },
            %{
              board: %{id: "b3", name: "rules", slug: "rules"},
              subscribed?: true,
              required_subscription?: true,
              unread_count: 0,
              last_post_at: two_hours_ago()
            }
          ]
        }
      ]

      state = BoardTree.init(directory: dir, id: "bt-no-diamond")
      text = render_text(state, theme, width: 80)

      refute text =~ "◇", "no row should render the ◇ glyph; expected whitespace slot"
    end
  end

  describe "render/2 - subscription cluster cell + theme routing (BOARDS-02, D-10b)" do
    test "required row routes ⚿ glyph through theme.warning.fg",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: true,
          required_subscription?: true,
          unread_count: 0,
          last_post_at: two_hours_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-warning-route")
      tree = BoardTree.render(state, theme: theme, width: 80)
      runs = text_runs(tree)

      run = Enum.find(runs, fn run -> String.contains?(run_text(run), @glyph_required) end)
      assert run, "expected a text run containing ⚿ in #{inspect(Enum.map(runs, &run_text/1))}"

      assert run_fg(run) == theme.warning.fg,
             "expected ⚿ run fg=theme.warning.fg, got #{inspect(run_fg(run))}"
    end

    test "subscribed (non-required) row routes ✓ glyph through theme.info.fg",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: true,
          required_subscription?: false,
          unread_count: 0,
          last_post_at: ten_min_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-info-route")
      tree = BoardTree.render(state, theme: theme, width: 80)
      runs = text_runs(tree)

      run = Enum.find(runs, fn run -> String.contains?(run_text(run), @glyph_subscribed) end)
      assert run, "expected a text run containing ✓"

      assert run_fg(run) == theme.info.fg,
             "expected ✓ run fg=theme.info.fg, got #{inspect(run_fg(run))}"
    end

    test "available (unsubscribed) row routes + glyph through theme.dim.fg",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: false,
          required_subscription?: false,
          unread_count: nil,
          last_post_at: nil
        })

      state = BoardTree.init(directory: dir, id: "bt-dim-route")
      tree = BoardTree.render(state, theme: theme, width: 80)
      runs = text_runs(tree)

      run = Enum.find(runs, fn run -> String.contains?(run_text(run), @glyph_available) end)
      assert run, "expected a text run containing +"

      assert run_fg(run) == theme.dim.fg,
             "expected + run fg=theme.dim.fg, got #{inspect(run_fg(run))}"
    end
  end

  describe "render/2 - metadata column composition (BOARDS-02)" do
    test "unread_count >= 1 metadata reads `N unread  AGE` (regex magnitude)",
         %{theme: theme} do
      dir = directory_with_one_board(%{unread_count: 3, last_post_at: ten_min_ago()})

      state = BoardTree.init(directory: dir, id: "bt-meta-unread")
      text = render_text(state, theme, width: 80)

      assert text =~ "3 unread"
      assert text =~ ~r/\d+m\b/, "expected an `Nm` magnitude in #{inspect(text)}"
    end

    test "unread_count == 0 metadata reads `all read  AGE` (regex magnitude)",
         %{theme: theme} do
      dir = directory_with_one_board(%{unread_count: 0, last_post_at: two_hours_ago()})

      state = BoardTree.init(directory: dir, id: "bt-meta-read")
      text = render_text(state, theme, width: 80)

      assert text =~ "all read"
      assert text =~ ~r/\d+h\b/, "expected an `Nh` magnitude in #{inspect(text)}"
    end

    test "unread_count == nil metadata is age-only (regex magnitude)",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: false,
          unread_count: nil,
          last_post_at: three_days_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-meta-age-only")
      text = render_text(state, theme, width: 80)

      assert text =~ ~r/\d+d\b/, "expected an `Nd` magnitude in #{inspect(text)}"
      refute text =~ "unread"
      refute text =~ "all read"
    end

    test "last_post_at == nil renders `—` (em-dash) in metadata, not `?`",
         %{theme: theme} do
      dir = directory_with_one_board(%{unread_count: 0, last_post_at: nil})

      state = BoardTree.init(directory: dir, id: "bt-meta-no-age")
      text = render_text(state, theme, width: 80)

      assert text =~ @glyph_no_age
      refute text =~ "?"
    end
  end

  describe "render/2 - width contract at 64-cell content (BOARDS-02 priority)" do
    @long_name "this-is-a-very-long-board-name-that-must-truncate"

    test "at width 60, all four trailing elements render fully; only name truncates",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          board: %{id: "b1", name: @long_name, slug: "long"},
          subscribed?: true,
          required_subscription?: true,
          unread_count: 7,
          last_post_at: ten_min_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-truncate")
      rows = render_rows(state, theme, width: 60)
      text = Enum.join(rows, "\n")

      assert text =~ @glyph_required
      assert text =~ @glyph_unread
      assert text =~ "7 unread"
      assert text =~ ~r/\d+m\b/
      assert text =~ "…"

      for line <- rows, line != "" do
        assert TextWidth.display_width(line) <= 60,
               "line exceeded 60 cells: #{inspect(line)} (width=#{TextWidth.display_width(line)})"
      end
    end

    test "at width 60 with short name, name renders without truncation",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          board: %{id: "b1", name: "short", slug: "short"},
          subscribed?: true,
          required_subscription?: false,
          unread_count: 1,
          last_post_at: five_min_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-noTrunc")
      text = render_text(state, theme, width: 60)

      assert text =~ @glyph_subscribed
      assert text =~ "short"
      refute text =~ "shor…"
    end
  end

  describe "render/2 - RichRow integration boundary (BOARDS-01)" do
    test "RichRow :state_cluster carries read-state + subscription-state cells (no atom leakage)",
         %{theme: theme} do
      dir =
        directory_with_one_board(%{
          subscribed?: true,
          required_subscription?: true,
          unread_count: 0,
          last_post_at: ten_min_ago()
        })

      state = BoardTree.init(directory: dir, id: "bt-cluster-roles")
      text = render_text(state, theme, width: 80)

      assert text =~ @glyph_required
      refute text =~ @glyph_unread
      refute text =~ "⚿ general"
    end
  end

  describe "selection treatment" do
    test "render/2 reflects cursor position via RichRow's focus marker",
         %{theme: theme} do
      dir = directory_with_one_board(%{})
      state = BoardTree.init(directory: dir, id: "bt-cursor")
      {state, _action} = BoardTree.handle_event(%{key: :down}, state)
      text = render_text(state, theme, width: 80)

      assert text =~ "▌ "
    end
  end

  describe "render/2 - visible_height windowing" do
    test "limits large visible trees to the requested rendered row count", %{theme: theme} do
      state = BoardTree.init(directory: large_directory(), id: "bt-visible-height")

      text = render_text(state, theme, width: 60, visible_height: 8)

      rendered_rows = String.split(text, "\n", trim: true)
      assert length(rendered_rows) <= 8
      assert text =~ "Large"
    end

    test "keeps the focused board visible after cursor moves below the initial window",
         %{theme: theme} do
      state = BoardTree.init(directory: large_directory(), id: "bt-visible-focused")

      state =
        Enum.reduce(1..15, state, fn _index, acc ->
          {next, _action} = BoardTree.handle_event(%{key: :down}, acc)
          next
        end)

      text = render_text(state, theme, width: 60, visible_height: 8)

      assert length(String.split(text, "\n", trim: true)) <= 8
      assert text =~ "Board 15"
      refute text =~ "Board 01"
    end
  end

  describe "theme-routing hygiene (BOARDS-01)" do
    test "BoardTree source contains no hardcoded color atoms", %{theme: _theme} do
      source = File.read!("lib/foglet_bbs/tui/widgets/list/board_tree.ex")

      for color <- color_names() do
        refute color_atom_leaked?(source, color),
               "color atom :#{color} leaked into BoardTree source"
      end
    end
  end

  defp run_text(%{content: content}) when is_binary(content), do: content
  defp run_text(%{text: text}) when is_binary(text), do: text
  defp run_text(_run), do: ""

  defp run_fg(%{style: %{fg: fg}}), do: fg
  defp run_fg(%{fg: fg}), do: fg
  defp run_fg(_run), do: nil
end

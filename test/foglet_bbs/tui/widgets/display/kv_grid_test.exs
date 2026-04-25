defmodule Foglet.TUI.Widgets.Display.KvGridTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [color_atom_leaked?: 2, color_names: 0, flatten_text: 1]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.KvGrid

  setup do
    %{theme: Theme.default()}
  end

  describe "render/2 fixture coverage (D-11)" do
    test "renders account profile rows at 64 and 80 columns", %{theme: theme} do
      assert_width_safe(account_profile_rows(), theme, ["Location", "Tagline", "Real name"])
    end

    test "renders account preference rows at 64 and 80 columns", %{theme: theme} do
      assert_width_safe(account_prefs_rows(), theme, ["Timezone", "Time format", "Theme"])
    end

    test "renders sysop system rows at 64 and 80 columns", %{theme: theme} do
      assert_width_safe(sysop_system_rows(), theme, ["Version", "Uptime", "Sessions"])
    end

    test "renders site setting rows at 64 and 80 columns", %{theme: theme} do
      assert_width_safe(site_setting_rows(), theme, ["Registration"])
    end

    test "renders runtime limit rows at 64 and 80 columns", %{theme: theme} do
      assert_width_safe(runtime_limit_rows(), theme, ["Title limit"])
    end
  end

  describe "render/2 status badge metadata" do
    test "renders state and badge text through Display.Badge", %{theme: theme} do
      for width <- [64, 80] do
        tree = KvGrid.render(status_summary_rows(), theme: theme, width: width)
        flat = flatten_text(tree)

        assert flat =~ "Health"
        assert flat =~ "healthy"
        assert flat =~ "pending"
        assert TextWidth.display_width(flat) <= width * length(status_summary_rows())
      end
    end

    test "renders structured badge metadata without leaking inspected maps", %{theme: theme} do
      rows = [
        %{
          label: "Review",
          value: "requires action",
          badge: %{state: :pending, label: "queued", role: :warning}
        }
      ]

      tree = KvGrid.render(rows, theme: theme, width: 64)
      flat = flatten_text(tree)

      assert flat =~ "Review"
      assert flat =~ "queued"
      refute flat =~ "%{"

      for line <- text_lines(tree) do
        assert TextWidth.display_width(line) <= 64
      end
    end
  end

  describe "render/2 theme hygiene" do
    test "does not leak hardcoded terminal color atoms", %{theme: theme} do
      serialized =
        status_summary_rows()
        |> KvGrid.render(theme: theme, width: 64)
        |> inspect(printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "leaked :#{color} atom"
      end
    end
  end

  defp assert_width_safe(rows, theme, expected_labels) do
    for width <- [64, 80] do
      tree = KvGrid.render(rows, theme: theme, width: width)
      flat = flatten_text(tree)

      for label <- expected_labels do
        assert flat =~ label
      end

      for line <- text_lines(tree) do
        assert TextWidth.display_width(line) <= width
      end
    end
  end

  defp text_lines(tree) do
    tree
    |> flatten_text()
    |> String.split("\n", trim: true)
  end

  defp account_profile_rows do
    [
      %{label: "Location", value: "New Orleans"},
      %{label: "Tagline", value: "Building weird small internet"},
      %{label: "Real name", value: "Brendan Turner"}
    ]
  end

  defp account_prefs_rows do
    [
      %{label: "Timezone", value: "America/Chicago"},
      %{label: "Time format", value: "12h"},
      %{label: "Theme", value: "amber"}
    ]
  end

  defp sysop_system_rows do
    [
      %{label: "Version", value: "1.3.0-pre"},
      %{label: "Uptime", value: "03:14:15"},
      %{label: "Sessions", value: "7"},
      %{label: "Active boards", value: "12"},
      %{label: "OTP processes", value: "482"},
      %{label: "DB pool size", value: "10"}
    ]
  end

  defp site_setting_rows do
    [
      %{label: "Registration", value: "invite-only"},
      %{label: "Invite policy", value: "sysops and moderators"},
      %{label: "Board creation", value: "sysop approval"}
    ]
  end

  defp runtime_limit_rows do
    [
      %{label: "Title limit", value: "120 chars"},
      %{label: "Post limit", value: "12_000 chars"},
      %{label: "Upload limit", value: "disabled"}
    ]
  end

  defp status_summary_rows do
    [
      %{label: "Health", value: "database reachable", state: :healthy},
      %{label: "Pending users", value: "3 awaiting approval", badge: :pending},
      %{label: "SSH daemon", value: "listening on 2222", state: :healthy}
    ]
  end
end

defmodule Foglet.TUI.Widgets.Chrome.StatusBarTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.Chrome.{ClockFormatter, StatusBar}

  defp user(attrs) do
    struct!(
      User,
      Keyword.merge(
        [
          id: "u1",
          handle: "alice",
          role: :user,
          timezone: "Etc/UTC",
          preferences: %{"time_format" => "12h"}
        ],
        attrs
      )
    )
  end

  describe "ClockFormatter.format/2" do
    test "renders fixed instants in the user's timezone with 24-hour time" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 18:05:00Z],
          user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
        )

      assert text == "13:05"
      refute text =~ "AM"
      refute text =~ "PM"
    end

    test "renders fixed instants in 12-hour time when requested" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: "Etc/UTC", preferences: %{"time_format" => "12h"})
        )

      assert text == "12:05 AM"
    end

    test "falls back to UTC and 12-hour time for invalid preferences" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: "Not/AZone", preferences: %{"time_format" => "weird"})
        )

      assert text == "12:05 AM"
    end

    test "falls back to UTC and 12-hour time for missing preferences" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: nil, preferences: %{})
        )

      assert text == "12:05 AM"
    end
  end

  describe "StatusBar.status_atoms/1" do
    test "BBS mode includes handle, positive unread, activity, and clock" do
      state = %{
        current_screen: :main_menu,
        unread_count: 3,
        activity_label: "fresh posts",
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      assert StatusBar.status_atoms(state) == ["@alice", "unread 3", "fresh posts", "13:05"]
    end

    test "BBS mode omits absent or non-positive optional atoms" do
      state = %{
        current_screen: :board_list,
        unread_count: 0,
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      assert StatusBar.status_atoms(state) == ["@alice", "13:05"]
    end

    test "operator mode includes only present operator atoms and clock" do
      state = %{
        current_screen: :account,
        operator_scope: "site",
        system_status: "mail degraded",
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      assert StatusBar.status_atoms(state) == ["@alice", "scope site", "mail degraded", "13:05"]
    end

    test "guest state renders only the clock and without fabricated optional atoms" do
      state = %{
        current_screen: :account,
        unread_count: 9,
        operator_scope: "site",
        system_status: "mail degraded",
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]}
      }

      assert StatusBar.status_atoms(state) == ["06:05 PM"]
    end

    test "uses Presentation.mode_for! with current_screen" do
      assert_raise ArgumentError, ~r/unknown TUI screen/, fn ->
        StatusBar.status_atoms(%{current_screen: :not_a_screen})
      end
    end
  end

  describe "StatusBar.render/3" do
    test "accepts breadcrumb parts while preserving status atoms" do
      state = %{
        current_screen: :main_menu,
        unread_count: 3,
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      texts = StatusBar.render(state, ["Foglet", "Home"], width: 80) |> collect_text_values()
      rendered = Enum.join(texts, " ")

      assert rendered =~ "Foglet ▸ Home"
      assert rendered =~ "@alice | unread 3 | 13:05"
    end
  end
end

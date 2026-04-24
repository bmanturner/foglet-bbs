defmodule Foglet.TUI.Widgets.Chrome.StatusBarTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.Chrome.{ClockFormatter, StatusBar}

  defp user(attrs \\ []) do
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

      assert text =~ "2026-04-24"
      assert text =~ "13:05"
      refute text =~ "AM"
      refute text =~ "PM"
    end

    test "renders fixed instants in 12-hour time when requested" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: "Etc/UTC", preferences: %{"time_format" => "12h"})
        )

      assert text =~ "2026-04-24"
      assert text =~ "12:05"
      assert text =~ "AM"
    end

    test "falls back to UTC and 12-hour time for invalid preferences" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: "Not/AZone", preferences: %{"time_format" => "weird"})
        )

      assert text =~ "2026-04-24"
      assert text =~ "12:05"
      assert text =~ "AM"
    end

    test "falls back to UTC and 12-hour time for missing preferences" do
      text =
        ClockFormatter.format(
          ~U[2026-04-24 00:05:00Z],
          user(timezone: nil, preferences: %{})
        )

      assert text =~ "2026-04-24"
      assert text =~ "12:05"
      assert text =~ "AM"
    end
  end

  describe "StatusBar.render/2" do
    test "main menu includes fixed clock text and handle" do
      state = %{
        current_screen: :main_menu,
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      texts = StatusBar.render(state, "Main Menu") |> collect_text_values()
      rendered = Enum.join(texts, " ")

      assert rendered =~ "2026-04-24"
      assert rendered =~ "13:05"
      assert rendered =~ "@alice"
    end

    test "non-main-menu screens keep handle-only status text" do
      state = %{
        current_screen: :board_list,
        session_context: %{clock_now: ~U[2026-04-24 18:05:00Z]},
        current_user: user(timezone: "America/Chicago", preferences: %{"time_format" => "24h"})
      }

      texts = StatusBar.render(state, "Boards") |> collect_text_values()

      assert "@alice " in texts
      rendered = Enum.join(texts, " ")
      refute rendered =~ "2026-04-24"
      refute rendered =~ "13:05"
    end
  end
end

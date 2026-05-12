defmodule Foglet.TUI.Widgets.Chrome.ScreenFrameTest do
  use ExUnit.Case, async: false

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Raxol.UI.Layout.Engine

  @fixed_clock ~U[2026-04-24 18:05:00Z]

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Map.merge(
      %{
        current_screen: :board_list,
        current_user: %{
          id: "u1",
          handle: "alice",
          timezone: "America/Chicago",
          preferences: %{"time_format" => "24h"}
        },
        terminal_size: {80, 24},
        session_context: %{clock_now: @fixed_clock},
        unread_notifications_count: 0
      },
      attrs
    )
  end

  defp content do
    text("BODY SENTINEL")
  end

  describe "render/4" do
    test "uses the configured public app name for fallback breadcrumbs" do
      original = Application.get_env(:foglet_bbs, :app_name)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:foglet_bbs, :app_name)
          value -> Application.put_env(:foglet_bbs, :app_name, value)
        end
      end)

      Application.put_env(:foglet_bbs, :app_name, "Foglet BBS")

      texts =
        state()
        |> ScreenFrame.render(%{}, content(), [])
        |> apply_layout()
        |> collect_positioned_text_elements()

      rows = text_rows(texts)
      top_border = Map.fetch!(rows, 0)

      assert top_border =~ "Foglet BBS"
      refute top_border =~ "Foglet ▸"
    end

    test "renders Chrome V2 breadcrumb, status atoms, and command groups" do
      # Phase 39 R3 / D-12: callers supply breadcrumb_parts explicitly via
      # the chrome map. Legacy title strings no longer derive breadcrumb
      # segments — they fall back to the configured public app name.
      chrome = %{breadcrumb_parts: ["Foglet", "Boards"]}

      texts =
        state()
        |> ScreenFrame.render(chrome, content(), [
          %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}
        ])
        |> apply_layout()
        |> collect_positioned_text_elements()

      rendered = Enum.map_join(texts, " ", & &1.text)
      rows = text_rows(texts)
      top_border = Map.fetch!(rows, 0)
      bottom_border = Map.fetch!(rows, 23)
      side_borders = Enum.filter(texts, &(&1.text == "│"))
      assert rendered =~ "Foglet"
      assert rendered =~ "Foglet ▸ Boards"
      assert rendered =~ "@alice | 13:05"
      refute rendered =~ "System"
      assert rendered =~ "Q"
      assert rendered =~ "Back"
      assert top_border =~ "Foglet ▸ Boards"
      assert top_border =~ "@alice | 13:05"
      assert String.ends_with?(top_border, "┐")
      refute bottom_border =~ "System"
      assert bottom_border =~ "Q Back"
      assert String.ends_with?(bottom_border, "┘")
      assert length(side_borders) == 44

      breadcrumb = Enum.find(texts, &(&1.text == "Foglet ▸ Boards"))
      status = Enum.find(texts, &(&1.text == "@alice | 13:05"))
      command_key = Enum.find(texts, &(&1.text == "Q"))

      assert breadcrumb.fg
      assert status.fg
      assert command_key.fg
    end

    test "keeps caller content between top border chrome and bottom border commands" do
      texts =
        state()
        |> ScreenFrame.render(
          %{breadcrumb_parts: ["Foglet", "Boards"]},
          content(),
          [%{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}]
        )
        |> apply_layout()
        |> collect_positioned_text_elements()

      top_index = Enum.find_index(texts, &String.starts_with?(&1.text, "┌"))
      content_index = Enum.find_index(texts, &String.contains?(&1.text, "BODY SENTINEL"))
      command_index = Enum.find_index(texts, &String.starts_with?(&1.text, "└"))
      content = Enum.find(texts, &String.contains?(&1.text, "BODY SENTINEL"))

      assert top_index
      assert content_index
      assert command_index
      assert top_index < content_index
      assert content_index < command_index
      assert content.x > 0
      assert content.x + String.length(content.text) < 80
    end

    test "renders notification token only for positive authenticated counts" do
      zero_top =
        state(unread_notifications_count: 0)
        |> render_top_border(width: 80)

      one_top =
        state(unread_notifications_count: 1)
        |> render_top_border(width: 80)

      many_top =
        state(unread_notifications_count: 12)
        |> render_top_border(width: 80)

      guest_top =
        state(current_user: nil, unread_notifications_count: 12)
        |> render_top_border(width: 80)

      refute zero_top =~ "N 0"
      refute zero_top =~ "N "
      assert one_top =~ "@alice | N 1 | 13:05"
      assert many_top =~ "@alice | N 12 | 13:05"
      refute guest_top =~ "N 12"
    end

    test "preserves handle, notification token, and clock at the 64-column breakpoint" do
      top_border =
        state(terminal_size: {64, 22}, unread_notifications_count: 12)
        |> render_top_border(width: 64, height: 22)

      assert String.ends_with?(top_border, "┐")
      assert top_border =~ "@alice | N 12 | 13:05"
      assert String.length(top_border) <= 64
    end
  end

  defp apply_layout(tree, width \\ 80, height \\ 24),
    do: Engine.apply_layout(tree, %{width: width, height: height})

  defp collect_positioned_text_elements(positioned) do
    positioned
    |> List.flatten()
    |> Enum.filter(&(&1.type == :text))
    |> Enum.sort_by(&{&1.y, &1.x})
  end

  defp render_top_border(state, opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.get(opts, :height, 24)

    state
    |> ScreenFrame.render(
      %{breadcrumb_parts: ["Foglet", "Boards", "Thread Archive"]},
      content(),
      []
    )
    |> apply_layout(width, height)
    |> collect_positioned_text_elements()
    |> text_rows()
    |> Map.fetch!(0)
  end

  defp text_rows(elements) do
    elements
    |> Enum.group_by(& &1.y)
    |> Map.new(fn {y, row_elements} ->
      row_text =
        row_elements
        |> Enum.sort_by(& &1.x)
        |> Enum.map_join(& &1.text)

      {y, row_text}
    end)
  end
end

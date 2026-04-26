defmodule Foglet.TUI.Widgets.Chrome.ScreenFrameTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers
  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  @fixed_clock ~U[2026-04-24 18:05:00Z]

  defp state do
    %{
      current_screen: :board_list,
      current_user: %{
        id: "u1",
        handle: "alice",
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"}
      },
      terminal_size: {80, 24},
      session_context: %{clock_now: @fixed_clock}
    }
  end

  defp content do
    text("BODY SENTINEL")
  end

  describe "render/4" do
    test "renders Chrome V2 breadcrumb, status atoms, and command groups" do
      texts =
        state()
        |> ScreenFrame.render("Boards", content(), [{"Q", "Back"}])
        |> collect_text_values()

      rendered = Enum.join(texts, " ")
      top_border = Enum.find(texts, &String.starts_with?(&1, "┌"))
      bottom_border = Enum.find(texts, &String.starts_with?(&1, "└"))

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
    end

    test "keeps caller content between top border chrome and bottom border commands" do
      texts =
        state()
        |> ScreenFrame.render("Boards", content(), [{"Q", "Back"}])
        |> collect_text_values()

      top_index = Enum.find_index(texts, &String.starts_with?(&1, "┌"))
      content_index = Enum.find_index(texts, &String.contains?(&1, "BODY SENTINEL"))
      command_index = Enum.find_index(texts, &String.starts_with?(&1, "└"))

      assert top_index
      assert content_index
      assert command_index
      assert top_index < content_index
      assert content_index < command_index
    end
  end
end

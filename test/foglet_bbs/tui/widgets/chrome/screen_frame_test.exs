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

      assert rendered =~ "BODY SENTINEL"
      assert rendered =~ "System"
      assert rendered =~ "Q"
      assert rendered =~ "Back"
    end

    test "keeps caller content between top chrome and command chrome" do
      texts =
        state()
        |> ScreenFrame.render("Boards", content(), [{"Q", "Back"}])
        |> collect_text_values()

      content_index = Enum.find_index(texts, &String.contains?(&1, "BODY SENTINEL"))
      command_index = Enum.find_index(texts, &String.contains?(&1, "System"))

      assert content_index
      assert command_index
      assert content_index < command_index
    end
  end
end

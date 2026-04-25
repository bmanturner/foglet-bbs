defmodule Foglet.TUI.LayoutSmoke.SysopHelper do
  @moduledoc """
  Per-tab size-contract registry for the Sysop screen (Phase 25, D-09/D-11).

  Plan 04 fills in SITE/LIMITS/BOARDS/USERS/SYSTEM blocks here.
  Plan 01 ships the sentinel BOARDS block to prove the set_active_tab/2 helper
  and macro pattern work end-to-end.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  defmacro register_sysop_size_contracts do
    quote do
      import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]

      alias Foglet.TUI.Screens.Sysop
      alias Foglet.TUI.TextWidth

      # Sentinel block: proves the set_active_tab/2 helper and macro pattern
      # work against the already-converted Sysop.BoardsView (Phase 24).
      # Plans 04 adds the full SITE/LIMITS/BOARDS/USERS/SYSTEM suite here.
      describe "sysop boards tab — size contract (Phase 25 helper sentinel)" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"sysop boards size contract"
          test "at #{width}x#{height} primitives render within bounds" do
            width = @width
            height = @height

            ss =
              Sysop.init_screen_state()
              |> set_active_tab("BOARDS")

            state =
              %Foglet.TUI.App{
                current_screen: :sysop,
                current_user: %{
                  id: "u1",
                  handle: "sysop",
                  role: :sysop,
                  status: :active
                },
                session_context: %{},
                terminal_size: {width, height},
                screen_state: %{sysop: ss}
              }
              |> Map.from_struct()

            tree = Sysop.render(state)
            positioned = apply_at_size(tree, {width, height})

            for el <- text_elements(positioned) do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end
          end
        end
      end
    end
  end
end

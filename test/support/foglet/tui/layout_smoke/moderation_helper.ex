defmodule Foglet.TUI.LayoutSmoke.ModerationHelper do
  @moduledoc """
  Per-tab size-contract registry for the Moderation screen (Phase 25, D-09/D-11).

  Plan 03 fills in LOG/USERS/BOARDS/INVITES blocks here.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  @doc false
  def moderation_smoke_state(width, height, screen_state, policy \\ "sysop_only") do
    %Foglet.TUI.App{
      current_screen: :moderation,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "mod", role: :mod},
      session_context: %{registration_mode: "invite_only", invite_code_generators: policy},
      terminal_size: {width, height},
      screen_state: %{moderation: screen_state}
    }
    |> Map.from_struct()
  end

  @doc false
  def render_moderation_smoke_state(state) do
    app = struct!(Foglet.TUI.App, Map.take(state, Map.keys(%Foglet.TUI.App{})))
    context = Foglet.TUI.App.build_context(app)

    local_state =
      Foglet.TUI.App.screen_state_for(app, :moderation) ||
        Foglet.TUI.Screens.Moderation.init(context)

    Foglet.TUI.Screens.Moderation.render(local_state, context)
  end

  defmacro register_moderation_size_contracts do
    quote do
      import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]
      alias Foglet.TUI.LayoutSmoke.ModerationHelper
      require Foglet.TUI.LayoutSmoke.ModerationHelper

      ModerationHelper.moderation_log_size_contracts()
      ModerationHelper.moderation_users_size_contracts()
      ModerationHelper.moderation_boards_size_contracts()
      ModerationHelper.moderation_invites_size_contracts()
    end
  end

  defmacro moderation_log_size_contracts do
    quote do
      describe "moderation log tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation log size contract"
          test "at #{width}x#{height} KvGrid summary and ConsoleTable fit within bounds" do
            width = @width
            height = @height

            log_row = %Foglet.Moderation.Action{
              kind: :hide_oneliner,
              target_kind: :oneliner,
              target_id: "t1",
              reason: "spam",
              metadata: %{"body" => "some content", "author_handle" => "target"},
              mod: %Foglet.Accounts.User{handle: "mod1", id: "u1", role: :mod},
              inserted_at: ~U[2026-01-01 00:00:00Z]
            }

            ss =
              Foglet.TUI.Screens.Moderation.State.new(mod_log: [log_row])
              |> set_active_tab("LOG")

            state =
              Foglet.TUI.LayoutSmoke.ModerationHelper.moderation_smoke_state(width, height, ss)

            positioned =
              state
              |> Foglet.TUI.LayoutSmoke.ModerationHelper.render_moderation_smoke_state()
              |> apply_at_size({width, height})

            elements = content_text_elements(positioned)

            for el <- elements do
              assert el.x + Foglet.TUI.TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"

              assert el.y < height,
                     "element #{inspect(el.text)} at y=#{el.y} exceeds height #{height}"
            end

            tab_row =
              elements
              |> Enum.group_by(& &1.y)
              |> Map.values()
              |> Enum.find([], fn row ->
                Enum.any?(row, &String.contains?(&1.text, "QUEUE")) and
                  Enum.any?(row, &String.contains?(&1.text, "LOG"))
              end)
              |> Enum.sort_by(& &1.x)
              |> Enum.map_join(& &1.text)

            assert Foglet.TUI.TextWidth.display_width(tab_row) <= 60,
                   "tab row exceeded 60-column frame budget: #{inspect(tab_row)}"

            all_text = Enum.map_join(elements, " ", & &1.text)

            assert all_text =~ "Scope" or all_text =~ "When" or all_text =~ "Actor" or
                     all_text =~ "hide_oneliner",
                   "Expected LOG primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            coords = Enum.map(elements, &{&1.x, &1.y})

            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end
    end
  end

  defmacro moderation_users_size_contracts do
    quote do
      describe "moderation users tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation users size contract"
          test "at #{width}x#{height} KvGrid summary and ConsoleTable fit within bounds" do
            width = @width
            height = @height

            ss =
              Foglet.TUI.Screens.Moderation.State.new(
                users: [%{handle: "alice", role: :user, status: :active}]
              )
              |> set_active_tab("USERS")

            state =
              Foglet.TUI.LayoutSmoke.ModerationHelper.moderation_smoke_state(width, height, ss)

            positioned =
              state
              |> Foglet.TUI.LayoutSmoke.ModerationHelper.render_moderation_smoke_state()
              |> apply_at_size({width, height})

            elements = content_text_elements(positioned)

            for el <- elements do
              assert el.x + Foglet.TUI.TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"

              assert el.y < height,
                     "element #{inspect(el.text)} at y=#{el.y} exceeds height #{height}"
            end

            tab_row =
              elements
              |> Enum.group_by(& &1.y)
              |> Map.values()
              |> Enum.find([], fn row ->
                Enum.any?(row, &String.contains?(&1.text, "QUEUE")) and
                  Enum.any?(row, &String.contains?(&1.text, "USERS"))
              end)
              |> Enum.sort_by(& &1.x)
              |> Enum.map_join(& &1.text)

            assert Foglet.TUI.TextWidth.display_width(tab_row) <= 60,
                   "tab row exceeded 60-column frame budget: #{inspect(tab_row)}"

            all_text = Enum.map_join(elements, " ", & &1.text)

            assert all_text =~ "Scope" or all_text =~ "Handle" or all_text =~ "Status",
                   "Expected USERS primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            coords = Enum.map(elements, &{&1.x, &1.y})

            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end
    end
  end

  defmacro moderation_boards_size_contracts do
    quote do
      describe "moderation boards tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation boards size contract"
          test "at #{width}x#{height} KvGrid summary and ConsoleTable fit within bounds" do
            width = @width
            height = @height

            board_row = %{
              name: "General",
              slug: "general",
              category_name: "Main",
              scope: :site,
              state: :active
            }

            ss =
              Foglet.TUI.Screens.Moderation.State.new(
                scopes: [:site],
                boards: [board_row]
              )
              |> set_active_tab("BOARDS")

            state =
              Foglet.TUI.LayoutSmoke.ModerationHelper.moderation_smoke_state(width, height, ss)

            positioned =
              state
              |> Foglet.TUI.LayoutSmoke.ModerationHelper.render_moderation_smoke_state()
              |> apply_at_size({width, height})

            elements = content_text_elements(positioned)

            for el <- elements do
              assert el.x + Foglet.TUI.TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"

              assert el.y < height,
                     "element #{inspect(el.text)} at y=#{el.y} exceeds height #{height}"
            end

            tab_row =
              elements
              |> Enum.group_by(& &1.y)
              |> Map.values()
              |> Enum.find([], fn row ->
                Enum.any?(row, &String.contains?(&1.text, "QUEUE")) and
                  Enum.any?(row, &String.contains?(&1.text, "BOARDS"))
              end)
              |> Enum.sort_by(& &1.x)
              |> Enum.map_join(& &1.text)

            assert Foglet.TUI.TextWidth.display_width(tab_row) <= 60,
                   "tab row exceeded 60-column frame budget: #{inspect(tab_row)}"

            all_text = Enum.map_join(elements, " ", & &1.text)

            assert all_text =~ "Scope" or all_text =~ "Board" or all_text =~ "Category" or
                     all_text =~ "General",
                   "Expected BOARDS primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            coords = Enum.map(elements, &{&1.x, &1.y})

            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end
    end
  end

  defmacro moderation_invites_size_contracts do
    quote do
      describe "moderation invites tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation invites size contract"
          test "at #{width}x#{height} ConsoleTable fits within bounds" do
            width = @width
            height = @height

            invite_item = %{
              code: "ABC123",
              status: :active,
              inserted_at: ~U[2026-01-01 00:00:00Z],
              consumed_by_user_id: nil
            }

            ss =
              Foglet.TUI.Screens.Moderation.State.new(invites_visible?: true)
              |> set_active_tab("INVITES")
              |> Map.put(
                :invites,
                Foglet.TUI.Screens.Shared.InvitesState.new(items: [invite_item])
              )

            state =
              Foglet.TUI.LayoutSmoke.ModerationHelper.moderation_smoke_state(
                width,
                height,
                ss,
                "mods"
              )

            positioned =
              state
              |> Foglet.TUI.LayoutSmoke.ModerationHelper.render_moderation_smoke_state()
              |> apply_at_size({width, height})

            elements = content_text_elements(positioned)

            for el <- elements do
              assert el.x + Foglet.TUI.TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            all_text = Enum.map_join(elements, " ", & &1.text)

            assert all_text =~ "Code" or all_text =~ "Status" or all_text =~ "ABC123" or
                     all_text =~ "Generate",
                   "Expected INVITES primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            coords = Enum.map(elements, &{&1.x, &1.y})

            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end
    end
  end
end

defmodule Foglet.TUI.LayoutSmoke.ModerationHelper do
  @moduledoc """
  Per-tab size-contract registry for the Moderation screen (Phase 25, D-09/D-11).

  Plan 03 fills in LOG/USERS/BOARDS/INVITES blocks here.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  defmacro register_moderation_size_contracts do
    quote do
      import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]

      alias Foglet.Accounts.User
      alias Foglet.Moderation.Action
      alias Foglet.TUI.Screens.Moderation
      alias Foglet.TUI.Screens.Shared.InvitesState
      alias Foglet.TUI.TextWidth

      # ---------------------------------------------------------------------------
      # LOG tab — size contract
      # ---------------------------------------------------------------------------

      describe "moderation log tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation log size contract"
          test "at #{width}x#{height} KvGrid summary and ConsoleTable fit within bounds" do
            width = @width
            height = @height

            log_row = %Action{
              kind: :hide_oneliner,
              target_kind: :oneliner,
              target_id: "t1",
              reason: "spam",
              metadata: %{"body" => "some content", "author_handle" => "target"},
              mod: %User{handle: "mod1", id: "u1", role: :mod},
              inserted_at: ~U[2026-01-01 00:00:00Z]
            }

            ss =
              Moderation.init_screen_state(mod_log: [log_row])
              |> set_active_tab("LOG")

            state =
              %Foglet.TUI.App{
                current_screen: :moderation,
                current_user: %User{id: "u1", handle: "mod", role: :mod},
                session_context: %{invite_code_generators: "sysop_only"},
                terminal_size: {width, height},
                screen_state: %{moderation: ss}
              }
              |> Map.from_struct()

            tree = Moderation.render(state)
            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            # (a) Bounds check
            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            # (b) Primitive sentinel: KvGrid Scope label OR ConsoleTable header
            all_text = elements |> Enum.map(& &1.text) |> Enum.join(" ")

            assert all_text =~ "Scope" or all_text =~ "When" or all_text =~ "Actor" or
                     all_text =~ "hide_oneliner",
                   "Expected LOG primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            # (c) No-overlap: no two elements at same {x, y}
            coords = Enum.map(elements, &{&1.x, &1.y})
            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end

      # ---------------------------------------------------------------------------
      # USERS tab — size contract
      # ---------------------------------------------------------------------------

      describe "moderation users tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"moderation users size contract"
          test "at #{width}x#{height} KvGrid summary and ConsoleTable fit within bounds" do
            width = @width
            height = @height

            user_row = %{handle: "alice", role: :user, status: :active}

            ss =
              Moderation.init_screen_state(users: [user_row])
              |> set_active_tab("USERS")

            state =
              %Foglet.TUI.App{
                current_screen: :moderation,
                current_user: %User{id: "u1", handle: "mod", role: :mod},
                session_context: %{invite_code_generators: "sysop_only"},
                terminal_size: {width, height},
                screen_state: %{moderation: ss}
              }
              |> Map.from_struct()

            tree = Moderation.render(state)
            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            # (a) Bounds check
            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            # (b) Primitive sentinel: KvGrid Scope label OR ConsoleTable header
            all_text = elements |> Enum.map(& &1.text) |> Enum.join(" ")

            assert all_text =~ "Scope" or all_text =~ "Handle" or all_text =~ "Status",
                   "Expected USERS primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            # (c) No-overlap
            coords = Enum.map(elements, &{&1.x, &1.y})
            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end

      # ---------------------------------------------------------------------------
      # BOARDS tab — size contract
      # ---------------------------------------------------------------------------

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
              Moderation.init_screen_state(scopes: [:site], boards: [board_row])
              |> set_active_tab("BOARDS")

            state =
              %Foglet.TUI.App{
                current_screen: :moderation,
                current_user: %User{id: "u1", handle: "mod", role: :mod},
                session_context: %{invite_code_generators: "sysop_only"},
                terminal_size: {width, height},
                screen_state: %{moderation: ss}
              }
              |> Map.from_struct()

            tree = Moderation.render(state)
            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            # (a) Bounds check
            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            # (b) Primitive sentinel: KvGrid Scope label OR ConsoleTable header OR board name
            all_text = elements |> Enum.map(& &1.text) |> Enum.join(" ")

            assert all_text =~ "Scope" or all_text =~ "Board" or all_text =~ "Category" or
                     all_text =~ "General",
                   "Expected BOARDS primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            # (c) No-overlap
            coords = Enum.map(elements, &{&1.x, &1.y})
            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end

      # ---------------------------------------------------------------------------
      # INVITES tab — size contract
      # ---------------------------------------------------------------------------

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
              Moderation.init_screen_state(invites_visible?: true)
              |> set_active_tab("INVITES")
              |> Map.put(:invites, InvitesState.new(items: [invite_item]))

            state =
              %Foglet.TUI.App{
                current_screen: :moderation,
                current_user: %User{id: "u1", handle: "mod", role: :mod},
                session_context: %{invite_code_generators: "mods"},
                terminal_size: {width, height},
                screen_state: %{moderation: ss}
              }
              |> Map.from_struct()

            tree = Moderation.render(state)
            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            # (a) Bounds check
            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            # (b) Primitive sentinel: ConsoleTable header OR invite data
            all_text = elements |> Enum.map(& &1.text) |> Enum.join(" ")

            assert all_text =~ "Code" or all_text =~ "Status" or all_text =~ "ABC123" or
                     all_text =~ "Generate",
                   "Expected INVITES primitives at #{width}x#{height}, got: #{inspect(all_text)}"

            # (c) No-overlap
            coords = Enum.map(elements, &{&1.x, &1.y})
            assert length(coords) == length(Enum.uniq(coords)),
                   "Overlapping text elements detected at #{width}x#{height}"
          end
        end
      end
    end
  end
end

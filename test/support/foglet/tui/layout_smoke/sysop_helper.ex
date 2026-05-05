# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
defmodule Foglet.TUI.LayoutSmoke.SysopHelper do
  @moduledoc """
  Per-tab size-contract registry for the Sysop screen (Phase 25, D-09/D-11).

  Plan 04 fills in SITE/LIMITS/BOARDS/USERS/SYSTEM blocks here.
  Plan 01 ships the sentinel BOARDS block to prove the set_active_tab/2 helper
  and macro pattern work end-to-end.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  @doc """
  Recursively collect all text strings from a Raxol render tree.

  Used for D-09 primitive-presence sentinel checks in tabs where the layout
  engine's height clipping or nested-list output would otherwise prevent
  text_elements/1 from finding the sentinel.
  """
  @spec collect_text(any()) :: [String.t()]
  def collect_text(tree), do: do_collect(tree, []) |> Enum.reverse()

  defp do_collect(nil, acc), do: acc
  defp do_collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &do_collect/2)

  defp do_collect(%{children: children} = node, acc) do
    acc = node_text(node, acc)
    do_collect(children, acc)
  end

  defp do_collect(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp do_collect(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp do_collect(_other, acc), do: acc

  defp node_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp node_text(%{text: text}, acc) when is_binary(text), do: [text | acc]
  defp node_text(_node, acc), do: acc

  @doc """
  FOG-181: assert the SYSTEM tab footer "[R] Refresh snapshot" renders
  strictly below every kv-row label in the positioned tree, given a list of
  positioned text elements.

  Returns a list of `{label, reason}` violations — empty when the layout is
  clean. The caller does the ExUnit assertion so failures point at the test
  source line.
  """
  @spec system_tab_footer_violations([map()]) ::
          [{String.t(), :missing} | {String.t(), :overlap, non_neg_integer(), non_neg_integer()}]
          | {:no_footer}
          | {:footer_text, String.t()}
  def system_tab_footer_violations(elements) when is_list(elements) do
    footer_el =
      Enum.find(elements, fn el ->
        is_binary(Map.get(el, :text)) and String.contains?(el.text, "[R] Refresh snapshot")
      end)

    cond do
      footer_el == nil ->
        {:no_footer}

      footer_el.text != "[R] Refresh snapshot" ->
        {:footer_text, footer_el.text}

      true ->
        kv_row_labels = [
          "Version:",
          "Uptime:",
          "Live sessions:",
          "Active boards:",
          "BEAM processes:",
          "Database pool:"
        ]

        for label <- kv_row_labels,
            violation = check_kv_row(label, elements, footer_el),
            not is_nil(violation),
            do: violation
    end
  end

  defp check_kv_row(label, elements, footer_el) do
    case Enum.find(elements, fn el ->
           is_binary(Map.get(el, :text)) and String.contains?(el.text, label)
         end) do
      nil -> {label, :missing}
      %{y: y} when y >= footer_el.y -> {label, :overlap, y, footer_el.y}
      _ -> nil
    end
  end

  @doc false
  def render_sysop_smoke_state(state) do
    app = struct!(Foglet.TUI.App, Map.take(state, Map.keys(%Foglet.TUI.App{})))
    context = Foglet.TUI.App.build_context(app)

    local_state =
      Foglet.TUI.App.screen_state_for(app, :sysop) || Foglet.TUI.Screens.Sysop.init(context)

    Foglet.TUI.Screens.Sysop.render(local_state, context)
  end

  defmacro register_sysop_size_contracts do
    quote do
      import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]

      alias Foglet.TUI.LayoutSmoke.SysopHelper
      alias Foglet.TUI.Screens.Sysop
      alias Foglet.TUI.Screens.Sysop.LimitsForm
      alias Foglet.TUI.Screens.Sysop.SiteForm
      alias Foglet.TUI.Screens.Sysop.SystemSnapshot
      alias Foglet.TUI.Screens.Sysop.UsersView
      alias Foglet.TUI.TextWidth

      describe "sysop site tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"sysop site size contract"
          test "at #{width}x#{height} form actions live in the screen command bar" do
            width = @width
            height = @height

            ss =
              Sysop.State.new()
              |> Map.put(:site_form, SiteForm.init([]))
              |> set_active_tab("SITE")

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

            tree = SysopHelper.render_sysop_smoke_state(state)
            texts = SysopHelper.collect_text(tree)

            refute Enum.any?(texts, &String.contains?(&1, "[Enter] Submit")),
                   "expected SITE tab to suppress the Modal.Form footer at #{width}x#{height}"

            assert Enum.any?(texts, &String.contains?(&1, "Edit")),
                   "expected command-bar Edit action at #{width}x#{height}"

            assert Enum.any?(texts, &String.contains?(&1, "Select")),
                   "expected command-bar selection help at #{width}x#{height}"

            refute Enum.any?(texts, &String.contains?(&1, "Ctrl+S")),
                   "SITE list mode must not advertise legacy full-form save at #{width}x#{height}"
          end
        end
      end

      # LIMITS descriptions exceed terminal width, making full-form bounds
      # assertions unreliable; the positioned footer check keeps the command-bar
      # text itself in bounds after FOG-713 moved form actions out of body footers.
      describe "sysop limits tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"sysop limits size contract"
          test "at #{width}x#{height} save footer sentinel renders within bounds" do
            width = @width
            height = @height
            # Phase 29 D-07: lifecycle slot wrapped as {:loaded, _}.
            ss =
              Sysop.State.new()
              |> Map.put(:limits_form, {:loaded, LimitsForm.init([])})
              |> set_active_tab("LIMITS")

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

            tree = SysopHelper.render_sysop_smoke_state(state)
            texts = SysopHelper.collect_text(tree)

            refute Enum.any?(texts, &String.contains?(&1, "[Tab] Next")),
                   "expected LIMITS tab to suppress body footer at #{width}x#{height}"

            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            assert Enum.any?(texts, &String.contains?(&1, "Ctrl+S")),
                   "expected command-bar Ctrl+S key at #{width}x#{height}"

            footer_el =
              Enum.find(elements, fn el -> String.contains?(el.text, "Save") end)

            assert footer_el, "expected positioned command-bar save at #{width}x#{height}"

            assert footer_el.x + TextWidth.display_width(footer_el.text) <= width,
                   "footer #{inspect(footer_el.text)} at x=#{footer_el.x} exceeds width #{width}"

            assert footer_el.y < height,
                   "footer #{inspect(footer_el.text)} at y=#{footer_el.y} exceeds height #{height}"

            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end
          end
        end
      end

      describe "sysop boards tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"sysop boards size contract"
          test "at #{width}x#{height} primitives render within bounds" do
            width = @width
            height = @height

            ss =
              Sysop.State.new()
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

            tree = SysopHelper.render_sysop_smoke_state(state)
            positioned = apply_at_size(tree, {width, height})

            for el <- text_elements(positioned) do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end
          end
        end
      end

      # Sentinel check via raw tree traversal (D-09 primitive presence).
      # The action footer is wider than 64 columns; raw traversal confirms
      # ConsoleTable renders the "Handle" column header in the non-empty path.
      describe "sysop users tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"sysop users size contract"
          test "at #{width}x#{height} ConsoleTable header sentinel renders within bounds" do
            width = @width
            height = @height

            # Non-empty rows required to reach the header-text render path.
            fake_user = %{
              id: "u1",
              handle: "alice",
              email: "alice@foglet.io",
              role: :user,
              status: :active
            }

            users_view = %UsersView{
              rows: [{:active, fake_user}],
              selection_index: 0,
              groups: %{active: [fake_user], pending: [], suspended: [], rejected: []},
              message: nil,
              users_table: nil,
              current_user: nil
            }

            # Phase 29 D-07: lifecycle slot wrapped as {:loaded, _}.
            ss =
              Sysop.State.new()
              |> Map.put(:users_view, {:loaded, users_view})
              |> set_active_tab("USERS")

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

            texts =
              state
              |> SysopHelper.render_sysop_smoke_state()
              |> SysopHelper.collect_text()

            assert Enum.any?(texts, &String.contains?(&1, "Handle")),
                   "expected 'Handle' at #{width}x#{height}"
          end
        end
      end

      # FOG-177: SYSTEM previously rendered through a KvGrid call that
      # interspersed text("\n") nodes, which produced literal embedded
      # newlines in the layout and pushed the Sysop chrome off-screen in the
      # live SSH harness (parent issue: FOG-151 / PR #26). KvGrid now emits
      # one layout element per entry, so we can both verify the key sentinel
      # AND assert primitive bounds (the BOARDS-style apply_at_size check)
      # so a regression that overflows or breaks rows is caught here without
      # needing the live PTY sweep.
      describe "sysop system tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}, {100, 30}] do
          @width width
          @height height
          @tag :"sysop system size contract"
          test "at #{width}x#{height} KvGrid key sentinel renders within bounds" do
            width = @width
            height = @height

            # Phase 29 D-07: lifecycle slot wrapped as {:loaded, _}.
            ss =
              Sysop.State.new()
              |> Map.put(:system_snapshot, {:loaded, SystemSnapshot.init()})
              |> set_active_tab("SYSTEM")

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

            tree = SysopHelper.render_sysop_smoke_state(state)

            texts = SysopHelper.collect_text(tree)

            assert Enum.any?(texts, &String.contains?(&1, "Live sessions:")),
                   "expected 'Live sessions:' at #{width}x#{height}"

            # Frame sentinels: the Sysop shell breadcrumb and the SYSTEM tab
            # marker must render — their absence is the FOG-177 regression
            # signature (the entire chrome was clipped off screen).
            assert Enum.any?(texts, &String.contains?(&1, "Foglet")),
                   "expected 'Foglet' breadcrumb at #{width}x#{height}"

            assert Enum.any?(texts, &String.contains?(&1, "SYSTEM")),
                   "expected 'SYSTEM' tab label at #{width}x#{height}"

            # No text node should embed a literal \n — that was the layout
            # corruption that broke the chrome on the SYSTEM tab.
            refute Enum.any?(texts, &String.contains?(&1, "\n")),
                   "no text node should embed a literal newline"

            # Bounds: every positioned text element must fit inside the
            # terminal width. Now reachable because KvGrid no longer emits
            # nested `[text, badge]` lists that crashed apply_at_size.
            positioned = apply_at_size(tree, {width, height})

            for el <- text_elements(positioned) do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
            end

            # FOG-181: the SYSTEM action footer "[R] Refresh snapshot" must
            # render strictly below every kv-row label. Before the fix the
            # nested kv `column` was measured as a single line in the parent
            # flex layout, so the inner rows stacked at y values that
            # overlapped the sibling helper / footer text — the BEAM-process
            # value bled through the shorter footer
            # ("[R] Refresh snapshot9").
            assert SysopHelper.system_tab_footer_violations(text_elements(positioned)) == [],
                   "SYSTEM tab footer overlap at #{width}x#{height}: #{inspect(SysopHelper.system_tab_footer_violations(text_elements(positioned)))}"
          end
        end
      end
    end
  end
end

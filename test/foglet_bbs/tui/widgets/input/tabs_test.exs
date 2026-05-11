defmodule Foglet.TUI.Widgets.Input.TabsTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [
      flatten_text: 1,
      color_atom_leaked?: 2,
      color_names: 0
    ]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Tabs

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      border: %{fg: "#tabs-border"},
      accent: %{fg: "#tabs-indicator"},
      selected: %{fg: "#tabs-selected", bg: "#tabs-selected-bg"},
      unselected: %{fg: "#tabs-unselected"}
    }
  end

  defp tabs_state do
    Tabs.init(tabs: ["Home", "Posts", "Settings"])
  end

  describe "init/1" do
    test "test 2 — active index defaults to 0" do
      state = tabs_state()
      assert Map.get(state.raxol_state, :active_index) == 0
    end

    test "init with custom active index" do
      state = Tabs.init(tabs: ["A", "B", "C"], active: 1)
      assert Map.get(state.raxol_state, :active_index) == 1
    end

    test "WR-04 — atom tab entries are coerced to string labels" do
      state = Tabs.init(tabs: [:home, :posts])
      flat = flatten_text(Tabs.render(state, theme: theme()))
      assert flat =~ "home"
      assert flat =~ "posts"
    end

    test "WR-04 — map with :label passes through" do
      state = Tabs.init(tabs: [%{label: "Mixed"}])
      flat = flatten_text(Tabs.render(state, theme: theme()))
      assert flat =~ "Mixed"
    end

    test "WR-04 — nil tab entry raises ArgumentError with helpful message" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [nil])
      end
    end

    test "WR-04 — tuple tab entry raises ArgumentError" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [{:bad, "shape"}])
      end
    end

    test "WR-04 — map without :label raises ArgumentError" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [%{name: "oops"}])
      end
    end

    test "WR-02 — :active above last tab clamps to the final tab" do
      state = Tabs.init(tabs: ["A", "B", "C"], active: 99)
      assert Map.get(state.raxol_state, :active_index) == 2

      flat = flatten_text(Tabs.render(state, theme: distinctive_theme()))
      assert flat == "A   B   ▌ C"
    end

    test "WR-02 — negative :active clamps to the first tab" do
      state = Tabs.init(tabs: ["A", "B", "C"], active: -1)
      assert Map.get(state.raxol_state, :active_index) == 0

      flat = flatten_text(Tabs.render(state, theme: distinctive_theme()))
      assert flat == "▌ A   B   C"
    end

    test "WR-02 — empty tab list with non-zero :active falls back to 0" do
      state = Tabs.init(tabs: [], active: 5)
      assert Map.get(state.raxol_state, :active_index) == 0
    end

    test "WR-02 — clamped state still renders exactly one indicator" do
      tree = Tabs.render(Tabs.init(tabs: ["A", "B"], active: 99), theme: distinctive_theme())
      flat = flatten_text(tree)

      indicator_count = flat |> String.split("▌") |> length() |> Kernel.-(1)
      assert indicator_count == 1
    end
  end

  describe "handle_event/2 (D-14)" do
    test "test 3 — Right arrow advances to index 1" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :right}, state)
      assert action == {:tab_changed, 1}
    end

    test "FOG-1186 — SSH parser-shaped Left/Right arrows change tabs" do
      right_event =
        "\e[C"
        |> Raxol.SSH.IOAdapter.parse_input()
        |> List.first()
        |> Foglet.TUI.App.MessageNormalizer.normalize()

      left_event =
        "\e[D"
        |> Raxol.SSH.IOAdapter.parse_input()
        |> List.first()
        |> Foglet.TUI.App.MessageNormalizer.normalize()

      assert {:key, %{key: :right} = right_key} = right_event
      assert {:key, %{key: :left} = left_key} = left_event

      {state, action} = Tabs.handle_event(right_key, tabs_state())
      assert action == {:tab_changed, 1}

      {_state, action} = Tabs.handle_event(left_key, state)
      assert action == {:tab_changed, 0}
    end

    test "test 5 — digit key '2' jumps to index 1" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :char, char: "2"}, state)
      assert action == {:tab_changed, 1}
    end

    test "test 6 — unrelated key returns nil action and is pure" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :enter}, state)
      assert is_nil(action)
    end

    test "test 7 — purity: same input + event -> same output" do
      state = tabs_state()
      result1 = Tabs.handle_event(%{key: :right}, state)
      result2 = Tabs.handle_event(%{key: :right}, state)
      assert result1 == result2
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "test 1 — returns a non-nil map with :type key" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
      assert result.type in [:row, :flex]
    end

    test "rendered output contains tab labels" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Home"
    end
  end

  describe "render/2 — visual contract" do
    test "default tab strip owns indicator, active label, inactive labels, and spacing" do
      state = Tabs.init(tabs: ["Profile", "Prefs", "SSH Keys", "Invites"], active: 0)
      tree = Tabs.render(state, theme: distinctive_theme())
      flat = flatten_text(tree)

      assert flat == "▌ Profile   Prefs   SSH Keys   Invites"
      assert flat |> String.split("▌") |> length() |> Kernel.-(1) == 1
      refute flat =~ "(active)"
      refute flat =~ "[selected]"
    end

    test "active indicator moves with active index" do
      state = Tabs.init(tabs: ["Profile", "Prefs", "SSH Keys", "Invites"], active: 2)
      flat = flatten_text(Tabs.render(state, theme: distinctive_theme()))

      assert flat == "Profile   Prefs   ▌ SSH Keys   Invites"
    end

    test "compact width clamps tab strip to drawable frame budget" do
      state =
        Tabs.init(
          tabs: ["Profile", "Preferences", "SSH Public Keys", "Invite Management"],
          active: 2
        )

      flat = flatten_text(Tabs.render(state, theme: distinctive_theme(), width: 60))

      assert TextWidth.display_width(flat) <= 60
      assert flat =~ "▌ S"
    end

    test "active tab keeps indicator and a visible label character when labels overflow" do
      state =
        Tabs.init(
          tabs: ["Queue Review", "Moderation Log", "User Administration", "Sanctions", "Boards"],
          active: 2
        )

      flat = flatten_text(Tabs.render(state, theme: distinctive_theme(), width: 24))

      assert TextWidth.display_width(flat) <= 24
      assert flat =~ "▌ U"
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "test 8 — no hardcoded color atoms in rendered tree" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Tabs leaked :#{color} atom in serialized tree"
      end
    end

    test "test 9 — alt-theme produces different rendered output" do
      state = tabs_state()
      default_result = Tabs.render(state, theme: theme())
      danger_result = Tabs.render(state, theme: alt_theme())

      refute inspect(default_result, printable_limit: :infinity, limit: :infinity) ==
               inspect(danger_result, printable_limit: :infinity, limit: :infinity)
    end

    test "test 10 — moduledoc mentions digit shortcuts and D-15 caller-filter contract" do
      {:docs_v1, _anno, _lang, _format, %{"en" => moduledoc}, _metadata, _docs} =
        Code.fetch_docs(Foglet.TUI.Widgets.Input.Tabs)

      has_digit_ref =
        String.contains?(moduledoc, "digit") or String.contains?(moduledoc, "1-9") or
          String.contains?(moduledoc, "1–9")

      has_d15_ref = String.contains?(moduledoc, "D-15")

      assert has_digit_ref or has_d15_ref,
             "Moduledoc must mention digit shortcuts (1-9) and/or D-15 screen-filter contract"
    end
  end
end

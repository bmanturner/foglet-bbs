defmodule Foglet.TUI.SizeGateTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.SizeGate
  alias Foglet.TUI.Theme

  describe "min_cols/0 and min_rows/0" do
    test "min_cols/0 returns 64" do
      assert SizeGate.min_cols() == 64
    end

    test "min_rows/0 returns 22" do
      assert SizeGate.min_rows() == 22
    end
  end

  describe "too_small?/1" do
    test "returns true when cols < 64" do
      assert SizeGate.too_small?(%{terminal_size: {63, 30}})
      assert SizeGate.too_small?(%{terminal_size: {40, 30}})
      assert SizeGate.too_small?(%{terminal_size: {1, 30}})
    end

    test "returns true when rows < 22" do
      assert SizeGate.too_small?(%{terminal_size: {100, 21}})
      assert SizeGate.too_small?(%{terminal_size: {100, 10}})
      assert SizeGate.too_small?(%{terminal_size: {100, 1}})
    end

    test "returns true when both dims below" do
      assert SizeGate.too_small?(%{terminal_size: {40, 10}})
    end

    test "returns false at exactly 64×22 (strict inequality per D-13)" do
      refute SizeGate.too_small?(%{terminal_size: {64, 22}})
    end

    test "returns false at 80×24 (common default)" do
      refute SizeGate.too_small?(%{terminal_size: {80, 24}})
    end

    test "returns false at typical laptop sizes (120×40, 200×60)" do
      refute SizeGate.too_small?(%{terminal_size: {120, 40}})
      refute SizeGate.too_small?(%{terminal_size: {200, 60}})
    end

    test "returns false when terminal_size is missing (safety fallback)" do
      refute SizeGate.too_small?(%{})
      refute SizeGate.too_small?(%{terminal_size: nil})
      refute SizeGate.too_small?(%{other_field: 42})
    end
  end

  describe "render/1" do
    test "returns a Raxol element (does not crash, returns non-nil)" do
      element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{}})
      refute is_nil(element)
    end

    test "interpolates current dimensions from state.terminal_size" do
      element = SizeGate.render(%{terminal_size: {55, 18}, session_context: %{}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ "55×18"
    end

    test "includes the minimum 64×22 in the message" do
      element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ "64×22"
    end

    test "includes all four required lines" do
      element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ "Terminal too small."
      assert serialized =~ "Foglet requires at least 64×22."
      assert serialized =~ "Your terminal is currently: 40×10."
      assert serialized =~ "Please resize."
    end

    test "uses theme.dim.fg when session_context has a theme" do
      theme = %Theme{dim: %{fg: "#999999"}}
      element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{theme: theme}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ "#999999"
    end

    test "falls back to Theme.default() when session_context is empty" do
      default = Theme.default()
      default_fg = Map.get(default.dim, :fg)
      # Ensure the default theme actually has a dim.fg — if this fails,
      # Theme.default/0 needs to be updated to provide one.
      assert default_fg != nil, "Theme.default() must provide a dim.fg for SizeGate rendering"

      element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ default_fg
    end

    test "falls back to Theme.default() when session_context is absent entirely" do
      element = SizeGate.render(%{terminal_size: {40, 10}})
      refute is_nil(element)
    end

    test "handles missing terminal_size defensively (renders sentinel)" do
      element = SizeGate.render(%{session_context: %{}})
      serialized = inspect(element, limit: :infinity)
      assert serialized =~ "unknown"
    end
  end
end

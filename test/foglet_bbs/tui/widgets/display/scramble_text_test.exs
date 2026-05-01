defmodule Foglet.TUI.Widgets.Display.ScrambleTextTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ScrambleText

  defp theme, do: Theme.default()

  defp distinctive_theme do
    %Theme{
      primary: %{fg: "#scramble-settled", style: [:bold]},
      dim: %{fg: "#scramble-dim"},
      accent: %{fg: "#scramble-cursor", style: [:bold]}
    }
  end

  defp flat(target, frame, opts \\ []) do
    target
    |> ScrambleText.render(frame, [theme: theme()] ++ opts)
    |> flatten_text()
  end

  defp settled_bitmap(target, frame, opts) do
    target_graphemes = String.graphemes(target)

    target
    |> flat(frame, opts)
    |> String.graphemes()
    |> Enum.take(length(target_graphemes))
    |> Enum.zip(target_graphemes)
    |> Enum.map(fn {actual, expected} -> actual == expected end)
  end

  describe "render/3 determinism and settling" do
    test "fixed seed, frame, and options render the same output" do
      opts = [seed: 123, direction: :center_out, charset: :upper]

      assert flat("Foglet", 3, opts) == flat("Foglet", 3, opts)
    end

    test "final frame settles exactly to the target" do
      opts = [seed: 123, direction: :right_to_left, cursor: :block]
      frame = ScrambleText.settled_frame("Foglet", opts)

      assert flat("Foglet", frame, opts) == "Foglet"
    end

    test "empty string returns empty themed text" do
      assert flat("", 0) == ""
    end

    test "one-grapheme target scrambles and then settles" do
      assert flat("x", 0, charset: {:custom, "Z"}, seed: 1) == "Z"
      assert flat("x", 2, charset: {:custom, "Z"}, seed: 1) == "x"
    end

    test "non-ASCII grapheme target settles correctly" do
      target = "cafe\u0301"
      frame = ScrambleText.settled_frame(target, reveal_rate: 1)

      assert flat(target, frame, seed: 7, reveal_rate: 1) == target
    end
  end

  describe "render/3 reveal directions" do
    test "left-to-right reveals positions in order" do
      assert settled_bitmap("abcd", 2, charset: {:custom, "Z"}, reveal_rate: 2) ==
               [true, false, false, false]

      assert settled_bitmap("abcd", 4, charset: {:custom, "Z"}, reveal_rate: 2) ==
               [true, true, false, false]
    end

    test "right-to-left reveals positions in order" do
      assert settled_bitmap("abcd", 2,
               charset: {:custom, "Z"},
               direction: :right_to_left,
               reveal_rate: 2
             ) ==
               [false, false, false, true]

      assert settled_bitmap("abcd", 4,
               charset: {:custom, "Z"},
               direction: :right_to_left,
               reveal_rate: 2
             ) ==
               [false, false, true, true]
    end

    test "center-out reveals middle positions first" do
      assert settled_bitmap("abcde", 2,
               charset: {:custom, "Z"},
               direction: :center_out,
               reveal_rate: 2
             ) ==
               [false, false, true, false, false]

      assert settled_bitmap("abcde", 6,
               charset: {:custom, "Z"},
               direction: :center_out,
               reveal_rate: 2
             ) ==
               [false, true, true, true, false]
    end

    test "random reveal order is deterministic for seed" do
      opts = [charset: {:custom, "Z"}, direction: :random, seed: 99, reveal_rate: 1]

      assert settled_bitmap("abcdef", 3, opts) == settled_bitmap("abcdef", 3, opts)
      refute settled_bitmap("abcdef", 3, opts) == [true, true, true, false, false, false]
    end
  end

  describe "render/3 charset, cursor, and width bounds" do
    test "custom charset controls all scrambled positions" do
      rendered = flat("abcd", 0, charset: {:custom, "XY"}, seed: 1)

      assert rendered
             |> String.graphemes()
             |> Enum.all?(&(&1 in ["X", "Y"]))
    end

    test "cursor is present while unsettled and absent when settled" do
      mid = flat("abcd", 2, charset: {:custom, "Z"}, cursor: :underscore, seed: 1)
      final_frame = ScrambleText.settled_frame("abcd", cursor: :underscore)

      assert "_" in String.graphemes(mid)
      refute "_" in String.graphemes(flat("abcd", final_frame, cursor: :underscore, seed: 1))
    end

    test "output length never exceeds target length plus optional cursor" do
      target = String.duplicate("a", 40)
      rendered = flat(target, 3, cursor: :block, seed: 1)

      assert length(String.graphemes(rendered)) <= length(String.graphemes(target)) + 1
    end
  end

  describe "render/3 theme hygiene (D-18)" do
    test "uses theme slots for settled, scrambled, and cursor runs" do
      t = distinctive_theme()
      tree = ScrambleText.render("abcd", 2, theme: t, charset: {:custom, "Z"}, cursor: :block)

      assert_text_run(tree, "a", fg: t.primary.fg)
      assert_text_run(tree, "Z", fg: t.dim.fg)
      assert_text_run(tree, "█", fg: t.accent.fg)
    end

    test "no hardcoded color atoms appear in the rendered output" do
      tree = ScrambleText.render("Foglet", 1, theme: theme(), seed: 1)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "ScrambleText leaked :#{color} atom"
      end
    end

    test "alt-theme differential changes serialized output" do
      default_tree = ScrambleText.render("Foglet", 1, theme: theme(), seed: 1)
      distinctive_tree = ScrambleText.render("Foglet", 1, theme: distinctive_theme(), seed: 1)

      refute inspect(default_tree, printable_limit: :infinity, limit: :infinity) ==
               inspect(distinctive_tree, printable_limit: :infinity, limit: :infinity)
    end
  end
end

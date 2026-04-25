defmodule Foglet.TUI.Widgets.Composer.EditorFrameTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Composer.EditorFrame

  defp distinctive_theme do
    %Theme{
      accent: %{fg: "#composer-accent"},
      border: %{fg: "#composer-border"},
      primary: %{fg: "#composer-primary"},
      dim: %{fg: "#composer-dim"},
      warning: %{fg: "#composer-warning"},
      error: %{fg: "#composer-error"}
    }
  end

  describe "render/1" do
    test "focused and unfocused frames route shell styling through editor theme slots" do
      theme = distinctive_theme()

      focused =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [],
          width: 72,
          height: 12,
          theme: theme
        )

      unfocused =
        EditorFrame.render(
          mode: :edit,
          focused?: false,
          body: text("BODY CHILD"),
          budgets: [],
          width: 72,
          height: 12,
          theme: theme
        )

      assert flatten_text(focused) =~ "Composer"
      assert inspect(focused, printable_limit: :infinity, limit: :infinity) =~ theme.accent.fg
      assert inspect(unfocused, printable_limit: :infinity, limit: :infinity) =~ theme.border.fg
    end

    test "mode labels render in-shell and active edit/preview modes differ" do
      theme = distinctive_theme()

      edit =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [],
          width: 72,
          height: 12,
          theme: theme
        )

      preview =
        EditorFrame.render(
          mode: :preview,
          focused?: true,
          body: text("PREVIEW CHILD"),
          budgets: [],
          width: 72,
          height: 12,
          theme: theme
        )

      assert flatten_text(edit) =~ "Edit"
      assert flatten_text(edit) =~ "Preview"
      assert flatten_text(preview) =~ "Edit"
      assert flatten_text(preview) =~ "Preview"

      assert inspect(edit, printable_limit: :infinity, limit: :infinity) !=
               inspect(preview, printable_limit: :infinity, limit: :infinity)
    end

    test "budget counters render compact character counts with threshold styling" do
      theme = distinctive_theme()

      normal =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [%{label: "Body", count: 4, limit: 10}],
          width: 72,
          height: 12,
          theme: theme
        )

      warning =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [%{label: "Body", count: 8, limit: 10}],
          width: 72,
          height: 12,
          theme: theme
        )

      error =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [%{label: "Body", count: 11, limit: 10}],
          width: 72,
          height: 12,
          theme: theme
        )

      assert flatten_text(normal) =~ "Body 4 / 10 chars"
      assert flatten_text(warning) =~ "Body 8 / 10 chars"
      assert flatten_text(error) =~ "Body 11 / 10 chars"

      assert_text_run(normal, "Body 4 / 10 chars", fg: theme.dim.fg)
      assert_text_run(warning, "Body 8 / 10 chars", fg: theme.warning.fg)
      assert_text_run(error, "Body 11 / 10 chars", fg: theme.error.fg)
    end

    test "context, title, editor children, preview children, and errors are presentation children" do
      theme = distinctive_theme()

      tree =
        EditorFrame.render(
          mode: :preview,
          focused?: true,
          context: text("CONTEXT CHILD"),
          title: text("TITLE CHILD"),
          body:
            column style: %{gap: 0} do
              [
                text("BODY CHILD"),
                text("PREVIEW CHILD")
              ]
            end,
          budgets: [],
          error: "ERROR CHILD",
          width: 72,
          height: 12,
          theme: theme
        )

      flat = flatten_text(tree)
      assert flat =~ "CONTEXT CHILD"
      assert flat =~ "TITLE CHILD"
      assert flat =~ "BODY CHILD"
      assert flat =~ "PREVIEW CHILD"
      assert flat =~ "ERROR CHILD"
    end

    test "render output does not leak hardcoded color atoms" do
      tree =
        EditorFrame.render(
          mode: :edit,
          focused?: true,
          body: text("BODY CHILD"),
          budgets: [%{label: "Body", count: 4, limit: 10}],
          width: 72,
          height: 12,
          theme: distinctive_theme()
        )

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "EditorFrame leaked :#{color} atom: #{serialized}"
      end
    end
  end
end

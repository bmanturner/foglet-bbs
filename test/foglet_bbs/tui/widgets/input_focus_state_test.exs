defmodule Foglet.TUI.Widgets.InputFocusStateTest do
  @moduledoc """
  FORM-04 (Phase 28 D-16): leaf input widgets MUST NOT carry their own focus
  state. Modal.Form's `focus_index` is the single source of truth for which
  field consumes the next keystroke. Stateful leaf widgets receive `focused?`
  as a render-time parameter only; their defstructs (or absence thereof) must
  not declare a focus field.

  This test pins that property forward — any future change that adds a
  `:focused`, `focused?:`, or `:focus_index` field to a leaf input widget will
  trip this test and force a design conversation about where focus state
  belongs.
  """
  use ExUnit.Case, async: true

  @leaf_widget_files [
    "lib/foglet_bbs/tui/widgets/input/text_input.ex",
    "lib/foglet_bbs/tui/widgets/input/radio_group.ex",
    "lib/foglet_bbs/tui/widgets/input/checkbox.ex"
  ]

  test "leaf input widgets carry no struct-level focus field (FORM-04)" do
    for path <- @leaf_widget_files do
      contents = File.read!(path)

      refute Regex.match?(~r/defstruct[^\n]*:focused/, contents),
             "#{path}: defstruct must not include a :focused field (FORM-04)"

      refute Regex.match?(~r/:focus_index/, contents),
             "#{path}: leaf widget must not reference :focus_index (FORM-04)"

      refute Regex.match?(~r/defstruct[^\n]*focused\?:/, contents),
             "#{path}: defstruct must not include a focused? field (FORM-04)"
    end
  end
end

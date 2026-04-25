defmodule Foglet.TUI.Widgets.Modal.FormTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form

  defp theme, do: Theme.default()

  defp default_fields do
    [
      %{name: :title, type: :text, label: "Title", max_length: 80},
      %{name: :count, type: :integer, label: "Count"},
      %{name: :enabled, type: :boolean, label: "Enabled", value: false}
    ]
  end

  defp test_form(fields \\ nil, opts \\ []) do
    fields = fields || default_fields()
    pid = self()

    Form.init(
      title: Keyword.get(opts, :title, "Test Form"),
      fields: fields,
      on_submit: fn payload -> send(pid, {:submitted, payload}) end,
      on_cancel: fn -> send(pid, :cancelled) end
    )
  end

  defp send_events(state, events) do
    Enum.reduce(events, {state, []}, fn ev, {st, acts} ->
      {st2, act} = Form.handle_event(ev, st)
      {st2, acts ++ [act]}
    end)
  end

  # --- REQ-1: smoke ---

  test "smoke: init returns Modal.Form struct and render returns view map" do
    state = test_form()
    assert %Form{} = state
    result = Form.render(state, theme: theme())
    assert is_map(result)
    assert Map.has_key?(result, :type)
  end

  test "D-18 theme hygiene: no hardcoded color atoms in rendered tree" do
    state = test_form()
    result = Form.render(state, theme: theme())
    serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

    for color <- color_names() do
      refute color_atom_leaked?(serialized, color),
             "Modal.Form leaked :#{color} atom in serialized tree"
    end
  end

  # --- REQ-2: five field types ---

  test "renders all five field types without error" do
    fields = [
      %{name: :t, type: :text, label: "T"},
      %{name: :i, type: :integer, label: "I"},
      %{name: :b, type: :boolean, label: "B", value: false},
      %{name: :e, type: :enum, label: "E", choices: [:a, :b, :c]},
      %{name: :a, type: :textarea, label: "A", rows: 3}
    ]

    state = test_form(fields)
    assert is_map(Form.render(state, theme: theme()))
  end

  # --- REQ-3: typed coercion ---

  test "typed coercion (text): submit payload has string value" do
    fields = [%{name: :name, type: :text, label: "Name"}]
    state = test_form(fields)

    # Type "hi" then Enter (single field = last field -> submits)
    events = [
      %{key: :char, char: "h"},
      %{key: :char, char: "i"},
      %{key: :enter}
    ]

    {_final_state, _actions} = send_events(state, events)
    assert_receive {:submitted, %{name: value}}
    assert is_binary(value)
    assert value == "hi"
  end

  test "typed coercion (integer): '42' -> 42, '' -> nil, '12x' -> nil" do
    pid = self()

    fields = [%{name: :count, type: :integer, label: "Count"}]

    # "42" -> integer 42
    state1 =
      Form.init(
        title: "T",
        fields: fields,
        on_submit: fn payload -> send(pid, {:submitted, payload}) end,
        on_cancel: fn -> nil end
      )

    events_42 = [
      %{key: :char, char: "4"},
      %{key: :char, char: "2"},
      %{key: :enter}
    ]

    send_events(state1, events_42)
    assert_receive {:submitted, %{count: 42}}

    # "" -> nil
    state2 =
      Form.init(
        title: "T",
        fields: fields,
        on_submit: fn payload -> send(pid, {:submitted, payload}) end,
        on_cancel: fn -> nil end
      )

    {_s2, _} = Form.handle_event(%{key: :enter}, state2)
    assert_receive {:submitted, %{count: nil}}

    # "12x" -> nil
    state3 =
      Form.init(
        title: "T",
        fields: fields,
        on_submit: fn payload -> send(pid, {:submitted, payload}) end,
        on_cancel: fn -> nil end
      )

    events_12x = [
      %{key: :char, char: "1"},
      %{key: :char, char: "2"},
      %{key: :char, char: "x"},
      %{key: :enter}
    ]

    send_events(state3, events_12x)
    assert_receive {:submitted, %{count: nil}}
  end

  test "typed coercion (boolean): Space toggles to true, submit gives boolean true" do
    fields = [%{name: :active, type: :boolean, label: "Active", value: false}]
    state = test_form(fields)

    # Space toggles boolean, Enter submits (single field)
    events = [
      %{key: :char, char: " "},
      %{key: :enter}
    ]

    send_events(state, events)
    assert_receive {:submitted, %{active: true}}
  end

  test "typed coercion (enum): Down selects second choice, submit gives atom/string (not index)" do
    fields = [%{name: :color, type: :enum, label: "Color", choices: [:red, :green, :blue]}]
    state = test_form(fields)

    events = [
      %{key: :down},
      %{key: :enter}
    ]

    send_events(state, events)
    assert_receive {:submitted, %{color: :green}}
  end

  test "typed coercion (textarea): multi-line content submits as string with newline" do
    fields = [%{name: :body, type: :textarea, label: "Body", rows: 3}]
    state = test_form(fields)

    # Type some content including a newline sequence
    events =
      Enum.map(String.codepoints("hello\nworld"), fn ch ->
        %{key: :char, char: ch}
      end) ++ [%{key: :enter}]

    send_events(state, events)

    assert_receive {:submitted, %{body: value}}
    assert is_binary(value)
    assert String.contains?(value, "\n")
  end

  # --- REQ-4: Tab / Shift-Tab focus navigation ---

  test "REQ-4 Tab wrap forward: 3-field form cycles 0 -> 1 -> 2 -> 0" do
    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"},
      %{name: :c, type: :text, label: "C"}
    ]

    state = test_form(fields)
    assert state.focus_index == 0

    {s1, _} = Form.handle_event(%{key: :tab}, state)
    assert s1.focus_index == 1

    {s2, _} = Form.handle_event(%{key: :tab}, s1)
    assert s2.focus_index == 2

    {s3, _} = Form.handle_event(%{key: :tab}, s2)
    assert s3.focus_index == 0
  end

  test "REQ-4 Shift-Tab wrap reverse: 3-field form cycles 0 -> 2 -> 1 -> 0" do
    # Shift-Tab event shape verified against
    # vendor/raxol/lib/raxol/ui/components/modal/events.ex:94
    # %{type: :key, data: %{key: "Tab", shift: true}} is the raw Raxol wire format.
    # Foglet widget convention uses the simpler flat map: %{key: :tab, shift: true}
    # (consistent with RESEARCH.md REQ-4 documentation and the :tab/:enter/:escape pattern
    #  used throughout lib/foglet_bbs/tui/screens/ and test/foglet_bbs/tui/widgets/).
    shift_tab = %{key: :tab, shift: true}

    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"},
      %{name: :c, type: :text, label: "C"}
    ]

    state = test_form(fields)
    assert state.focus_index == 0

    {s1, _} = Form.handle_event(shift_tab, state)
    assert s1.focus_index == 2

    {s2, _} = Form.handle_event(shift_tab, s1)
    assert s2.focus_index == 1

    {s3, _} = Form.handle_event(shift_tab, s2)
    assert s3.focus_index == 0
  end

  # --- REQ-5: Enter behavior ---

  test "REQ-5 Enter on last field submits and returns :submitted action" do
    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"}
    ]

    state = test_form(fields)
    # Move to last field (index 1)
    {state_at_last, _} = Form.handle_event(%{key: :tab}, state)
    assert state_at_last.focus_index == 1

    {_final, action} = Form.handle_event(%{key: :enter}, state_at_last)
    assert action == :submitted
    assert_receive {:submitted, _payload}
  end

  test "REQ-5 Enter on non-last field advances focus, does not submit" do
    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"},
      %{name: :c, type: :text, label: "C"}
    ]

    state = test_form(fields)
    assert state.focus_index == 0

    {new_state, action} = Form.handle_event(%{key: :enter}, state)
    assert new_state.focus_index == 1
    refute action == :submitted
    refute_receive {:submitted, _}
  end

  # --- REQ-6: Escape cancels ---

  test "REQ-6 Esc cancels unconditionally: on_cancel fires once, action is :cancelled" do
    fields = [%{name: :x, type: :text, label: "X"}]
    state = test_form(fields)

    # Type some chars first to ensure cancel works even with dirty state
    {dirty, _} = Form.handle_event(%{key: :char, char: "a"}, state)

    {_final, action} = Form.handle_event(%{key: :escape}, dirty)
    assert action == :cancelled
    assert_receive :cancelled
    refute_receive {:submitted, _}
  end

  # --- REQ-7: set_errors + inline rendering ---

  test "REQ-7 set_errors + render: error messages appear in rendered output" do
    state = test_form()
    state_with_errors = Form.set_errors(state, %{title: "required", count: "too long"})

    result = Form.render(state_with_errors, theme: theme())
    flat = flatten_text(result)

    assert String.contains?(flat, "required"),
           "Expected 'required' in rendered output, got: #{inspect(flat)}"

    assert String.contains?(flat, "too long"),
           "Expected 'too long' in rendered output, got: #{inspect(flat)}"
  end

  test "D-19 refreshed body renders title, required markers, and action footer" do
    fields = [
      %{name: :slug, type: :text, label: "Slug", required: true},
      %{name: :name, type: :text, label: "Name", required: true}
    ]

    state = test_form(fields, title: "Create board")
    flat = state |> Form.render(theme: theme()) |> flatten_text()

    assert flat =~ "Create board"
    assert flat =~ "Slug"
    assert flat =~ "Name"
    assert flat =~ "*"
    assert flat =~ "[Enter] Submit"
    assert flat =~ "[Esc] Cancel"
  end

  test "D-19 renders inline field errors and base errors" do
    fields = [
      %{name: :slug, type: :text, label: "Slug", required: true},
      %{name: :name, type: :text, label: "Name", required: true}
    ]

    state =
      fields
      |> test_form(title: "Create board")
      |> Form.set_errors(%{slug: "can't be blank", base: "Board invalid"})

    flat = state |> Form.render(theme: theme()) |> flatten_text()

    assert flat =~ "can't be blank"
    assert flat =~ "Board invalid"
  end

  test "D-20 render remains body-only with no modal chrome" do
    fields = [
      %{name: :slug, type: :text, label: "Slug", required: true},
      %{name: :name, type: :text, label: "Name", required: true}
    ]

    serialized =
      fields
      |> test_form(title: "Create board")
      |> Form.render(theme: theme())
      |> inspect(printable_limit: :infinity, limit: :infinity)

    refute serialized =~ "border:"
    refute serialized =~ "type: :box"
    refute serialized =~ "center"
  end

  test "REQ-7 errors use theme.error.fg slot in rendered tree" do
    t = theme()
    state = test_form()
    state_with_errors = Form.set_errors(state, %{title: "required"})

    result = Form.render(state_with_errors, theme: t)
    serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

    assert serialized =~ to_string(t.error.fg),
           "Expected theme.error.fg (#{t.error.fg}) in rendered tree for error messages"

    # D-07/D-09 hygiene: no raw color atoms even with errors present
    for color <- color_names() do
      refute color_atom_leaked?(serialized, color),
             "Modal.Form leaked :#{color} atom in error-state rendered tree"
    end
  end

  test "REQ-7 modal stays open after set_errors: state is still a Form struct and handles events" do
    state = test_form()
    state_with_errors = Form.set_errors(state, %{title: "required"})

    assert %Form{} = state_with_errors

    # Should still respond to events normally (e.g., Tab advances focus)
    {new_state, _action} = Form.handle_event(%{key: :tab}, state_with_errors)
    assert %Form{} = new_state
  end

  # --- D-25 Pitfall 1: shift_tab event-shape parity ---

  describe "shift+tab event shapes" do
    # D-25 Pitfall 1: shift_tab event-shape parity
    # CLIHandler translates back-tab to %{key: :shift_tab} (Foglet shape).
    # Raxol native shape is %{key: :tab, shift: true}.
    # Both must route through the same back-tab branch.

    setup do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"},
        %{name: :c, type: :text, label: "C"}
      ]

      {:ok, form: test_form(fields)}
    end

    test "Raxol shape %{key: :tab, shift: true} moves focus to previous field", %{form: form} do
      # Start at 0, go to 2 (wrap), then back to 1
      {at_2, _} = Form.handle_event(%{key: :tab, shift: true}, form)
      assert at_2.focus_index == 2

      {at_1, _} = Form.handle_event(%{key: :tab, shift: true}, at_2)
      assert at_1.focus_index == 1
    end

    test "Foglet shape %{key: :shift_tab} moves focus to previous field (same as Raxol shape)", %{form: form} do
      # D-25 Pitfall 1: this event shape is translated by CLIHandler and must be handled
      {at_2, _} = Form.handle_event(%{key: :shift_tab}, form)
      assert at_2.focus_index == 2

      {at_1, _} = Form.handle_event(%{key: :shift_tab}, at_2)
      assert at_1.focus_index == 1
    end

    test "both shift_tab shapes return identical {form, nil} result shape" do
      fields = [
        %{name: :x, type: :text, label: "X"},
        %{name: :y, type: :text, label: "Y"}
      ]

      form = test_form(fields)
      {form_raxol, action_raxol} = Form.handle_event(%{key: :tab, shift: true}, form)
      {form_foglet, action_foglet} = Form.handle_event(%{key: :shift_tab}, form)

      assert form_raxol.focus_index == form_foglet.focus_index
      assert action_raxol == action_foglet
      assert action_raxol == nil
    end

    test "forward tab %{key: :tab} still advances focus (regression)" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"}
      ]

      form = test_form(fields)
      {s1, _} = Form.handle_event(%{key: :tab}, form)
      assert s1.focus_index == 1
    end

    test "forward tab %{key: :tab, shift: false} still advances focus (regression)" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"}
      ]

      form = test_form(fields)
      {s1, _} = Form.handle_event(%{key: :tab, shift: false}, form)
      assert s1.focus_index == 1
    end
  end

  # --- REQ-9: E2E fixture ---

  test "REQ-9 E2E: open form, type in fields, submit, assert typed payload" do
    fields = [
      %{name: :name, type: :text, label: "Name"},
      %{name: :count, type: :integer, label: "Count"},
      %{name: :enabled, type: :boolean, label: "Enabled", value: false}
    ]

    state = test_form(fields)

    # Type "hello" in text field, Tab to next
    text_events = Enum.map(String.codepoints("hello"), &%{key: :char, char: &1})
    # Type "7" in integer field, Tab to next
    int_events = [%{key: :char, char: "7"}]
    # Space to toggle boolean, then Enter to submit (last field)
    bool_events = [%{key: :char, char: " "}, %{key: :enter}]

    all_events =
      text_events ++
        [%{key: :tab}] ++
        int_events ++
        [%{key: :tab}] ++
        bool_events

    send_events(state, all_events)

    assert_receive {:submitted, payload}
    assert payload.name == "hello"
    assert payload.count == 7
    assert payload.enabled == true
  end
end

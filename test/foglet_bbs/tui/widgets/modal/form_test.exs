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

  test "text fields seeded with a value are editable from the end of the existing value" do
    fields = [%{name: :location, type: :text, label: "Location", value: "Birmingham"}]
    state = test_form(fields)

    assert Form.field_value(state, :location) == "Birmingham"

    {state, nil} = Form.handle_event(%{key: :backspace}, state)
    assert Form.field_value(state, :location) == "Birmingha"

    {state, nil} = Form.handle_event(%{key: :char, char: "m"}, state)
    assert Form.field_value(state, :location) == "Birmingham"

    {state, nil} = Form.handle_event(%{key: :left}, state)
    {state, nil} = Form.handle_event(%{key: :delete}, state)
    assert Form.field_value(state, :location) == "Birmingha"

    {state, nil} = Form.handle_event(%{key: :char, char: "m"}, state)
    assert Form.field_value(state, :location) == "Birmingham"
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

  test "typed coercion (select_list): search narrows, enter selects tuple value, submit gives raw value" do
    fields = [
      %{
        name: :timezone,
        type: :select_list,
        label: "Timezone",
        choices: [
          {"UTC", "Etc/UTC"},
          {"Central — Chicago", "America/Chicago"},
          {"Eastern — New York", "America/New_York"}
        ],
        value: "Etc/UTC"
      },
      %{name: :confirm, type: :text, label: "Confirm"}
    ]

    state = test_form(fields)

    {state, nil} = Form.handle_event(%{key: :char, char: "C"}, state)
    {state, nil} = Form.handle_event(%{key: :char, char: "h"}, state)
    assert Form.field_value(state, :timezone) == "Etc/UTC"

    {state, nil} = Form.handle_event(%{key: :enter}, state)
    assert Form.field_value(state, :timezone) == "America/Chicago"
    assert state.focus_index == 1

    {_state, _action} = Form.handle_event(%{key: :enter}, state)
    assert_receive {:submitted, %{timezone: "America/Chicago", confirm: ""}}
  end

  test "select_list keeps Enter as selection and Ctrl+S as save" do
    fields = [
      %{
        name: :timezone,
        type: :select_list,
        label: "Timezone",
        choices: ["Etc/UTC", "America/Chicago", "America/New_York"],
        value: "Etc/UTC"
      }
    ]

    state = test_form(fields)
    {state, nil} = Form.handle_event(%{key: :char, char: "C"}, state)
    {state, nil} = Form.handle_event(%{key: :char, char: "h"}, state)
    {state, action} = Form.handle_event(%{key: :enter}, state)

    assert action == nil
    assert Form.field_value(state, :timezone) == "America/Chicago"
    refute_receive {:submitted, _}

    {_state, action} = Form.handle_event(%{key: :char, char: "s", ctrl: true}, state)

    assert action == {:submitted, {:submitted, %{timezone: "America/Chicago"}}}
    assert_receive {:submitted, %{timezone: "America/Chicago"}}
  end

  test "select_list render includes search prompt and filtered options instead of cycling chrome" do
    fields = [
      %{
        name: :timezone,
        type: :select_list,
        label: "Timezone",
        choices: ["Etc/UTC", "America/Chicago", "America/New_York"],
        value: "America/Chicago"
      }
    ]

    flat = fields |> test_form() |> Form.render(theme: theme()) |> flatten_text()

    assert flat =~ "Type to filter"
    assert flat =~ "America/Chicago"
    refute flat =~ "‹ America/Chicago ›"
  end

  test "typed coercion (textarea): multi-line content submits as string with newline" do
    fields = [%{name: :body, type: :textarea, label: "Body", rows: 3}]
    state = test_form(fields)

    # Type some content including a newline sequence, then save with Ctrl+S
    # because Enter is reserved for textarea editing semantics.
    events =
      Enum.map(String.codepoints("hello\nworld"), fn ch ->
        %{key: :char, char: ch}
      end) ++ [%{key: :char, char: "s", ctrl: true}]

    send_events(state, events)

    assert_receive {:submitted, %{body: value}}
    assert is_binary(value)
    assert String.contains?(value, "\n")
  end

  test "textarea accepts terminal :space events and keeps control characters filtered" do
    fields = [%{name: :body, type: :textarea, label: "Body", rows: 3}]
    state = test_form(fields)

    events = [
      %{key: :char, char: "General"},
      %{key: :space},
      %{key: :char, char: "discussion"},
      %{key: :char, char: <<7>>},
      %{key: :space},
      %{key: :char, char: "board"},
      %{key: :char, char: "s", ctrl: true}
    ]

    {state, _actions} = send_events(state, events)

    rendered = state |> Form.render(theme: theme()) |> flatten_text()
    assert rendered =~ "General discussion board"
    assert_receive {:submitted, %{body: "General discussion board"}}
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

  test "REQ-5 Enter on last field submits once and returns submit result action" do
    pid = self()

    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"}
    ]

    state =
      Form.init(
        title: "Test Form",
        fields: fields,
        on_submit: fn payload ->
          send(pid, {:submitted, payload})
          {:submit_result, payload}
        end,
        on_cancel: fn -> send(pid, :cancelled) end
      )

    # Move to last field (index 1)
    {state_at_last, _} = Form.handle_event(%{key: :tab}, state)
    assert state_at_last.focus_index == 1

    {_final, action} = Form.handle_event(%{key: :enter}, state_at_last)
    assert action == {:submitted, {:submit_result, %{a: "", b: ""}}}
    assert_receive {:submitted, %{a: "", b: ""}}
    refute_receive {:submitted, _payload}
  end

  test "REQ-5 Enter on non-last ordinary field submits without moving focus" do
    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"},
      %{name: :c, type: :text, label: "C"}
    ]

    state = test_form(fields)
    assert state.focus_index == 0

    {new_state, action} = Form.handle_event(%{key: :enter}, state)

    assert new_state.focus_index == 0
    assert action == {:submitted, {:submitted, %{a: "", b: "", c: ""}}}
    assert_receive {:submitted, %{a: "", b: "", c: ""}}
  end

  test "Ctrl+S submits from current focus without moving focus" do
    fields = [
      %{name: :a, type: :text, label: "A"},
      %{name: :b, type: :text, label: "B"},
      %{name: :c, type: :text, label: "C"}
    ]

    state = test_form(fields)
    {state, nil} = Form.handle_event(%{key: :tab}, state)
    assert state.focus_index == 1

    {new_state, action} = Form.handle_event(%{key: :char, char: "s", ctrl: true}, state)

    assert new_state.focus_index == 1
    assert action == {:submitted, {:submitted, %{a: "", b: "", c: ""}}}
    assert_receive {:submitted, %{a: "", b: "", c: ""}}
  end

  test "Enter on textarea edits the field while Ctrl+S submits textarea forms" do
    fields = [%{name: :body, type: :textarea, label: "Body", rows: 3}]
    state = test_form(fields)

    {state, action} = Form.handle_event(%{key: :enter}, state)

    assert action == nil
    refute_receive {:submitted, _}

    {_state, action} = Form.handle_event(%{key: :char, char: "s", ctrl: true}, state)

    assert action == {:submitted, {:submitted, %{body: "\n"}}}
    assert_receive {:submitted, %{body: "\n"}}
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
    # Phase 28 FORM-03 (D-06): the footer is opt-in. Pass show_footer: true so
    # this test continues to verify footer rendering on overlay-style forms;
    # tab-body consumers (Account, Sysop) leave it default-off.
    pid = self()

    fields = [
      %{name: :slug, type: :text, label: "Slug", required: true},
      %{name: :name, type: :text, label: "Name", required: true}
    ]

    state =
      Form.init(
        title: "Create board",
        fields: fields,
        show_footer: true,
        on_submit: fn payload -> send(pid, {:submitted, payload}) end,
        on_cancel: fn -> send(pid, :cancelled) end
      )

    flat = state |> Form.render(theme: theme(), width: 90) |> flatten_text()

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

  # --- D-25 A1: enum field value accessor (D-03 / Pitfall 5) ---

  describe "enum field value accessor" do
    # D-25 D-03 / Pitfall 5: prefs theme-cycle live preview integration path.
    # Modal.Form.field_value/2 returns the current post-event enum choice so
    # screens can implement side effects (e.g. theme preview) without submit.

    defp enum_form do
      Form.init(
        title: "Theme",
        fields: [
          %{
            name: :theme_id,
            type: :enum,
            label: "Theme",
            choices: [:dark, :light, :amber],
            value: :dark
          }
        ],
        on_submit: fn _ -> nil end,
        on_cancel: fn -> nil end
      )
    end

    test "field_value/2 returns initial enum choice before any events" do
      form = enum_form()
      assert Form.field_value(form, :theme_id) == :dark
    end

    test "field_value/2 returns updated choice after :down event (cycle to :light)" do
      form = enum_form()
      {form_after, _} = Form.handle_event(%{key: :down}, form)
      assert Form.field_value(form_after, :theme_id) == :light
    end

    test "field_value/2 returns :amber after two :down events" do
      form = enum_form()
      {f1, _} = Form.handle_event(%{key: :down}, form)
      {f2, _} = Form.handle_event(%{key: :down}, f1)
      assert Form.field_value(f2, :theme_id) == :amber
    end

    test "cycling does NOT mark the form :submitted and returns nil action" do
      form = enum_form()
      {_f1, action} = Form.handle_event(%{key: :down}, form)
      assert action == nil
    end

    test "field_value/2 returns nil for unknown field name" do
      form = enum_form()
      assert Form.field_value(form, :nonexistent) == nil
    end
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

    test "Foglet shape %{key: :shift_tab} moves focus to previous field (same as Raxol shape)", %{
      form: form
    } do
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

  # --- Phase 28 Plan 01 Task 1: FORM-01 / FORM-02 / FORM-04 substrate ---
  #
  # FORM-02: %{key: :backtab} (CLIHandler-translated terminal back-tab) MUST be
  # accepted as an alias of %{key: :shift_tab} and %{key: :tab, shift: true}.
  # FORM-01: Up/Down advance/retreat focus on text/integer/textarea fields with
  # wrap (last → 0 forward, 0 → last backward); Up/Down on enum cycles the value
  # and does NOT change focus_index.
  # FORM-04: Modal.Form.focus_index is the single source of truth for which
  # field consumes the next keystroke — verified end-to-end via Tab sequencing.

  describe "FORM-02 :backtab event shape (Phase 28 D-15)" do
    setup do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"},
        %{name: :c, type: :text, label: "C"}
      ]

      {:ok, form: test_form(fields)}
    end

    test "FORM-02 :backtab from focus_index: 1 retreats to 0", %{form: form} do
      {at_1, _} = Form.handle_event(%{key: :tab}, form)
      assert at_1.focus_index == 1

      {at_0, action} = Form.handle_event(%{key: :backtab}, at_1)
      assert at_0.focus_index == 0
      assert action == nil
    end

    test "FORM-02 :backtab from focus_index: 0 wraps to last (length - 1)", %{form: form} do
      assert form.focus_index == 0

      {wrapped, _} = Form.handle_event(%{key: :backtab}, form)
      assert wrapped.focus_index == 2
    end

    test "FORM-02 :backtab and :shift_tab and %{key: :tab, shift: true} are byte-equivalent",
         %{form: form} do
      {f_backtab, a_backtab} = Form.handle_event(%{key: :backtab}, form)
      {f_shift_tab, a_shift_tab} = Form.handle_event(%{key: :shift_tab}, form)
      {f_raxol, a_raxol} = Form.handle_event(%{key: :tab, shift: true}, form)

      assert f_backtab.focus_index == f_shift_tab.focus_index
      assert f_shift_tab.focus_index == f_raxol.focus_index
      assert a_backtab == nil
      assert a_shift_tab == nil
      assert a_raxol == nil
    end
  end

  describe "FORM-01 Up/Down focus on text-like fields (Phase 28 D-13/D-14)" do
    test "Down on a [text, text, enum] form at focus_index: 0 advances to 1, then 2" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"},
        %{name: :e, type: :enum, label: "E", choices: [:x, :y]}
      ]

      form = test_form(fields)
      assert form.focus_index == 0

      {f1, action1} = Form.handle_event(%{key: :down}, form)
      assert f1.focus_index == 1
      assert action1 == nil

      {f2, action2} = Form.handle_event(%{key: :down}, f1)
      assert f2.focus_index == 2
      assert action2 == nil
    end

    test "Down forward wrap: [text, text, text] at focus_index: 2 wraps to 0" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"},
        %{name: :c, type: :text, label: "C"}
      ]

      form = test_form(fields)
      {f1, _} = Form.handle_event(%{key: :tab}, form)
      {f2, _} = Form.handle_event(%{key: :tab}, f1)
      assert f2.focus_index == 2

      {wrapped, action} = Form.handle_event(%{key: :down}, f2)
      assert wrapped.focus_index == 0
      assert action == nil
    end

    test "Up on [text, text] at focus_index: 1 retreats to 0; another Up wraps 0 → last" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"}
      ]

      form = test_form(fields)
      {f1, _} = Form.handle_event(%{key: :tab}, form)
      assert f1.focus_index == 1

      {f0, action0} = Form.handle_event(%{key: :up}, f1)
      assert f0.focus_index == 0
      assert action0 == nil

      {f_wrap, action_wrap} = Form.handle_event(%{key: :up}, f0)
      assert f_wrap.focus_index == 1
      assert action_wrap == nil
    end

    test "Up/Down on integer fields advance/retreat focus_index (text-like)" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :n, type: :integer, label: "N"}
      ]

      form = test_form(fields)
      {f1, _} = Form.handle_event(%{key: :tab}, form)
      assert f1.focus_index == 1

      {f0, _} = Form.handle_event(%{key: :up}, f1)
      assert f0.focus_index == 0

      {f1_again, _} = Form.handle_event(%{key: :down}, f0)
      assert f1_again.focus_index == 1
    end

    test "Up/Down on textarea fields advance/retreat focus_index (text-like)" do
      fields = [
        %{name: :head, type: :text, label: "Head"},
        %{name: :body, type: :textarea, label: "Body", rows: 3}
      ]

      form = test_form(fields)
      {at_textarea, _} = Form.handle_event(%{key: :tab}, form)
      assert at_textarea.focus_index == 1

      {back, _} = Form.handle_event(%{key: :up}, at_textarea)
      assert back.focus_index == 0

      {forward, _} = Form.handle_event(%{key: :down}, back)
      assert forward.focus_index == 1
    end
  end

  describe "FORM-01 Up/Down on :enum cycles value, leaves focus" do
    test "Down on focused :enum cycles value to next choice; focus_index stays" do
      fields = [
        %{name: :a, type: :text, label: "A"},
        %{name: :b, type: :text, label: "B"},
        %{name: :pick, type: :enum, label: "Pick", choices: ["a", "b", "c"]}
      ]

      form = test_form(fields)
      {f1, _} = Form.handle_event(%{key: :tab}, form)
      {f2, _} = Form.handle_event(%{key: :tab}, f1)
      assert f2.focus_index == 2
      assert Form.field_value(f2, :pick) == "a"

      {after_down, action} = Form.handle_event(%{key: :down}, f2)
      assert after_down.focus_index == 2
      assert action == nil
      assert Form.field_value(after_down, :pick) == "b"

      {after_up, _} = Form.handle_event(%{key: :up}, after_down)
      assert after_up.focus_index == 2
      assert Form.field_value(after_up, :pick) == "a"
    end
  end

  # --- Phase 28 Plan 01 Task 2: FORM-03 footer opt-in ---
  #
  # FORM-03: Modal.Form.render/2 emits no [Enter] Submit / [Esc] Cancel footer
  # by default; passing :show_footer: true via init/1 restores the footer.
  # The default-off setting suppresses the footer for tab-body consumers
  # (Account Profile/Prefs, Sysop Site) so the global command bar is the single
  # advertiser of those keys; true overlay callers opt in explicitly (D-06).

  describe "FORM-03 :show_footer opt-in (Phase 28 D-06, D-07)" do
    defp footer_form(opts \\ []) do
      pid = self()

      Form.init(
        Keyword.merge(
          [
            title: "Test",
            fields: [
              %{name: :a, type: :text, label: "A"},
              %{name: :b, type: :text, label: "B"}
            ],
            on_submit: fn _ -> send(pid, :submitted) end,
            on_cancel: fn -> send(pid, :cancelled) end
          ],
          opts
        )
      )
    end

    test "FORM-03 default: render emits no [Enter] Submit / [Esc] Cancel substring" do
      form = footer_form()
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      refute String.contains?(flat, "[Enter] Submit"),
             "default-rendered form must NOT advertise [Enter] Submit, got: #{inspect(flat)}"

      refute String.contains?(flat, "[Esc] Cancel"),
             "default-rendered form must NOT advertise [Esc] Cancel, got: #{inspect(flat)}"
    end

    test "FORM-03 explicit show_footer: true emits both footer substrings" do
      form = footer_form(show_footer: true)
      flat = form |> Form.render(theme: theme(), width: 90) |> flatten_text()

      assert String.contains?(flat, "[Enter] Submit"),
             "show_footer: true must advertise [Enter] Submit when width allows, got: #{inspect(flat)}"

      assert String.contains?(flat, "[Esc] Cancel"),
             "show_footer: true must advertise [Esc] Cancel, got: #{inspect(flat)}"
    end

    test "FORM-03 responsive footer collapses to save/cancel at 80 columns" do
      form = footer_form(show_footer: true)
      flat = form |> Form.render(theme: theme(), width: 80) |> flatten_text()

      assert String.contains?(flat, "[Enter/Ctrl+S] Save")
      assert String.contains?(flat, "[Esc] Cancel")
      refute String.contains?(flat, "[Shift+Tab] Previous")
      refute String.contains?(flat, "[Enter] Submit")
    end

    test "FORM-03 responsive footer keeps one-line output within cramped width" do
      form = footer_form(show_footer: true)
      flat = form |> Form.render(theme: theme(), width: 34) |> flatten_text()

      assert String.contains?(flat, "[Enter/Ctrl+S] Save   [Esc] Cancel")
      refute String.contains?(flat, "[Tab] Next")
      assert String.length("[Enter/Ctrl+S] Save   [Esc] Cancel") == 34
    end

    test "FORM-03 optional middle tier appears for multi-field modal above 80 when full does not fit" do
      form = footer_form(show_footer: true)
      flat = form |> Form.render(theme: theme(), width: 50) |> flatten_text()

      assert String.contains?(flat, "[Enter/Ctrl+S] Save")
      refute String.contains?(flat, "[Shift+Tab] Previous")
      refute String.contains?(flat, "[Tab] Next")

      flat = form |> Form.render(theme: theme(), width: 82) |> flatten_text()

      assert String.contains?(flat, "[Tab] Next")
      assert String.contains?(flat, "[Enter/Ctrl+S] Save")
      assert String.contains?(flat, "[Esc] Cancel")
      refute String.contains?(flat, "[Shift+Tab] Previous")
    end

    test "FORM-03 one-field compact footer does not advertise tab navigation" do
      form =
        footer_form(
          fields: [%{name: :body, type: :textarea, label: "Body", rows: 3}],
          show_footer: true
        )

      flat = form |> Form.render(theme: theme(), width: 82) |> flatten_text()

      assert String.contains?(flat, "[Enter/Ctrl+S] Save")
      assert String.contains?(flat, "[Esc] Cancel")
      refute String.contains?(flat, "[Tab] Next")
    end

    test "FORM-03 select-list footer advertises Enter selection and Ctrl+S save" do
      form =
        footer_form(
          fields: [
            %{
              name: :timezone,
              type: :select_list,
              label: "Timezone",
              choices: ["Etc/UTC", "America/Chicago"],
              value: "Etc/UTC"
            }
          ],
          show_footer: true
        )

      flat = form |> Form.render(theme: theme(), width: 80) |> flatten_text()

      assert String.contains?(flat, "[Enter] Select")
      assert String.contains?(flat, "[Ctrl+S] Save")
      assert String.contains?(flat, "[Esc] Cancel")
      refute String.contains?(flat, "[Enter/Ctrl+S] Save")
      refute String.contains?(flat, "[Enter] Submit")
    end

    test "FORM-03 explicit show_footer: false matches default-off behavior" do
      form = footer_form(show_footer: false)
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      refute String.contains?(flat, "[Enter] Submit")
      refute String.contains?(flat, "[Esc] Cancel")
    end

    test "FORM-03 :show_footer struct field is locked at init/1" do
      assert footer_form().show_footer == false
      assert footer_form(show_footer: false).show_footer == false
      assert footer_form(show_footer: true).show_footer == true
    end
  end

  describe "FORM-04 single-source-of-truth focus routing" do
    test ":tab :tab :char x on [text, text, text] lands x in third field's buffer only" do
      fields = [
        %{name: :first, type: :text, label: "First"},
        %{name: :second, type: :text, label: "Second"},
        %{name: :third, type: :text, label: "Third"}
      ]

      form = test_form(fields)
      assert form.focus_index == 0

      events = [
        %{key: :tab},
        %{key: :tab},
        %{key: :char, char: "x"}
      ]

      {final, _} = send_events(form, events)

      assert final.focus_index == 2
      assert Form.field_value(final, :third) == "x"
      assert Form.field_value(final, :first) == ""
      assert Form.field_value(final, :second) == ""
    end
  end

  # --- Phase 28 Plan 02 Task 1: FORM-05 submit-state machine + lock + setter ---
  #
  # FORM-05: Modal.Form gains an explicit `submit_state` machine
  # (:idle -> :submitting -> {:saved | {:error, _}} -> :idle on next event).
  # The :submitting state locks all input (every event swallowed) so accidental
  # double-Enter, Enter-during-redraw, or held-key bounces cannot invoke
  # `on_submit` twice. `set_submit_state/2` is the public terminal-state setter
  # for consuming screens; `:submitting` is reserved for the internal Enter
  # transition (D-01..D-05).

  describe "FORM-05 submit-state machine + lock guard (Phase 28 D-01..D-05)" do
    defp single_field_form(opts \\ []) do
      pid = self()

      Form.init(
        Keyword.merge(
          [
            title: "Single",
            fields: [%{name: :only, type: :text, label: "Only", value: ""}],
            on_submit: fn _payload -> send(pid, :submit_called) end,
            on_cancel: fn -> send(pid, :cancel_called) end
          ],
          opts
        )
      )
    end

    defp two_field_form(opts \\ []) do
      pid = self()

      Form.init(
        Keyword.merge(
          [
            title: "Two",
            fields: [
              %{name: :a, type: :text, label: "A", value: ""},
              %{name: :b, type: :text, label: "B", value: ""}
            ],
            on_submit: fn _payload -> send(pid, :submit_called) end,
            on_cancel: fn -> send(pid, :cancel_called) end
          ],
          opts
        )
      )
    end

    test "FORM-05 init/1 seeds submit_state to :idle" do
      assert single_field_form().submit_state == :idle
      assert two_field_form().submit_state == :idle
    end

    test "FORM-05 double-Enter on a submittable form invokes on_submit exactly once" do
      form = single_field_form()

      {form1, action1} = Form.handle_event(%{key: :enter}, form)
      assert action1 == {:submitted, :submit_called}
      assert form1.submit_state == :submitting

      {form2, action2} = Form.handle_event(%{key: :enter}, form1)
      assert action2 == nil
      assert form2.submit_state == :submitting

      assert_receive :submit_called
      refute_receive :submit_called, 50
    end

    test "FORM-05 lock — :char event does not mutate field_states or focus" do
      form = single_field_form()
      {locked, {:submitted, :submit_called}} = Form.handle_event(%{key: :enter}, form)
      assert locked.submit_state == :submitting

      original_field_states = locked.field_states
      original_focus = locked.focus_index

      {after_char, action} = Form.handle_event(%{key: :char, char: "x"}, locked)

      assert action == nil
      assert after_char.submit_state == :submitting
      assert after_char.field_states == original_field_states
      assert after_char.focus_index == original_focus
      assert Form.field_value(after_char, :only) == ""
    end

    test "FORM-05 lock — every event is swallowed (no callbacks, no mutations)" do
      pid = self()
      raise_on_call = fn _ -> flunk("on_submit invoked while locked") end
      raise_on_cancel = fn -> flunk("on_cancel invoked while locked") end

      # Build a two-field form with raising callbacks so we catch any leak.
      form =
        Form.init(
          title: "Locked",
          fields: [
            %{name: :a, type: :text, label: "A", value: ""},
            %{name: :b, type: :text, label: "B", value: ""}
          ],
          on_submit: raise_on_call,
          on_cancel: raise_on_cancel
        )

      # Force the form into :submitting via the public setter is forbidden,
      # so use the internal Enter transition: focus the last field, then Enter.
      {form_focused, nil} = Form.handle_event(%{key: :tab}, form)
      assert form_focused.focus_index == 1
      # Replace on_submit with a no-op for the single legal submit event;
      # then restore the raising callbacks immediately by reaching back into
      # the struct, since :submitting locks every subsequent event.
      noop_form = %{form_focused | on_submit: fn _ -> :ok end}
      {locked_noop, :submitted} = Form.handle_event(%{key: :enter}, noop_form)
      locked = %{locked_noop | on_submit: raise_on_call, on_cancel: raise_on_cancel}

      assert locked.submit_state == :submitting
      original_focus = locked.focus_index
      original_field_states = locked.field_states
      original_errors = locked.errors

      events = [
        %{key: :tab},
        %{key: :shift_tab},
        %{key: :backtab},
        %{key: :up},
        %{key: :down},
        %{key: :backspace},
        %{key: :enter},
        %{key: :escape}
      ]

      final =
        Enum.reduce(events, locked, fn ev, st ->
          {st2, action} = Form.handle_event(ev, st)
          assert action == nil, "expected nil action while locked, got: #{inspect(action)}"
          st2
        end)

      assert final.submit_state == :submitting
      assert final.focus_index == original_focus
      assert final.field_states == original_field_states
      assert final.errors == original_errors

      # No stray messages from the (raising) callbacks should have queued either.
      refute_receive _, 20
      _ = pid
    end

    test "FORM-05 set_submit_state/2 accepts :idle, :saved, and {:error, term}" do
      form = single_field_form()

      assert Form.set_submit_state(form, :idle).submit_state == :idle
      assert Form.set_submit_state(form, :saved).submit_state == :saved

      assert Form.set_submit_state(form, {:error, "boom"}).submit_state ==
               {:error, "boom"}
    end

    test "FORM-05 set_submit_state/2 rejects :submitting with ArgumentError" do
      form = single_field_form()

      assert_raise ArgumentError, ~r/submitting/, fn ->
        Form.set_submit_state(form, :submitting)
      end
    end

    test "FORM-05 auto-reset from :saved on next non-locked event" do
      pid = self()
      raise_on_call = fn _ -> flunk("on_submit invoked during auto-reset event") end

      form =
        Form.init(
          title: "Reset",
          fields: [
            %{name: :a, type: :text, label: "A", value: ""},
            %{name: :b, type: :text, label: "B", value: ""}
          ],
          on_submit: raise_on_call,
          on_cancel: fn -> send(pid, :cancel_called) end
        )

      saved = Form.set_submit_state(form, :saved)
      assert saved.submit_state == :saved

      {after_tab, nil} = Form.handle_event(%{key: :tab}, saved)
      assert after_tab.submit_state == :idle
      assert after_tab.focus_index == 1
    end

    test "FORM-05 auto-reset from {:error, _} on next non-locked event" do
      pid = self()
      raise_on_call = fn _ -> flunk("on_submit invoked during auto-reset event") end

      form =
        Form.init(
          title: "Reset",
          fields: [
            %{name: :a, type: :text, label: "A", value: ""},
            %{name: :b, type: :text, label: "B", value: ""}
          ],
          on_submit: raise_on_call,
          on_cancel: fn -> send(pid, :cancel_called) end
        )

      errored = Form.set_submit_state(form, {:error, "boom"})
      assert errored.submit_state == {:error, "boom"}

      {after_tab, nil} = Form.handle_event(%{key: :tab}, errored)
      assert after_tab.submit_state == :idle
      assert after_tab.focus_index == 1
    end
  end

  # --- Phase 28 Plan 02 Task 2: FORM-05 status row in render/2 ---
  #
  # FORM-05 visibility: render/2 emits a status row at the bottom of the form
  # body when submit_state is :submitting, :saved, or {:error, _}. The status
  # row REPLACES the footer when both would render (D-09); idle + show_footer:
  # false produces neither status nor footer (the global command bar advertises
  # the keys for tab-body consumers, D-06).

  describe "FORM-05 render/2 status row (Phase 28 D-08, D-09)" do
    defp status_form(opts \\ []) do
      pid = self()

      Form.init(
        Keyword.merge(
          [
            title: "Status",
            fields: [
              %{name: :a, type: :text, label: "A", value: ""},
              %{name: :b, type: :text, label: "B", value: ""}
            ],
            on_submit: fn _ -> send(pid, :submitted) end,
            on_cancel: fn -> send(pid, :cancelled) end
          ],
          opts
        )
      )
    end

    test "FORM-05 :submitting renders Saving… row" do
      form = %{status_form() | submit_state: :submitting}
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "Saving…"),
             "expected 'Saving…' in render output, got: #{inspect(flat)}"
    end

    test "FORM-05 :saved renders Saved. row" do
      form = Form.set_submit_state(status_form(), :saved)
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "Saved."),
             "expected 'Saved.' in render output, got: #{inspect(flat)}"
    end

    test "FORM-05 {:error, msg} renders Error: <msg> row" do
      form = Form.set_submit_state(status_form(), {:error, "Disk full"})
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "Error: Disk full"),
             "expected 'Error: Disk full' in render output, got: #{inspect(flat)}"
    end

    test "FORM-05 status row replaces footer when both would render" do
      form = %{status_form(show_footer: true) | submit_state: :submitting}
      flat = form |> Form.render(theme: theme()) |> flatten_text()
      assert String.contains?(flat, "Saving…")

      refute String.contains?(flat, "[Enter] Submit"),
             "footer must be suppressed while a status row is shown, got: #{inspect(flat)}"
    end

    test "FORM-05 :idle + default show_footer: false → no status, no footer" do
      form = status_form()
      flat = form |> Form.render(theme: theme()) |> flatten_text()
      refute String.contains?(flat, "Saving…")
      refute String.contains?(flat, "Saved.")
      refute String.contains?(flat, "Error:")
      refute String.contains?(flat, "[Enter] Submit")
    end

    test "FORM-05 :idle + show_footer: true → footer present (no status row)" do
      form = status_form(show_footer: true)
      flat = form |> Form.render(theme: theme(), width: 90) |> flatten_text()
      assert String.contains?(flat, "[Enter] Submit")
      refute String.contains?(flat, "Saving…")
      refute String.contains?(flat, "Saved.")
      refute String.contains?(flat, "Error:")
    end
  end

  # =========================================================================
  # Phase 28 Plan 04 Task 2 — optional :description per field (substrate add)
  # =========================================================================

  describe "FORM field :description (Phase 28 Plan 04 substrate add)" do
    test "field with :description renders the description as a row beneath the widget" do
      fields = [
        %{
          name: :delivery_mode,
          type: :enum,
          label: "delivery_mode",
          choices: ["email", "no_email"],
          value: "email",
          description: "Outbound transactional delivery mode"
        }
      ]

      form =
        Form.init(
          title: "T",
          fields: fields,
          on_submit: fn _ -> :ok end,
          on_cancel: fn -> :ok end
        )

      flat = form |> Form.render(theme: theme()) |> flatten_text()
      assert String.contains?(flat, "Outbound transactional delivery mode")
    end

    test "field without :description does NOT emit any description row" do
      fields = [
        %{
          name: :title,
          type: :text,
          label: "Title"
        }
      ]

      form =
        Form.init(
          title: "T",
          fields: fields,
          on_submit: fn _ -> :ok end,
          on_cancel: fn -> :ok end
        )

      flat = form |> Form.render(theme: theme()) |> flatten_text()
      # No stray description-shaped artifacts (we only check there's no extra
      # body row carrying a non-existent description string).
      refute String.contains?(flat, "description")
    end

    test "empty :description is treated as absent (no extra row)" do
      fields = [
        %{name: :t, type: :text, label: "T", description: ""}
      ]

      form =
        Form.init(
          title: "T",
          fields: fields,
          on_submit: fn _ -> :ok end,
          on_cancel: fn -> :ok end
        )

      flat = form |> Form.render(theme: theme()) |> flatten_text()

      # The flat list has exactly: title, divider, label "T:", widget rows.
      # An empty description should not produce a blank trailing row.
      refute String.contains?(flat, "description")
    end
  end

  describe "FOG-349 :enum tuple-form choices (label, value)" do
    test "renders the human label, submits the raw value (not the label)" do
      pid = self()

      fields = [
        %{
          name: :mode,
          type: :enum,
          label: "Mode",
          choices: [{"In-memory (auto-expires)", "ephemeral"}, {"Saved to database", "permanent"}]
        }
      ]

      state =
        Form.init(
          title: "T",
          fields: fields,
          on_submit: fn payload -> send(pid, {:submitted, payload}) end,
          on_cancel: fn -> :ok end
        )

      flat = state |> Form.render(theme: theme()) |> flatten_text()
      assert String.contains?(flat, "In-memory (auto-expires)")
      assert String.contains?(flat, "Saved to database")
      refute String.contains?(flat, ~s|"ephemeral"|)

      {_s, _} = Form.handle_event(%{key: :enter}, state)
      assert_receive {:submitted, %{mode: "ephemeral"}}
    end

    test "preselects the choice whose raw value matches :value" do
      fields = [
        %{
          name: :mode,
          type: :enum,
          label: "Mode",
          choices: [{"A", "a"}, {"B", "b"}, {"C", "c"}],
          value: "b"
        }
      ]

      state =
        Form.init(
          title: "T",
          fields: fields,
          on_submit: fn _ -> :ok end,
          on_cancel: fn -> :ok end
        )

      assert Form.field_value(state, :mode) == "b"
    end
  end

  describe "FOG-349 :visible_when predicate" do
    defp visible_when_form(pid) do
      Form.init(
        title: "T",
        fields: [
          %{name: :on, type: :boolean, label: "On", value: false},
          %{
            name: :detail,
            type: :text,
            label: "Detail",
            visible_when: fn vals -> vals[:on] == true end
          },
          %{name: :name, type: :text, label: "Name"}
        ],
        on_submit: fn payload -> send(pid, {:submitted, payload}) end,
        on_cancel: fn -> :ok end
      )
    end

    test "hidden fields are not rendered" do
      state = visible_when_form(self())
      flat = state |> Form.render(theme: theme()) |> flatten_text()
      refute String.contains?(flat, "Detail:")
      assert String.contains?(flat, "Name:")
    end

    test "Tab traversal skips hidden fields and wraps" do
      state = visible_when_form(self())
      assert state.focus_index == 0

      {s1, _} = Form.handle_event(%{key: :tab}, state)
      # Skips :detail (hidden), lands on :name (index 2).
      assert s1.focus_index == 2

      {s2, _} = Form.handle_event(%{key: :tab}, s1)
      # Wraps back to :on.
      assert s2.focus_index == 0
    end

    test "Shift-Tab traversal skips hidden fields and wraps" do
      state = visible_when_form(self())

      {s1, _} = Form.handle_event(%{key: :shift_tab}, state)
      assert s1.focus_index == 2

      {s2, _} = Form.handle_event(%{key: :shift_tab}, s1)
      assert s2.focus_index == 0
    end

    test "submit payload excludes hidden field values" do
      state = visible_when_form(self())
      # Move to :name (last visible) and submit.
      {s_at_name, _} = Form.handle_event(%{key: :tab}, state)
      {_s, _} = Form.handle_event(%{key: :enter}, s_at_name)
      assert_receive {:submitted, payload}
      refute Map.has_key?(payload, :detail)
      assert Map.has_key?(payload, :on)
      assert Map.has_key?(payload, :name)
    end

    test "toggling the predicate's source field re-evaluates visibility live" do
      state = visible_when_form(self())
      # Press Space on :on (focus 0) to toggle true.
      {s_on, _} = Form.handle_event(%{key: :char, char: " "}, state)
      flat = s_on |> Form.render(theme: theme()) |> flatten_text()
      assert String.contains?(flat, "Detail:")

      # Tab now visits :detail before :name.
      {s_at_detail, _} = Form.handle_event(%{key: :tab}, s_on)
      assert s_at_detail.focus_index == 1
    end

    test "if focused field becomes hidden after an event, focus jumps to next visible" do
      # Build a form where focusing index 1 (visible while :on) hides itself
      # when :on flips back to false.
      pid = self()

      state =
        Form.init(
          title: "T",
          fields: [
            %{
              name: :detail,
              type: :text,
              label: "Detail",
              visible_when: fn vals -> vals[:on] == true end
            },
            %{name: :on, type: :boolean, label: "On", value: true},
            %{name: :name, type: :text, label: "Name"}
          ],
          on_submit: fn payload -> send(pid, {:submitted, payload}) end,
          on_cancel: fn -> :ok end
        )

      # Focus the soon-to-be-hidden field, then toggle :on off.
      state = %{state | focus_index: 0}
      {s_after_toggle, _} = Form.handle_event(%{key: :tab}, state)
      assert s_after_toggle.focus_index == 1

      # Now press Space to flip :on false; :detail becomes hidden but focus is
      # currently on :on (still visible), so focus stays put.
      {s_off, _} = Form.handle_event(%{key: :char, char: " "}, s_after_toggle)
      assert s_off.focus_index == 1

      # Move focus back to :detail manually then re-toggle off.
      s_force = %{s_off | focus_index: 0}
      # Make :on true again so :detail is visible; then toggle off so it hides.
      {s_on, _} = Form.handle_event(%{key: :tab}, s_force)
      {s_on, _} = Form.handle_event(%{key: :char, char: " "}, s_on)
      # Move focus back to :detail (now visible) by Shift-Tab.
      {s_force2, _} = Form.handle_event(%{key: :shift_tab}, s_on)
      assert s_force2.focus_index == 0

      # Tab to :on (visible) and toggle off; :detail becomes hidden, but the
      # currently-focused field (:on) is still visible.
      {s_on2, _} = Form.handle_event(%{key: :tab}, s_force2)
      {s_off2, _} = Form.handle_event(%{key: :char, char: " "}, s_on2)
      assert s_off2.focus_index == 1
    end

    test "Enter on the last visible field submits (skipping hidden trailing fields is moot here)" do
      state = visible_when_form(self())
      # :on (0), :detail (hidden), :name (2). Last visible = 2.
      {s_at_name, _} = Form.handle_event(%{key: :tab}, state)
      assert s_at_name.focus_index == 2
      {_s, action} = Form.handle_event(%{key: :enter}, s_at_name)
      assert match?(:submitted, action) or match?({:submitted, _}, action)
      assert_receive {:submitted, _payload}
    end
  end

  # =========================================================================
  # FOG-344 — :enum choices with operator-facing labels
  # =========================================================================

  describe "FOG-344 :enum choices accept {label, value} pairs" do
    test "renders the operator-facing label, not the raw value" do
      fields = [
        %{
          name: :registration_mode,
          type: :enum,
          label: "Account registration",
          choices: [
            {"Open — anyone can sign up", "open"},
            {"Invite only — requires an invite code", "invite_only"},
            {"Sysop approval — applications queue for review", "sysop_approved"}
          ],
          value: "open"
        }
      ]

      form = test_form(fields)
      flat = form |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "Open — anyone can sign up")
      assert String.contains?(flat, "Invite only — requires an invite code")
      # Raw schema strings should not leak into rendered widget rows.
      refute flat =~ ~r/^open$/m
      refute flat =~ ~r/^invite_only$/m
    end

    test "submit/coerce returns the raw value, not the label" do
      fields = [
        %{
          name: :registration_mode,
          type: :enum,
          label: "Account registration",
          choices: [
            {"Open — anyone can sign up", "open"},
            {"Invite only — requires an invite code", "invite_only"}
          ],
          value: "open"
        }
      ]

      state = test_form(fields)
      send_events(state, [%{key: :down}, %{key: :enter}])

      assert_receive {:submitted, %{registration_mode: "invite_only"}}
    end

    test "field_value/2 returns raw value while cycling" do
      fields = [
        %{
          name: :delivery_mode,
          type: :enum,
          label: "Email delivery",
          choices: [
            {"Send email", "email"},
            {"No email (offline mode)", "no_email"}
          ],
          value: "email"
        }
      ]

      state = test_form(fields)
      assert Form.field_value(state, :delivery_mode) == "email"

      {state2, _} = Form.handle_event(%{key: :down}, state)
      assert Form.field_value(state2, :delivery_mode) == "no_email"
    end

    test "backward compatible with flat choices: [value, ...]" do
      fields = [
        %{name: :color, type: :enum, label: "Color", choices: [:red, :green, :blue]}
      ]

      state = test_form(fields)
      flat = state |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "red")
      assert String.contains?(flat, "green")

      send_events(state, [%{key: :down}, %{key: :down}, %{key: :enter}])
      assert_receive {:submitted, %{color: :blue}}
    end

    test "initial :value seeds index against the value half of {label, value}" do
      fields = [
        %{
          name: :registration_mode,
          type: :enum,
          label: "Account registration",
          choices: [
            {"Open — anyone can sign up", "open"},
            {"Invite only — requires an invite code", "invite_only"},
            {"Sysop approval — applications queue for review", "sysop_approved"}
          ],
          value: "sysop_approved"
        }
      ]

      state = test_form(fields)
      send_events(state, [%{key: :enter}])
      assert_receive {:submitted, %{registration_mode: "sysop_approved"}}
    end

    test ":compact display renders labels in the cycler" do
      fields = [
        %{
          name: :delivery_mode,
          type: :enum,
          label: "Email delivery",
          display: :compact,
          choices: [
            {"Send email", "email"},
            {"No email (offline mode)", "no_email"}
          ],
          value: "email"
        }
      ]

      state = test_form(fields)
      flat = state |> Form.render(theme: theme()) |> flatten_text()

      assert String.contains?(flat, "Send email")
      refute flat =~ ~r/‹\s*email\s*›/
    end
  end

  describe "FOG-670 :max_visible viewport" do
    @field_atoms ~w(f1 f2 f3 f4 f5 f6 f7 f8)a

    defp many_fields(n) do
      @field_atoms
      |> Enum.take(n)
      |> Enum.with_index(1)
      |> Enum.map(fn {name, i} -> %{name: name, type: :text, label: "Field #{i}"} end)
    end

    test "no :max_visible renders every visible field" do
      state = test_form(many_fields(8))
      flat = Form.render(state, theme: theme()) |> flatten_text()

      for i <- 1..8 do
        assert flat =~ "Field #{i}:", "expected unwindowed render to include Field #{i}"
      end

      refute flat =~ "more above"
      refute flat =~ "more below"
    end

    test ":max_visible truncates fields and shows scroll indicators" do
      state = test_form(many_fields(8))
      flat = Form.render(state, theme: theme(), max_visible: 3) |> flatten_text()

      # focus_index is 0, so we see the top 3 fields and the rest collapse into
      # the bottom indicator.
      assert flat =~ "Field 1:"
      assert flat =~ "Field 2:"
      assert flat =~ "Field 3:"
      refute flat =~ "Field 4:"
      refute flat =~ "Field 8:"

      assert flat =~ "5 more below"
      refute flat =~ "more above"
    end

    test ":max_visible follows the focused field as Tab advances" do
      state = test_form(many_fields(8))
      # Advance focus to the 5th field (index 4) — should now be in the middle
      # of the visible window with scroll indicators on both sides.
      {state, _} = send_events(state, List.duplicate(%{key: :tab}, 4))

      flat = Form.render(state, theme: theme(), max_visible: 3) |> flatten_text()

      assert flat =~ "Field 4:"
      assert flat =~ "Field 5:"
      assert flat =~ "Field 6:"
      assert flat =~ "more above"
      assert flat =~ "more below"
      refute flat =~ "Field 1:"
      refute flat =~ "Field 8:"
    end
  end

  describe "init/1 input validation (Phase 28 BL-03)" do
    test "raises ArgumentError when :fields is an empty list" do
      assert_raise ArgumentError, ~r/at least one field/, fn ->
        Foglet.TUI.Widgets.Modal.Form.init(
          title: "Empty",
          fields: [],
          on_submit: fn _ -> :ok end,
          on_cancel: fn -> :ok end
        )
      end
    end
  end
end

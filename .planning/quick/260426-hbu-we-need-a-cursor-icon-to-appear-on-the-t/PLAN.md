---
status: complete
created: 2026-04-26
quick_id: 260426-hbu
slug: we-need-a-cursor-icon-to-appear-on-the-t
---

Add a visible cursor icon to active single-line text inputs.

Research:
- `Foglet.TUI.Widgets.Input.TextInput` is the shared single-line facade over
  Raxol's input component.
- Raxol tracks focus internally, but Foglet screens already own active-field
  state and currently pass no focused render option into the shared widget.
- Existing widget patterns use theme-routed focus glyphs such as `▌` and `▸`.

Plan:
1. Add a focused render option to `Input.TextInput` that shows a cursor marker
   before active inputs.
2. Pass the focused option from login, register, new-thread title, and modal
   form text/integer fields.
3. Add focused/unfocused widget tests and run targeted validation.

Result:
- Implemented in commit `9a9fedc`.

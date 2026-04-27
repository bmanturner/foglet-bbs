# Phase 28: modal-form-substrate - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or
> execution agents. Decisions captured in CONTEXT.md — this log
> preserves the analysis.

**Date:** 2026-04-27
**Phase:** 28-modal-form-substrate
**Mode:** assumptions
**Areas analyzed:** Submit-state machine, Footer opt-in, In-flight
status row, Honest Esc, Up/Down focus, `:backtab`, Single-source focus,
SiteForm migration

## Assumptions Presented

### Submit-State Machine
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `Modal.Form.set_submit_state/2`; `:submitting` reserved for internal Enter clause | Likely | form.ex existing surface (`field_value/2`, `set_errors/2`); SPEC REQ-5 wording |
| `:saved` and `{:error, _}` auto-reset to `:idle` on next user event | Likely | SPEC REQ-5: "`:saved` and `:error` accept input again"; existing status_message clear-on-overwrite convention |
| First-clause guard swallows all events while `:submitting` | Likely | SPEC constraint enumerates Tab/Shift+Tab/`:backtab`/Up/Down/char/backspace/Enter/Esc; first-clause guard is simplest expression |

### Footer Opt-In
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `:show_footer` boolean on `init/1`, default `false` | Confident | form.ex:83-96 init/1 takes `:title`/`:fields`/`:on_submit`/`:on_cancel`; render runs every redraw |
| App.render_modal_overlay/2 opts in at form construction | Confident | app.ex:187, 197 single overlay caller |

### In-Flight Status Row
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `Saving…` row replaces footer when `submit_state == :submitting`; `Saved.` for one cycle on `:saved`; `Error: <msg>` on `{:error, _}` | Likely | SPEC REQ-5 "renders a visible 'Saving…' (or equivalent) status row in place of/alongside the Modal.Form footer hint"; layout math at 64×22 |

### Honest Esc — No Flash (CORRECTED)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Modal.Form does not own the flash timer; consuming screens set status_message | Likely | ProfileForm pattern at profile_form.ex:52-53; D-14 widget contract |
| SiteForm gains a `status_message` field for "Changes discarded." flash | Likely | Account State already has the field; SPEC REQ-6 acceptance criterion (b) |

### Up/Down Focus Movement
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `:up`/`:down` clauses inspect focused field type; enum falls through to dispatch_to_field | Confident | form.ex:280-289 enum dispatch already matches `%{key: :down}`/`%{key: :up}` |

### `:backtab` Clause
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `:backtab` clause adjacent to `:shift_tab` (form.ex:119), identical body | Confident | form.ex:107-123 deliberate clause-adjacency convention |

### Single-Source-of-Truth Focus
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| No leaf widget code changes; verified by grep test | Confident | TextInput defstruct at text_input.ex:42 has no focus field; RadioGroup/Checkbox have no defstruct |

### SiteForm Migration
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| SiteForm becomes thin wrapper analogous to ProfileForm/PrefsForm; sibling state.ex | Likely | SPEC In-scope: "structurally analogous to ProfileForm/PrefsForm" |
| Bespoke "▸ key: value" renderer dropped in favor of Modal.Form rendering | Likely | site_form.ex moduledoc calls bespoke render a "D-19 fallback path"; substrate now removes the need |
| Ctrl+S submit shortcut preserved at screen-level | Likely | site_form.ex:85; operator muscle memory |
| validate_delivery_verification_pair runs inside on_submit before Config.put | Likely | site_form.ex:213-240 existing flow |
| visible_keys filter runs in screen wrapper before constructing Modal.Form fields | Likely | site_form.ex:316 "re-init on change" comment |

## Corrections Made

### Honest Esc — flash row removal

- **Original assumptions (D-A5/D-A6):** `Modal.Form` fires `on_cancel`;
  consuming screens reseed drafts AND set a `status_message`
  ("Changes discarded.") that renders as an inline flash row. SiteForm
  gains a `status_message` field. ProfileForm's existing flash copy
  stays. Implements SPEC FORM-06 acceptance criterion (b).
- **User correction:** Remove the "Changes discarded." display
  entirely. Field values reverting on the next render is the sufficient
  visible signal that Esc did something.
- **Reason:** The user determined the explicit copy row adds chrome
  noise on Account screens and conflicts with the milestone's
  duplicate-footer cleanup intent. The field re-paint is itself the
  honest visible signal.
- **Conflict flagged:** SPEC FORM-06 acceptance criterion (b)
  ("a status row containing the discard copy is present in the next
  render") was reviewed against this correction. The user accepted
  that this requires a SPEC amendment and chose to drop the flash
  anyway. Acceptance criterion (a) — "the field's underlying draft
  equals the saved value" — stands.
- **Downstream impact:**
  - D-10: Modal.Form drops any flash-row mechanism on Esc.
  - D-11: ProfileForm and PrefsForm have their existing
    `status_message: "...discarded."` removed; tests asserting that
    copy update to assert field reversion only.
  - D-12: SiteForm does not gain a `status_message` field.
  - SPEC FORM-06 should be amended when next touched. Planner does
    not block on the SPEC text update.

## Auto-Resolved

Not applicable — no `--auto` flag in this run.

## External Research

Not performed — the SPEC and the in-context source files (form.ex,
profile_form.ex, prefs_form.ex, site_form.ex, submit_stash.ex,
app.ex, text_input.ex) provided sufficient evidence for every
assumption.

# Phase 30: account-workflow - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-27
**Phase:** 30-account-workflow
**Mode:** assumptions
**Areas analyzed:** Paste capture (ACCT-05); SelectList for timezone (ACCT-04); Modal.Form internal-title suppression (ACCT-02); Saved flash render & clear (ACCT-01); time_format/theme commit gap (ACCT-03); Test strategy & UAT artifact

## Assumptions Presented

### Paste capture (ACCT-05)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Migrate SSH-keys add to Modal.Form `:textarea`, normalize via `String.replace(value, ~r/\s+/, " ") \|> String.trim/1` on submit; do NOT add bracketed-paste detection in this phase. | Likely | `widgets/modal/form.ex:251-265,295-325,391-397` (textarea accumulates `\n`); `screens/account/ssh_keys_actions.ex:86-96` (today's `:enter` triggers submit prematurely); `accounts/ssh_key.ex:54` (existing trim doesn't collapse internal whitespace) |

### SelectList for timezone (ACCT-04)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add Modal.Form field type `:select_list` wrapping `SmartList` with `enable_search: true`; seed options from `Tzdata.zone_list/0`. No new top-level widget, no new dep. | Likely | `widgets/list/smart_list.ex:46-51,81-106,117-132`; `widgets/modal/form.ex:267-325`; `mix.lock:71-73` (Tzdata transitive via Timex 3.7.13); `accounts/user.ex:265-272` (existing IANA validation precedent) |

### Modal.Form internal-title suppression (ACCT-02)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `:internal_title?` boolean opt to `Modal.Form.init/1` (default `true`); ProfileForm and PrefsForm pass `false`; overlays keep the default. | Confident | `widgets/modal/form.ex:191-192` (title row + divider); `widgets/modal/form.ex:83-96` (`init/1` already absorbs opts via `Keyword.get`) |

### Saved flash render & clear (ACCT-01)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Render `state.status_message` as `[Saved]` row inside ProfileForm/PrefsForm; clear via new `status_message_seen?` boolean on first true input event. No timer. Re-entry persistence verified by manual UAT. | Likely | `profile_form.ex:48`, `prefs_form.ex:63`, `app.ex:1229` (status set but never rendered); `app.ex:1185` (current_user refresh on save); `screens/account/state.ex:50-68` (state struct extension point) |

### time_format / theme commit gap (ACCT-03)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Phase 30 owns the test + flash only; substrate fix is Phase 28 FORM-04/05. `prefs_form.ex:51-58` correctly forwards enum values; `app.ex:902-908` re-keys into preferences map; `User.profile_changeset/2` casts both. | Likely | `widgets/modal/form.ex:133-144` (Enter submits only when `focus_index == last_idx` — likely user-perceived "nothing happened"); `lib/foglet_bbs/tui/screens/account/prefs_form.ex:51-58`; `lib/foglet_bbs/tui/app.ex:902-908`; `lib/foglet_bbs/accounts/user.ex:104-113` |

### Test strategy & UAT artifact
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Three new test files (`prefs_form_test.exs`, `ssh_keys_paste_test.exs`, `form_internal_title_test.exs`) plus `30-HUMAN-UAT.md`. | Confident | Phase 27 set the UAT-artifact precedent at `.planning/phases/27-cursor-breadcrumb-polish/27-HUMAN-UAT.md`; existing `account_test.exs:566-580` shows `Account.handle_key/2` test pattern |

## Corrections Made

### Paste capture (ACCT-05) — overlay vs inline
- **Original assumption:** "Migrate the SSH-keys add form to a Modal.Form-backed module (mirroring ProfileForm/PrefsForm)" — implied an inline tab-body Modal.Form, the same shape ProfileForm and PrefsForm use.
- **User correction:** "If you're gonna use Modal.Form for adding an ssh key it has to be the overlay mode that is activated by pressing the appropriate key on the ssh keys tab."
- **Locked decision (D-01):** Pressing `a`/`A` on the SSH KEYS list dispatches `{:show_modal, %Foglet.TUI.Modal{type: :form, title: "Add SSH Key", message: %ModalForm{...}}}` instead of switching `SSHKeysState.mode` to `:add`. The hand-rolled add form is removed.
- **Reason:** Mirrors existing overlay precedent (`app.ex:546` Post Oneliner, `app.ex:606` Hide Oneliner) and keeps the SSH-keys list rendering intact when the add flow opens.
- **Cascade effect:** ACCT-02 internal-title suppression no longer applies to the SSH-keys form (it's an overlay, not a tabbed-inline form); the overlay legitimately keeps a "Add SSH Key" title. ProfileForm and PrefsForm remain the only Phase 30 callers of `internal_title?: false`. Locked in D-07.

## External Research

Three items flagged for the planner / phase-researcher rather than resolved in discuss:

1. **Raxol `IOAdapter.parse_input/1` paste behavior** — the vendored fork references `Raxol.Terminal.ANSI.InputParser.parse/1` (`vendor/raxol/lib/raxol/ssh/io_adapter.ex:34`) but the parser module isn't in-tree (loaded from a hex dep). Whether multi-line SSH paste arrives as a `:char` stream with embedded `\n`, a single `:paste` event, or with newlines silently dropped is not answerable from the codebase. Empirical test against a live SSH session is required. Mitigated by: automated test feeds the multi-line key as a codepoint stream through Modal.Form directly; manual UAT verifies real SSH paste at 64×22.
2. **Raxol `SelectList` filter semantics** — prefix vs substring vs fuzzy match is undocumented in the vendored source. SPEC ACCT-04 requires case-insensitive substring match. Mitigation: a 5-minute IEx probe at the start of implementation; if Raxol defaults to prefix, add a Foglet-side `filtered_options` override.
3. **`Tzdata.zone_list/0` runtime availability** — transitive via Timex 3.7.13 but no current production caller in `lib/`. A 5-minute IEx probe at implementation start should confirm `Tzdata.zone_list/0` returns ~600 IANA strings without requiring `:tzdata` to be added to `:extra_applications`.

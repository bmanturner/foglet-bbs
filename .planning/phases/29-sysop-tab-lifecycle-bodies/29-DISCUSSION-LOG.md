# Phase 29: sysop-tab-lifecycle-bodies - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-27
**Phase:** 29-sysop-tab-lifecycle-bodies
**Mode:** assumptions
**Areas analyzed:** Lifecycle vehicle wiring, Tab-switch trigger location, Tagged enum representation, Per-row valid-status predicate location, Loading/error/forbidden copy + retry scope, Sysop Site Esc discard row (SPEC vs Phase 28 conflict), Saved confirmation row, USERS from→to copy + INVITES focus, 1-N Jump consistency, Site field description rewrites

## Assumptions Presented

### Lifecycle vehicle wiring
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Sysop returns dispatch tuples `{:load_sysop_*}` in `commands`; App.do_update/2 wraps them in `Foglet.TUI.Command.task/2`; result tuples `{:sysop_*_loaded, _}` route back via App helpers `put_sysop_loading|loaded|error`. | Confident | `app.ex:507-527` (moderation twin), `app.ex:911-917, 942-952, 1310-1329`, AGENTS.md sanctioned wrapper rule |

### Tab-switch trigger location
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Trigger fires from inside `Sysop.handle_key/2` tab-changed branch and a first-entry guard inside `init/1`. SITE stays sync; INVITES keeps existing path. | Likely | `sysop.ex:170-192, 220-228`; SITE seed at `site_form.ex:51-63` |

### Tagged enum representation
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Bare tagged values (`:not_loaded | :loading | {:loaded, struct} | {:error, reason}`) directly in existing State slots. Existing submodule structs become the third element. No envelope module. | Likely | `state.ex:27-44`; existing submodule struct shapes; AGENTS.md no-nil-leakage rule |

### Per-row valid-status predicate
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Expose `Foglet.Accounts.valid_status_transitions/1` derived from existing `permit_status_transition/2` clauses; `UsersView` consults it for footer/keybind gating. | Likely | `accounts.ex:187-191`; AGENTS.md context boundary rule |

### Loading/error copy + `[R] Retry` scope
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Loading copy `"Loading…"` (theme `dim.fg`); generic error `"Could not load <tab>. Press R to retry."` (theme `error.fg`); `:forbidden` `"Insufficient role to view this tab."` (theme `warning.fg`). `[R] Retry` advertised only when the *active* tab is in `{:error, reason ≠ :forbidden}`. | Unclear | `invites_surface.ex:61`; `moderation.ex:218`; `sysop.ex:71`; SPEC SYSOP-02 acceptance written from active-tab POV |

### Sysop Site Esc discard row — SPEC vs Phase 28 conflict
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| **Honor Phase 28 D-10/D-12: NO discard status row.** Field reversion is the visible signal. SPEC SYSOP-03 acceptance criterion ("the next render contains a discard status row") is amended; SiteForm gains no `status_message` field. | Unclear (genuine spec conflict) | `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` D-10, D-12; Phase 28 Specifics section explicitly authorises proceeding with D-12 over SPEC text |

### Saved confirmation row
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Reuse Phase 28 D-08's `Saved.` row (Modal.Form emits it on `submit_state == :saved`). No Sysop-specific confirmation copy. | Likely | Phase 28 CONTEXT.md D-08 |

### USERS from→to copy + INVITES focus
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `error_message(:invalid_transition)` → `"Cannot change @<handle> from <from> to <to>."` mirroring success-message format. INVITES focus uses existing `theme.selected.fg`/`theme.selected.bg` slots. | Likely | `users_view.ex:131-135, 204-208, 213` |

### `1-N Jump` consistency
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Each screen calls a render-time helper `"1-#{length(tab_labels)}"`. Account `@key_bar` and Moderation `@key_list` module attributes become render-time functions; Sysop's existing `jump_hint` generalises. | Confident | `sysop.ex:61`; `account.ex:42-48, 178-182`; `moderation.ex:44, 126`; SPEC §7 grep-test acceptance |

### Site field description rewrites
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Five `@site_keys` descriptions in `config/schema.ex` rewritten as short operator-facing copy with no internal references. Enum lists NOT inlined; operators cycle to discover values. | Likely | `config/schema.ex:51-124` (current strings contain `(D-NN)` tokens); `site_form.ex:353` description rendering |

## Corrections Made

No corrections — user selected "Yes, proceed" to all 10 assumptions, including the recommended resolution of the SPEC SYSOP-03 vs Phase 28 D-12 discard-row conflict (honor Phase 28).

## External Research

None performed. All evidence in-tree (`lib/foglet_bbs/...`) plus Phase 28 CONTEXT.md.

---
status: diagnosed
trigger: "Sysop Site form footer shows '[Enter] Submit  [Esc] Cancel' but Ctrl+S is the actual save key"
created: 2026-04-27T00:00:00Z
updated: 2026-04-27T00:10:00Z
---

## Current Focus

hypothesis: Modal.Form's footer text is hardcoded to "[Enter] Submit   [Esc] Cancel" with no `submit_label` parameterization; Sysop SiteForm opts INTO show_footer (per D-29) but has no way to override the advertised key, so the footer literally cannot reflect Ctrl+S.
test: Read `lib/foglet_bbs/tui/widgets/modal/form.ex` render path; check `init/1` options; check SiteForm.State.build_modal_form/1 for any submit-label override.
expecting: A literal hardcoded string in the footer branch and no caller-supplied label option.
next_action: Confirmed; proceed to return diagnosis (goal: find_root_cause_only — no fix).

## Symptoms

expected: Sysop Site form footer must accurately advertise the keybinding that submits the form. Per Phase 28 SPEC FORM-03 / D-29, Sysop Site opts INTO Modal.Form's footer because the Sysop command bar advertises Q/Tabs/Jump but NOT Enter/Esc. Footer should reflect the actual save key (Ctrl+S, the documented primary submit per D-19).
actual: Footer reads "[Enter] Submit   [Esc] Cancel" but the wrapper-level shortcut that operators are expected to use is Ctrl+S; the user reports nothing on the screen advertises Ctrl+S.
errors: None. Affordance/copy mismatch only.
reproduction: SSH in, navigate Sysop -> Site form. Observe Modal.Form footer text. Test 4 in `.planning/phases/28-modal-form-substrate/28-HUMAN-UAT.md`.
started: Discovered during Phase 28 UAT after Plan 04 introduced SiteForm-via-Modal.Form with `show_footer: true` opt-in.

## Eliminated

- hypothesis: SiteForm fails to set a `submit_label` / `submit_key` option that exists on Modal.Form.
  evidence: `Modal.Form.init/1` (form.ex:158-187) accepts only `:title`, `:fields`, `:on_submit`, `:on_cancel`, `:show_footer`. There is NO submit-label/submit-key option in the struct (`defstruct` at form.ex:114-124) or in the `init/1` documented options. The footer is therefore unparameterized — no override surface exists for SiteForm to use.
  timestamp: 2026-04-27T00:08:00Z

- hypothesis: Enter handler is broken / Enter is not actually wired (so footer is "correct" and the bug is the action).
  evidence: UAT Test 4 explicitly reports "it seems to save if I hold Enter, but not press Enter" — i.e. Enter on the last visible field DOES route through Modal.Form's Clause 4 (form.ex:277-288) and submits via the same path as Ctrl+S. Enter IS wired (D-19 routes Ctrl+S through the same `:enter` dispatch). The Enter-on-last-vs-press-Enter problem is a SEPARATE gap (key-repeat dispatch bug) tracked as Gap 3 in 28-HUMAN-UAT.md, not this one. For the footer-mismatch session, Enter as a footer copy is *partially* accurate but operationally misleading because Ctrl+S is the documented primary advertised binding for Sysop Site (D-19) and is the path the user is expected to discover.
  timestamp: 2026-04-27T00:09:00Z

## Evidence

- timestamp: 2026-04-27T00:03:00Z
  checked: lib/foglet_bbs/tui/widgets/modal/form.ex render/2 footer branch
  found: Lines 451-456:
        footer_rows =
          cond do
            status_rows != [] -> []
            state.show_footer -> [text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)]
            true -> []
          end
        The footer string is a literal embedded in the cond clause. There is no interpolation, no label option, no submit-key parameter. Whatever caller opts into `show_footer: true` gets exactly this string.
  implication: The Modal.Form substrate has no concept of "what key actually submits this form" at the footer-rendering level. This is a substrate gap, not a SiteForm misconfiguration.

- timestamp: 2026-04-27T00:04:00Z
  checked: lib/foglet_bbs/tui/widgets/modal/form.ex defstruct + init/1 options
  found: defstruct at lines 114-124 has fields: title, fields, field_states, focus_index, errors, on_submit, on_cancel, show_footer (boolean), submit_state. No `submit_label`, no `submit_key`, no footer-text override. init/1 (lines 158-187) accepts only `:title`, `:fields`, `:on_submit`, `:on_cancel`, `:show_footer`. No surface for callers to customize the footer copy.
  implication: Confirms SiteForm has no override knob. Even if SiteForm wanted to advertise "[Ctrl+S] Save", it cannot — the substrate offers no parameter.

- timestamp: 2026-04-27T00:05:00Z
  checked: lib/foglet_bbs/tui/screens/sysop/site_form/state.ex build_modal_form/1
  found: Lines 131-152: ModalForm.init is called with `show_footer: true` plus title, fields, on_submit, on_cancel. The inline comment at lines 137-141 explicitly says: "Sysop's global command bar advertises Q/Tabs/Jump but NOT Enter/Esc, so the SITE form opts into Modal.Form's footer to advertise '[Enter] Submit   [Esc] Cancel' at the body level." The author intended the footer to advertise Enter/Esc — but Ctrl+S is the documented primary save shortcut per D-19, and the footer makes no mention of it.
  implication: SiteForm intentionally opts into the footer (correct per D-29) but is locked into the substrate's hardcoded Enter/Esc copy. The mismatch is between (a) D-19 promoting Ctrl+S as the SiteForm primary submit shortcut, advertised at the wrapper, and (b) the substrate footer that advertises only Enter/Esc.

- timestamp: 2026-04-27T00:06:00Z
  checked: lib/foglet_bbs/tui/screens/sysop/site_form.ex Ctrl+S handling
  found: Lines 75-78: handle_key/2 matches `%{key: :char, char: "s", ctrl: true}` and routes to `submit/1`, which then drives the per-render Modal.Form to the last visible field and dispatches `:enter`, hitting Modal.Form's Clause 4 submit branch. Ctrl+S is wired and works (UAT Test 4 confirms "Ctrl+S DOES save"). But the footer never mentions it — the wrapper does not contribute its own footer text and the substrate's footer is hardcoded.
  implication: The Ctrl+S binding is functional but undiscoverable. The fix has to either (1) extend Modal.Form to accept a submit-label/footer-text override, or (2) have SiteForm render its own footer hint (and pass `show_footer: false` to Modal.Form to avoid duplication).

- timestamp: 2026-04-27T00:07:00Z
  checked: .planning/phases/28-modal-form-substrate/28-CONTEXT.md D-06, D-07, D-08, D-09, D-19, D-29
  found: D-06/D-07: `:show_footer` boolean opt-in, default false. D-08/D-09: status row replaces footer when present. D-19: Ctrl+S explicitly preserved at the wrapper as a documented submit shortcut. D-29 (referenced in UAT Test 2 expectation): SiteForm opts into show_footer because Sysop command bar does not advertise Enter/Esc. NO decision document specifies what the footer text should SAY beyond the legacy "[Enter] Submit   [Esc] Cancel" carried forward verbatim from the pre-Phase-28 substrate. The decision tree never reconciled "footer advertises Enter/Esc" with "Ctrl+S is the documented primary save shortcut for THIS form".
  implication: Substrate gap — Modal.Form treats footer copy as a constant rather than as data tied to the submit binding. SiteForm is the only opt-in caller and it is the only one with a non-Enter primary submit (Ctrl+S). The mismatch was not caught at SPEC time because the spec cared about footer COUNT (one hint group, not two) rather than footer ACCURACY for this consumer.

- timestamp: 2026-04-27T00:08:00Z
  checked: .planning/phases/28-modal-form-substrate/28-04-SUMMARY.md key-decisions section (line 55)
  found: The Plan 04 author explicitly chose `show_footer: true` for Sysop SITE because "the Sysop global command bar advertises Q/Tabs/Jump but NOT Enter/Esc" — and intended the footer to "preserve the legacy SiteForm screen-level footer UX". The legacy footer ALSO said "[Enter] Submit / [Esc] Cancel"; the legacy Sysop SiteForm had the same affordance gap and Phase 28 carried it forward verbatim.
  implication: Pre-existing UX defect that survived the Phase 28 migration unchanged. The migration faithfully reproduced the legacy footer; the legacy footer was already wrong.

## Resolution

root_cause: Modal.Form's `render/2` hardcodes the footer string `"[Enter] Submit   [Esc] Cancel"` (lib/foglet_bbs/tui/widgets/modal/form.ex:454) with no caller-supplied label option, and SiteForm (the sole `show_footer: true` opt-in caller) has no way to advertise its actual primary submit binding (Ctrl+S, per D-19). The substrate has no concept of "what key submits this form" at footer-render time, so the user is told to press Enter while the wrapper-level shortcut they are expected to discover is Ctrl+S.
fix: (deferred — goal: find_root_cause_only)
verification: (deferred)
files_changed: []

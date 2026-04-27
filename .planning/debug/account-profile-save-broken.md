---
status: diagnosed
trigger: "Account → Profile tab: edit a field, submit, no save occurs (field reverts/no persistence). Reset on single field works."
created: 2026-04-27
updated: 2026-04-27
---

## Current Focus

hypothesis: SubmitStash key mismatch — on_submit closures (built in State.build_profile_form/build_prefs_form)
  capture `__MODULE__` = Foglet.TUI.Screens.Account.State and stash under that key,
  but ProfileForm.handle_key / PrefsForm.handle_key pop using `__MODULE__` =
  ProfileForm / PrefsForm. The pop returns nil; the `{:profile, payload} = nil`
  pattern match raises a MatchError; the :submitted branch never reaches the
  `[{:account_save_profile, attrs}]` command emission.
test: Run a script that calls ProfileForm.handle_key(%{key: :enter}, ...) with focus on the
  last field and observe whether SubmitStash.pop returns the expected payload.
expecting: If hypothesis correct → MatchError on nil. Stash key under State, not ProfileForm.
next_action: Reported via debug return; planner will design the fix.

## Symptoms

expected: User edits a profile field on Account → Profile tab and submits; value persists to user record.
actual: Field reverts (or no save). Esc-reset on single field works. Save/submit path is broken.
errors: None reported by user (silent failure — exception is swallowed by Raxol runtime; no command emitted).
reproduction: SSH into TUI, log in, navigate to Account → Profile tab, edit a field, advance focus to the last field via Tab, press Enter. No save. Same bug exists for PrefsForm (Preferences tab).
started: Phase 25 Plan 02 (commit 4a289d7, "feat(25-02): convert Account PROFILE and PREFS forms to Modal.Form") introduced the SubmitStash pattern with the cross-module key mismatch. Phase 28 plans 03-06 did not touch the submit path. The bug has been latent since Phase 25.

## Eliminated

- hypothesis: Modal.Form lock state (:submitting) wedges the form so Enter is swallowed
  evidence: `submit_state` defaults to `:idle` on a fresh form (built in seed_from_user).
    Reproduction shows MatchError fires BEFORE the lock is even tested (the crash is
    inside ProfileForm.handle_key, after Modal.Form.handle_event already returned).
  timestamp: 2026-04-27 (this session)

- hypothesis: Enter on a non-last field just advances focus (UX confusion) — user pressed Enter on first field expecting save
  evidence: Reproduction confirms the bug fires even when focus is on the last field
    (focus_index = 2 / :real_name). The crash is inside the :submitted branch, which
    proves the :submitted action IS being reached. UX confusion is a separate concern but
    not the root cause.
  timestamp: 2026-04-27 (this session)

- hypothesis: persistence path (do_update({:account_save_profile, attrs}) → Accounts.update_profile) is broken
  evidence: Existing test "successful save persists profile attrs" (account_test.exs L342-414)
    bypasses the keyboard path by injecting `{:account_save_profile, ...}` directly to
    App.update/2 and confirms persistence works. The defect is upstream: the keyboard path
    never EMITS the command tuple due to the SubmitStash key mismatch crash.
  timestamp: 2026-04-27 (this session)

- hypothesis: Press-Enter vs hold-Enter is a key-event-type filter issue
  evidence: Sysop test 4 reports the same "press doesn't, hold does" symptom, but that
    surface lives in a different submit path (Sysop SiteForm uses Ctrl+S routed through
    its own submit/1 helper, not SubmitStash). Whether the two issues share a deeper
    Raxol runtime cause is for the planner to investigate; for the Account → Profile
    save defect, the SubmitStash mismatch is sufficient and proven.
  timestamp: 2026-04-27 (this session)

## Evidence

- timestamp: 2026-04-27
  checked: lib/foglet_bbs/tui/screens/account/state.ex L188-238 (build_profile_form, build_prefs_form)
  found: |
    on_submit: fn payload -> SubmitStash.stash(__MODULE__, {:profile, payload}) end
    Inside Foglet.TUI.Screens.Account.State module — `__MODULE__` evaluates to
    Foglet.TUI.Screens.Account.State at compile time. Stash key:
    `{Foglet.TUI.Widgets.Modal.Form.SubmitStash, Foglet.TUI.Screens.Account.State}`.
  implication: Closure captures the State module (not ProfileForm/PrefsForm) as the stash key.

- timestamp: 2026-04-27
  checked: lib/foglet_bbs/tui/screens/account/profile_form.ex L45 (and prefs_form.ex L57)
  found: |
    {:profile, payload} = SubmitStash.pop(__MODULE__)   # in ProfileForm
    {:prefs,   payload} = SubmitStash.pop(__MODULE__)   # in PrefsForm
    Inside their respective modules, `__MODULE__` evaluates to ProfileForm / PrefsForm.
    Pop keys: `{SubmitStash, Account.ProfileForm}` and `{SubmitStash, Account.PrefsForm}`.
  implication: Pop key does NOT match stash key. Pop always returns nil.

- timestamp: 2026-04-27
  checked: SubmitStash.pop/1 (lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex L41-43)
  found: |
    def pop(mod), do: Process.delete({__MODULE__, mod})
    Process.delete returns the previously-associated value or nil if absent.
  implication: Calling pop with the wrong module key returns nil cleanly (no crash here).

- timestamp: 2026-04-27
  checked: Reproduction script (mix run /tmp/check_submit_stash.exs)
  found: |
    === Calling ProfileForm.handle_key with :enter ===
    MatchError raised: nil
    Result: :match_error
    State-keyed stash: {:profile, %{location: "", tagline: "", real_name: ""}}
    Profile-keyed stash: nil
  implication: |
    Direct empirical confirmation:
    1. The on_submit closure DID stash payload under Account.State.
    2. ProfileForm.handle_key DID pop under Account.ProfileForm and got nil.
    3. The match `{:profile, payload} = nil` raised MatchError.
    4. Outcome: ProfileForm.handle_key crashes; no `[{:account_save_profile, attrs}]`
       command is returned; nothing reaches App.update → save_account →
       Accounts.update_profile. The user sees "no save".

- timestamp: 2026-04-27
  checked: Test coverage in test/foglet_bbs/tui/screens/account_test.exs
  found: |
    No test exercises the keyboard path through ProfileForm/PrefsForm to :submitted.
    The "successful save persists profile attrs" test (L342-414) injects
    `{:account_save_profile, %{...}}` directly via App.update/2, bypassing the
    Modal.Form / SubmitStash interaction entirely.
  implication: Bug latent since Phase 25 Plan 02 (commit 4a289d7) because no
    end-to-end keyboard test ever drove the submit path. Phase 28 added
    :backtab/:escape/lock tests but not :enter-submit tests.

- timestamp: 2026-04-27
  checked: Phase 28 plan summaries (28-03 through 28-06)
  found: |
    None of the Phase 28 plans modified the SubmitStash stash/pop pair on
    Account ProfileForm / PrefsForm. Plan 28-03 changed only the :cancelled
    branch (status_message: nil). Plan 28-04 was Sysop SiteForm. Plan 28-05/06
    were BL-01/BL-02 (oneliner / Sysop lock release). The mismatched
    `__MODULE__` keys were inherited verbatim from Phase 25 Plan 02.
  implication: This is a pre-existing latent bug surfaced by Phase 28 UAT, not
    a Phase 28 regression in the strict sense — but the Phase 28 form
    substrate work created the conditions for UAT to discover it.

## Resolution

root_cause: |
  SubmitStash key mismatch. The on_submit closures created by
  Foglet.TUI.Screens.Account.State.build_profile_form/1 and build_prefs_form/1
  call `SubmitStash.stash(__MODULE__, ...)` where `__MODULE__` is
  `Foglet.TUI.Screens.Account.State` (the module the closures are defined in).
  But Foglet.TUI.Screens.Account.ProfileForm.do_handle_key/3 and
  Foglet.TUI.Screens.Account.PrefsForm.do_handle_key/3 call
  `SubmitStash.pop(__MODULE__)` where `__MODULE__` is the *Form* module, not
  the State module. Pop returns nil; the subsequent `{:profile, payload} = nil`
  / `{:prefs, payload} = nil` pattern match raises MatchError; ProfileForm /
  PrefsForm crash before emitting the
  `{:account_save_profile, attrs}` / `{:account_save_prefs, attrs}` command.
  No save command ever reaches App.update → Accounts.update_profile, so the
  edited fields never persist. The user observes "Enter does nothing; field
  state reverts on next render via reseed_from_user", which is the symptom
  reported in UAT test 1.

fix: (deferred — diagnose-only mode; planner will design)
verification: (deferred)
files_changed: []

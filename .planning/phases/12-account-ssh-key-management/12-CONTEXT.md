# Phase 12: Account SSH Key Management - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can add, inspect, revoke, and use their own registered SSH public keys from the terminal Account surface, and successful public-key authentication records last-used metadata. This phase is limited to self-service Account SSH key management and registered-key authentication metadata. Browser workflows, operator management of another user's keys, private-key generation/storage, key expiration, audit-log UI, and broader account-security work are out of scope.

Locked requirements come from `.planning/phases/12-account-ssh-key-management/12-SPEC.md` and cover KEYS-01 through KEYS-05.
</domain>

<decisions>
## Implementation Decisions

### Domain Key Lifecycle
- **D-01:** SSH key add, list, and revoke behavior belongs in `Foglet.Accounts`; callers should not bypass the context or call `Repo` directly from TUI code.
- **D-02:** Ownership-safe key operations should take the current `%Foglet.Accounts.User{}` actor and a key identifier or submitted attrs, then enforce user ownership inside Accounts.
- **D-03:** Revocation should hard-delete the owned `ssh_keys` row. The existing schema has no `revoked_at`/status field, and account deletion already hard-deletes SSH keys. Planners should not add a soft-revocation migration unless new evidence makes hard deletion unsafe.

### Authentication And Last-Used Recording
- **D-04:** Successful public-key authentication should update `last_used_at` inside an Accounts authentication lookup path that finds the matching key and non-deleted user together, updates only that key, and returns the user.
- **D-05:** `Foglet.SSH.CLIHandler` should remain orchestration code: pop the stashed public key, encode it, call Accounts, and start the session. It should not own SSH key persistence rules.
- **D-06:** Failed, invalid, unregistered, revoked, deleted-user, password, and guest-login paths must not update SSH key usage metadata.

### Account TUI Integration
- **D-07:** Add `SSH KEYS` as another Account tab using the existing `PROFILE` / `PREFS` / conditional `INVITES` tab pattern.
- **D-08:** Keep Account key UI state screen-local and pure over already-loaded state. Persistence and refresh actions should route through Accounts-facing actions or commands, not direct `Repo` access.
- **D-09:** Use sibling Account modules for key form/actions behavior, mirroring the existing `ProfileForm`, `PrefsForm`, and shared invites action/surface organization rather than bolting all logic into `Account.render/1`.
- **D-10:** Key list and revoke selection should use existing terminal-native widgets and themed render patterns, especially the tab, list/selection, table, modal, and modal-form primitives where they fit.

### Test Shape
- **D-11:** Extend focused Accounts SSH key tests for validation, duplicate handling, ownership-safe revoke, lookup, and last-used behavior.
- **D-12:** Extend SSH tests around `CLIHandler`/public-key auth for registered, unregistered, revoked, deleted-user, and last-used metadata behavior.
- **D-13:** Extend Account screen tests for the `SSH KEYS` tab, zero-key empty state, key list rendering, add flow errors, revoke flow, refresh behavior, and command routing.
- **D-14:** Keep tests deterministic: use direct context calls, supervised processes, monitors, or state inspection instead of `Process.sleep/1`.

### the agent's Discretion
- Exact key list layout, timestamp formatting details within existing user preference conventions, empty-state wording, modal copy, and whether the add flow uses a full modal form or a screen-local form are left to planner discretion, provided the locked acceptance criteria remain satisfied.
- Exact public function names may be chosen by the planner, but the context boundary and ownership shape above are locked.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope
- `.planning/phases/12-account-ssh-key-management/12-SPEC.md` — locked requirements, boundaries, constraints, and acceptance criteria for Phase 12.
- `.planning/ROADMAP.md` — Phase 12 goal, dependency, requirements, and success criteria.
- `.planning/REQUIREMENTS.md` — KEYS-01 through KEYS-05 traceability.
- `.planning/PROJECT.md` — SSH-first product boundary and v1.2 pre-alpha gap-closure intent.

### Data And Architecture
- `docs/DATA_MODEL.md` — `ssh_keys` schema contract, timestamp conventions, and account deletion behavior.
- `.planning/codebase/ARCHITECTURE.md` — SSH, TUI, session, and domain-layer boundaries.
- `.planning/codebase/CONVENTIONS.md` — context, schema, testing, and public API conventions.
- `.planning/codebase/TESTING.md` — ExUnit, fixture, OTP, and sandbox test patterns.

### TUI And Widgets
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — relevant terminal widget primitives.
- `lib/foglet_bbs/tui/widgets/README.md` — Foglet widget theming and stateful/stateless widget contracts.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Accounts.register_ssh_key/2` and `list_ssh_keys/1` already provide the core insert/list foundation and compute fingerprints server-side.
- `Foglet.Accounts.SSHKey` already validates OpenSSH public-key text, computes SHA256 fingerprints, and enforces unique fingerprint and per-user label constraints.
- `Foglet.SSH.KeyCB`, `Foglet.SSH.PubkeyStash`, and `Foglet.SSH.CLIHandler` already form the public-key authentication handoff.
- `Foglet.TUI.Screens.Account.State`, `ProfileForm`, `PrefsForm`, shared invites actions/surface, and Account screen tests provide the established Account tab/action pattern.
- Existing widgets include tabs, selection lists, tables, buttons, modals, and modal forms suitable for terminal-native list/add/revoke flows.

### Established Patterns
- Domain mutations are owned by context modules and return tagged tuples or changesets.
- Context APIs programmatically set foreign keys such as `user_id` before changeset construction.
- TUI screens render pure state and dispatch commands/actions for side effects.
- The SSH callback accepts offered public keys and defers application-level identity resolution to Accounts.
- Tests mirror source paths and should cite requirement IDs where practical.

### Integration Points
- Add or adjust Accounts APIs in `lib/foglet_bbs/accounts.ex` and SSH key behavior in `lib/foglet_bbs/accounts/ssh_key.ex` only as needed.
- Update public-key login flow in `lib/foglet_bbs/ssh/cli_handler.ex` to call the metadata-recording Accounts path.
- Extend `lib/foglet_bbs/tui/screens/account/state.ex` and `lib/foglet_bbs/tui/screens/account.ex` for the `SSH KEYS` tab.
- Add sibling Account key modules under `lib/foglet_bbs/tui/screens/account/` if the flow grows beyond trivial rendering.
- Extend tests in `test/foglet_bbs/accounts/`, `test/foglet_bbs/ssh/`, and `test/foglet_bbs/tui/screens/account_test.exs`.
</code_context>

<specifics>
## Specific Ideas

No user-provided visual references. Favor the existing Account surface style: compact terminal tabs, clear action hints, explicit validation errors, and no browser-like account workflow.
</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 12-account-ssh-key-management*
*Context gathered: 2026-04-24*

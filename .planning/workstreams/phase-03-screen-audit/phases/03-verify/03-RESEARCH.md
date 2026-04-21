# Phase 03: Verify - Research

**Researched:** 2026-04-21
**Domain:** TUI verify-screen state migration and audit cleanup
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Verify-state ownership

- **D-01:** `verify.ex` owns the canonical Verify screen state after this phase. The public entry point is `init_screen_state/1`, and the file-local private helper `default_verify_state/0` is the single source of truth for the default map.
- **D-02:** `state.verify_state` is removed from the top-level `Foglet.TUI.App` struct. The canonical store becomes `state.screen_state[:verify]`.
- **D-03:** `login.ex` and `register.ex` stop constructing a top-level verify-state map when routing a user to `:verify`. They only set the navigation/user fields needed to enter the screen. `verify.ex` self-initializes from `screen_state[:verify]`.

### State shape and helper policy

- **D-04:** The default verify state remains structurally identical to today's behavior:
  ```elixir
  %{
    buffer: "",
    attempts: 0,
    cooldown_until: nil,
    resend_cooldown_until: nil
  }
  ```
- **D-05:** `default_verify_state/0` is private and file-local. No new shared helper module is introduced; this stays within AUDIT-14.
- **D-06:** `init_screen_state/1` returns the same map as `default_verify_state/0`. No additional view-only fields, timestamps, or UX bookkeeping keys are added.

### Cooldown feedback presentation

- **D-07:** Keep the current minimal Verify presentation. The inline render area continues to show only the instruction line, the slot visualization, and the existing status line.
- **D-08:** Blocked submit and blocked resend continue to use modal feedback (`state.modal`) rather than adding inline countdown text or extra persistent rows to the screen content.
- **D-09:** No inline resend countdown line is added. This preserves the gateway-screen sparseness rule and avoids claiming the area below the existing error/status region.

### Reset semantics

- **D-10:** Entering `:verify` starts with a fresh default verify state unless the user is already actively on the Verify screen in the same screen session. Entry paths from Login/Register should not carry forward a stale buffer or stale counters.
- **D-11:** Escape from Verify clears `screen_state[:verify]` and returns to `:login`, matching the current "cancel verification flow" behavior.
- **D-12:** Successful verify completion clears `screen_state[:verify]`.
- **D-13:** Register/login flows that successfully route to `:main_menu` never initialize verify screen state.

### Locked inherited behavior

- **D-14:** The 6-character `[ABC___]` buffer stays hand-rolled. This is the inherited `phase-03-polish` decision and must be documented in the moduledoc: TextInput cannot reproduce the slot visualization cleanly without a custom renderer and would conflict with the current flat display.
- **D-15:** The two-timer model stays intact:
  - `cooldown_until` gates code-entry submission after 5 failed attempts.
  - `resend_cooldown_until` gates resend requests only.
  - These timers are independent.
- **D-16:** Successful resend continues to clear `buffer`, `attempts`, and `cooldown_until`, then sets `resend_cooldown_until`. This is already locked from `phase-03-polish` Phase 6 and must not be reinterpreted during the audit.
- **D-17:** The existing modal-copy model stays intact:
  - invalid attempts show the existing invalid-code modal,
  - blocked cooldown actions show the existing "Wait Ns." modal,
  - successful resend shows the existing info modal.

### File organization and scope fence

- **D-18:** `verify.ex` is reordered to match the canonical screen section order from AUDIT-18. Any deviation must be justified in the moduledoc.
- **D-19:** `verify.ex` gains a public `init_screen_state/1` to satisfy AUDIT-19.
- **D-20:** Phase 3 operates under the documented AUDIT-13(c) exception:
  - `lib/foglet_bbs/tui/screens/verify.ex`
  - `lib/foglet_bbs/tui/app.ex` for top-level field removal + Verify dispatch migration
  - `lib/foglet_bbs/tui/screens/login.ex` and `register.ex` only where they seed Verify entry state
  - matching tests that must move from `verify_state` to `screen_state[:verify]`

### Claude's Discretion

- Exact helper names beyond `init_screen_state/1` and `default_verify_state/0` (`get_verify_ss/1`, `put_verify_ss/2`, `clear_verify_ss/1`) are planner discretion; follow the existing naming style used in audited screens.
- Whether `handle_verify_event/2` remains public as a dedicated dispatch entry point or is slightly reshaped internally is planner discretion, as long as `App.update/2` still has a clean Verify dispatch path.
- Exact moduledoc wording is planner discretion, but it must explicitly cite the inherited keep-hand-rolled decision and any canonical-layout deviation if one remains after reordering.

### Deferred Ideas (OUT OF SCOPE)

- Inline resend countdown text or a dedicated cooldown row — deferred; out of scope for this restraint audit.
- Converting the Verify screen to `Input.TextInput` with a custom renderer — deferred; explicitly rejected by inherited decisions.
- Any broader gateway-screen UX redesign shared across login/register/verify — separate work, not part of this phase.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VERIFY-01 | Keep the 6-char `[ABC___]` buffer hand-rolled and document why | Existing `pad_buffer_with_cursor/1`, prior Phase 07 decision log, and current render path confirm this should remain custom. |
| VERIFY-02 | Consolidate 7 duplicated default-state literals | Codebase grep shows seven identical literals in `verify.ex`; file-local helper is the minimal fix. |
| VERIFY-03 | Preserve two-cooldown logic and 5-attempt lockout semantics | Existing tests and `verify.ex` logic already encode the required behavior and must be migrated without reinterpretation. |
| VERIFY-04 | Pass AUDIT-05..22 and reduce line count | Current file organization, reserved-region rule, and grep-gate surface are known; helper extraction plus state-plumbing cleanup should reduce LoC. |
| VERIFY-05 | Migrate top-level `state.verify_state` to `state.screen_state[:verify]` | `app.ex`, `login.ex`, `register.ex`, `verify.ex`, and two test files contain the complete ownership surface. |
</phase_requirements>

## Summary

Phase 03 is a constrained refactor, not a behavior change. The current Verify screen already contains the exact UX the workstream wants to preserve: the hand-rolled slot renderer, the 5-attempt lockout, the independent resend cooldown, and modal-based feedback. The planner should treat those behaviors as locked and focus on relocating state ownership, removing duplication, and restoring the canonical per-screen structure. `[VERIFIED: codebase grep] [CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`

The real implementation surface is small and explicit. `verify.ex` still falls back to `state.verify_state` in seven places, `Foglet.TUI.App` still declares and carries a top-level `verify_state`, and both `login.ex` and `register.ex` still seed that top-level map on entry to `:verify`. The tests also still assert against the old shape, including two layout-smoke fixtures that omit `resend_cooldown_until`. `[VERIFIED: codebase grep]`

**Primary recommendation:** Follow the Phase 2 register precedent exactly: give `verify.ex` public `init_screen_state/1`, private file-local state helpers, self-initialize from `state.screen_state[:verify]`, and update only the four documented call sites plus coverage. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md] [VERIFIED: codebase grep]`

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Verify screen state ownership | Frontend Server (SSR TUI process) | Browser / Client | The BEAM-side TUI model owns `screen_state`; the terminal only emits key events. `[VERIFIED: lib/foglet_bbs/tui/app.ex] [CITED: docs/ARCHITECTURE.md]` |
| 6-char slot rendering | Frontend Server (SSR TUI process) | Browser / Client | The bracketed buffer is rendered by `verify.ex` using Raxol view nodes, not by a client widget. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| Attempt lockout and resend cooldown gating | API / Backend | Frontend Server (SSR TUI process) | The state is enforced in screen logic before calling domain functions, while the actual code verification/resend flows call `Accounts`. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| Email-code verification and code generation | API / Backend | Database / Storage | `Accounts.verify_email_code/2` and `Accounts.build_verify_code/1` remain the domain boundary. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex] [CITED: .planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-VERIFICATION.md]` |
| Modal feedback rendering | Frontend Server (SSR TUI process) | — | `state.modal` is set in screen handlers and rendered centrally by `App.view/1`. `[VERIFIED: lib/foglet_bbs/tui/app.ex]` |

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` before considering the phase done. `[CITED: CLAUDE.md]`
- Read `docs/ARCHITECTURE.md` for structural changes and `docs/raxol/getting-started/WIDGET_GALLERY.md` plus `lib/foglet_bbs/tui/widgets/README.md` for TUI work. `[CITED: CLAUDE.md]`
- Keep block-expression rebinding correct; bind the whole `if`/`case` result rather than assuming mutation. `[CITED: CLAUDE.md]`
- Do not treat structs as implementing `Access`; use field access or dedicated helpers. `[CITED: CLAUDE.md]`
- Use `start_supervised!/1` in tests and avoid `Process.sleep/1`; cooldown tests should keep using direct `DateTime` setup. `[CITED: CLAUDE.md]`

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir | 1.19.5 | Language/runtime for the app and tests | Installed locally and compatible with the repo's `~> 1.17` requirement. `[VERIFIED: local command] [VERIFIED: mix.exs]` |
| Erlang/OTP | 28 | BEAM runtime for the TUI app | Installed locally; matches the active Mix toolchain. `[VERIFIED: local command]` |
| Phoenix | 1.8.5 | App framework and OTP boundary | Repo-pinned in `mix.lock`; no phase changes required. `[VERIFIED: mix.lock]` |
| Raxol | 2.4.0 | TUI rendering/runtime primitives | Vendored via `path: "vendor/raxol"` and already drives screen rendering. `[VERIFIED: mix.exs] [VERIFIED: mix.lock] [CITED: docs/raxol/getting-started/WIDGET_GALLERY.md]` |
| ExUnit | bundled with Elixir | Test framework | Existing verify and layout smoke coverage already use it. `[VERIFIED: codebase grep]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Ecto / Ecto SQL | 3.13.5 | Domain persistence underneath `Accounts` | Read-only context for this phase; no schema work required. `[VERIFIED: mix.lock]` |
| Foglet.TUI.Theme | local module | Theme extraction via `Theme.from_state/1` | Use for every render path and widget call. `[VERIFIED: codebase grep] [CITED: .planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md]` |
| Foglet.TUI.Widgets.Chrome.ScreenFrame | local module | Standard frame + keybar/statusbar wrapper | Verify continues to render through it. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled verify slot renderer | `Input.TextInput` with custom renderer | Rejected by locked decision; adds complexity and risks border/layout drift for no phase value. `[CITED: .planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md]` |
| File-local `default_verify_state/0` | Shared helper module | Violates AUDIT-14 and widens scope without reuse outside this screen. `[CITED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md]` |
| Screen-owned `screen_state[:verify]` | Keep top-level `state.verify_state` | Conflicts with AUDIT-19 and Phase 2 precedent. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md] [CITED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md]` |

**Installation:**
```bash
mix deps.get
```

**Version verification:** Repo-pinned versions were verified from `mix.exs` and `mix.lock`, and local runtime availability was verified with `elixir --version` / `mix --version`. `[VERIFIED: mix.exs] [VERIFIED: mix.lock] [VERIFIED: local command]`

## Architecture Patterns

### System Architecture Diagram

```text
SSH key event
  -> Foglet.TUI.App.do_update({:key, event}, state)
  -> Verify.handle_key/2 or Verify.handle_verify_event/2
  -> verify screen state helper reads/writes screen_state[:verify]
  -> optional Accounts.verify_email_code/2 or Accounts.build_verify_code/1
  -> state.modal / current_screen / current_user updated
  -> App.view/1 renders modal overlay or Verify.render/1 through ScreenFrame
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/
├── app.ex              # top-level model + update/view dispatch
├── screens/
│   ├── verify.ex       # screen-owned verify state + render/handle_key/event hook
│   ├── login.ex        # verify entry path
│   └── register.ex     # verify entry path
└── widgets/chrome/
    └── screen_frame.ex # screen chrome wrapper

test/foglet_bbs/tui/
├── screens/verify_test.exs
└── layout_smoke_test.exs
```

### Pattern 1: Screen-Owned State with Public Initializer
**What:** A screen exposes public `init_screen_state/1`, owns its default shape locally, and reads/writes through `state.screen_state[:screen]`. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md] [VERIFIED: lib/foglet_bbs/tui/screens/register.ex]`
**When to use:** Any non-stateless screen covered by AUDIT-19. `[CITED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md]`
**Example:**
```elixir
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts), do: %{sub: :menu}

defp get_login_ss(state) do
  Map.get(state.screen_state || %{}, :login) ||
    %{focused_field: nil, handle_input: nil, password_input: nil, error: nil}
end
```
Source: `lib/foglet_bbs/tui/screens/login.ex` `[VERIFIED: codebase grep]`

### Pattern 2: File-Local State Plumbing Helpers
**What:** Keep `get_ss`/`put_ss`/`clear_ss`/`default_ss` private inside the screen file rather than introducing a shared abstraction. `[VERIFIED: lib/foglet_bbs/tui/screens/register.ex]`
**When to use:** Small screen-specific maps with one ownership site. `[CITED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md]`
**Example:**
```elixir
defp put_register_ss(state, reg) do
  new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
  %{state | screen_state: new_screen_state}
end

defp clear_register_ss(state) do
  new_screen_state = Map.delete(state.screen_state || %{}, :register)
  %{state | screen_state: new_screen_state}
end
```
Source: `lib/foglet_bbs/tui/screens/register.ex` `[VERIFIED: codebase grep]`

### Pattern 3: Modal Feedback Centralized in App
**What:** Screen handlers set `state.modal`; `App.view/1` handles overlay rendering and modal key handling globally. `[VERIFIED: lib/foglet_bbs/tui/app.ex]`
**When to use:** Temporary blocked-action or status feedback without adding new rows to the screen. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`
**Example:**
```elixir
defp do_update({:verify_event, event}, state) do
  Screens.Verify.handle_verify_event(event, state)
end
```
Source: `lib/foglet_bbs/tui/app.ex` `[VERIFIED: codebase grep]`

### Anti-Patterns to Avoid

- **Top-level verify-state resurrection:** Do not leave `verify_state` in `%Foglet.TUI.App{}` while also adding `screen_state[:verify]`; that creates split ownership. `[VERIFIED: codebase grep]`
- **Behavioral reinterpretation during migration:** Do not "simplify" resend or cooldown logic while moving state. Phase 3 is constrained to ownership and duplication cleanup. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`
- **Inline fallback literals after helper extraction:** Once `default_verify_state/0` exists, no remaining `%{buffer: "", attempts: 0, ...}` literal should stay in `verify.ex`. `[VERIFIED: codebase grep]`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Top-level state dispatch abstraction | New shared verify-state module | File-local helpers in `verify.ex` | The state shape is tiny and AUDIT-14 forbids new shared modules. `[CITED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md]` |
| Modal overlay rendering | Inline modal rows in Verify content | Existing `state.modal` + `App.view/1` overlay path | Preserves reserved layout region and existing feedback model. `[VERIFIED: lib/foglet_bbs/tui/app.ex] [CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]` |
| Verify code input widget | Custom `TextInput` adapter | Existing hand-rolled slot renderer | Locked by inherited decision and already covers the UX precisely. `[CITED: .planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md]` |

**Key insight:** This phase wins by deleting duplication and normalizing ownership, not by generalizing the Verify screen into a new abstraction. `[CITED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md]`

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verify screen state is not persisted to an Ecto schema or config row; the phase touches in-memory TUI state only. `[VERIFIED: codebase grep]` | Code edit only |
| Live service config | None — resend cooldown config already exists from Phase 6 and is not being renamed or migrated here. `[CITED: .planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-VERIFICATION.md]` | None |
| OS-registered state | None — Verify state lives inside the app process, not OS-level registrations. `[VERIFIED: codebase grep]` | None |
| Secrets/env vars | None — no env var or secret names are part of this migration surface. `[VERIFIED: codebase grep]` | None |
| Build artifacts | None specific to Verify state ownership; no installed package or generated artifact embeds `verify_state`. `[VERIFIED: codebase grep]` | None |

## Common Pitfalls

### Pitfall 1: Missing One of the Seven Default-State Fallbacks
**What goes wrong:** One `state.verify_state || %{...}` path survives after the helper extraction, so Verify still depends on the deprecated top-level field or diverges from the canonical default. `[VERIFIED: codebase grep]`
**Why it happens:** The literal appears seven times across render, key handling, submit, resend, and event paths. `[VERIFIED: codebase grep]`
**How to avoid:** Introduce `default_verify_state/0` early, then convert every fallback read before touching behavior. Finish with a grep gate for the literal. `[VERIFIED: codebase grep]`
**Warning signs:** `rg` still finds `%{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}` in `verify.ex`. `[VERIFIED: codebase grep]`

### Pitfall 2: Clearing the Wrong State on Exit or Success
**What goes wrong:** Escape or successful submit leaves stale `screen_state[:verify]`, so later visits reopen with an old buffer or counter. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`
**Why it happens:** The current code clears `verify_state: nil` directly in three paths; the migration must convert all three. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]`
**How to avoid:** Add a dedicated `clear_verify_ss/1` helper and use it for escape, no-user submit fallback, and success. `[ASSUMED]`
**Warning signs:** Tests still assert `new_state.verify_state == nil` instead of checking `screen_state[:verify]` removal. `[VERIFIED: codebase grep]`

### Pitfall 3: Reinterpreting the Dual-Timer Model
**What goes wrong:** Attempt cooldown and resend cooldown become coupled, or resend stops clearing `attempts` and `cooldown_until`. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`
**Why it happens:** State migration invites "cleanup" of conditionals that are actually load-bearing. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]`
**How to avoid:** Treat current `submit_raw/1` and `resend_code_raw/1` behavior as specification and move only the state plumbing. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex] [CITED: .planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-VERIFICATION.md]`
**Warning signs:** Resend tests lose assertions about `cooldown_until == nil`, `attempts == 0`, or `resend_cooldown_until` remaining independent. `[VERIFIED: test/foglet_bbs/tui/screens/verify_test.exs]`

### Pitfall 4: Forgetting Non-Screen Verify Entry Points
**What goes wrong:** `verify.ex` reads `screen_state[:verify]`, but `login.ex` or `register.ex` still seeds `verify_state`, or layout smoke tests still build the old struct shape. `[VERIFIED: codebase grep]`
**Why it happens:** The phase touches four production files and two test files, not one file in isolation. `[VERIFIED: codebase grep]`
**How to avoid:** Treat the migration surface as a fixed checklist: `verify.ex`, `app.ex`, `login.ex`, `register.ex`, `verify_test.exs`, `layout_smoke_test.exs`. `[VERIFIED: codebase grep]`
**Warning signs:** `rg -n "verify_state"` still returns production hits after the refactor. `[VERIFIED: codebase grep]`

## Code Examples

Verified patterns from the codebase:

### Screen-Owned State Plumbing
```elixir
defp get_register_ss(state) do
  Map.get(state.screen_state || %{}, :register) || init_screen_state_for(state)
end

defp put_register_ss(state, reg) do
  new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
  %{state | screen_state: new_screen_state}
end
```
Source: `lib/foglet_bbs/tui/screens/register.ex` `[VERIFIED: codebase grep]`

### Verify Event Dispatch Boundary
```elixir
defp do_update({:verify_event, event}, state) do
  Screens.Verify.handle_verify_event(event, state)
end
```
Source: `lib/foglet_bbs/tui/app.ex` `[VERIFIED: codebase grep]`

### Hand-Rolled Slot Renderer to Preserve
```elixir
defp pad_buffer_with_cursor(buffer) when is_binary(buffer) do
  len = String.length(buffer)

  if len >= @code_length do
    buffer
  else
    remaining = @code_length - len - 1
    buffer <> "█" <> String.duplicate("_", remaining)
  end
end
```
Source: `lib/foglet_bbs/tui/screens/verify.ex` `[VERIFIED: codebase grep]`

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Top-level wizard/screen state on `%Foglet.TUI.App{}` | Screen-owned `state.screen_state[:screen]` with `init_screen_state/1` | Established by Phase 2 on 2026-04-21 | Phase 3 should inherit the same ownership model for Verify. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md]` |
| Repeated inline default-state maps | File-local `default_*_state/0` helpers in audit phases | Workstream audit rule active in v1.0.2 | Reduces drift and makes grep-gate verification simpler. `[CITED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md] [CITED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md]` |

**Deprecated/outdated:**
- Top-level `verify_state` ownership in `Foglet.TUI.App` is now the outdated pattern for this workstream and should be removed in Phase 03. `[CITED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md] [VERIFIED: lib/foglet_bbs/tui/app.ex]`

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A dedicated `clear_verify_ss/1` helper is the cleanest way to clear screen state in all exit paths. | Common Pitfalls | Low — planner can choose different helper names/mechanics without changing scope. |

## Open Questions

1. **Should `handle_verify_event/2` stay public as the App dispatch entry point?**
   - What we know: `App.do_update({:verify_event, event}, state)` currently delegates straight to it, and CONTEXT.md leaves the exact shape to planner discretion. `[VERIFIED: lib/foglet_bbs/tui/app.ex] [CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]`
   - What's unclear: Whether the planner wants to preserve that public hook unchanged or collapse some logic behind private helpers while keeping the dispatch boundary stable.
   - Recommendation: Keep the public function and refactor internals only; that minimizes App churn and mirrors the current contract. `[ASSUMED]`

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `elixir` | compiling/tests | ✓ | 1.19.5 | — |
| `mix` | test/precommit commands | ✓ | 1.19.5 | — |
| Erlang/OTP | runtime/toolchain | ✓ | 28 | — |

**Missing dependencies with no fallback:**
- None. `[VERIFIED: local command]`

**Missing dependencies with fallback:**
- None. `[VERIFIED: local command]`

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (repo-native) `[VERIFIED: codebase grep]` |
| Config file | `mix.exs`, `test/test_helper.exs` `[VERIFIED: mix.exs]` |
| Quick run command | `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` `[VERIFIED: codebase grep]` |
| Full suite command | `mix test` and phase gate `mix precommit` `[CITED: CLAUDE.md] [VERIFIED: mix.exs]` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VERIFY-01 | Hand-rolled slot renderer remains visible and usable | unit + layout smoke | `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ |
| VERIFY-02 | All default-state ownership paths route through helper/self-init | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ |
| VERIFY-03 | 5-attempt lockout and resend cooldown semantics preserved | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ |
| VERIFY-04 | Audit rubric and line-count reduction | static + suite | `mix precommit` | ✅ |
| VERIFY-05 | `screen_state[:verify]` migration across app entry points | unit + smoke | `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/screens/verify_test.exs`
- **Per wave merge:** `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Phase gate:** `mix precommit`

### Wave 0 Gaps

- [ ] Update `test/foglet_bbs/tui/layout_smoke_test.exs` verify fixtures to use `screen_state[:verify]` and include `resend_cooldown_until` in the migrated state shape. `[VERIFIED: codebase grep]`
- [ ] Rewrite `test/foglet_bbs/tui/screens/verify_test.exs` assertions away from `new_state.verify_state` so the migration is actually locked by tests. `[VERIFIED: codebase grep]`

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Existing `Accounts.verify_email_code/2` boundary and 5-attempt cooldown flow. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| V3 Session Management | no | Out of scope; phase does not alter session lifecycle. `[CITED: docs/ARCHITECTURE.md]` |
| V4 Access Control | no | No authorization boundary changes. `[VERIFIED: codebase grep]` |
| V5 Input Validation | yes | Verify input is restricted to uppercase alphanumeric chars and fixed length 6. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| V6 Cryptography | no | No crypto implementation changes in this phase. `[VERIFIED: codebase grep]` |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Brute-force verify-code entry | Tampering | Preserve `@max_attempts` lockout and `cooldown_until` gating exactly. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| Resend spam / code churn | Denial of Service | Preserve `resend_cooldown_until` gating and visible modal feedback. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex]` |
| Stale in-memory verify state reused across flows | Elevation of Privilege | Clear `screen_state[:verify]` on escape and success, and start fresh on new entry. `[CITED: .planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md]` |

## Sources

### Primary (HIGH confidence)

- `lib/foglet_bbs/tui/screens/verify.ex` - current Verify behavior, duplicated literals, cooldown semantics
- `lib/foglet_bbs/tui/app.ex` - top-level `verify_state`, Verify event dispatch, modal rendering
- `lib/foglet_bbs/tui/screens/login.ex` - Verify entry path still seeding top-level state
- `lib/foglet_bbs/tui/screens/register.ex` - Verify entry path still seeding top-level state
- `test/foglet_bbs/tui/screens/verify_test.exs` - behavior coverage and old-shape assertions
- `test/foglet_bbs/tui/layout_smoke_test.exs` - verify render fixtures that still use old shape
- `.planning/workstreams/phase-03-screen-audit/phases/03-verify/03-CONTEXT.md` - locked decisions and scope
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` - VERIFY-01..05 and AUDIT rubric
- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` - phase goal, success criteria, serialized dependency
- `.planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md` - canonical migration precedent
- `.planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-RESEARCH.md` - prior verified resend/cooldown findings
- `.planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-VERIFICATION.md` - previously verified semantics
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md` - locked hand-rolled buffer decision
- `CLAUDE.md` - project constraints
- `docs/ARCHITECTURE.md` - app/screen ownership boundaries
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - local Raxol widget docs
- `lib/foglet_bbs/tui/widgets/README.md` - local widget contract summary
- `mix.exs`, `mix.lock` - stack and version verification

### Secondary (MEDIUM confidence)

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` - audit-wide canonical screen layout and state-ownership analysis
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` - workstream-level conclusions and anti-affordances

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `mix.lock`, and local toolchain output.
- Architecture: HIGH - verified from current production files plus Phase 2 precedent.
- Pitfalls: HIGH - verified from direct state-ownership reads and existing tests.

**Research date:** 2026-04-21
**Valid until:** 2026-05-21

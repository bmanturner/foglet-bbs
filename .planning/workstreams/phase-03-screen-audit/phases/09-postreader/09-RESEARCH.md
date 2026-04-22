# Phase 9: PostReader - Research

**Researched:** 2026-04-22
**Domain:** Elixir/Raxol TUI screen audit for `PostReader` lifecycle, loading UX, and render-path purity
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Domain/helper adoption

- **D-01:** Apply full helper adoption now: all domain module resolution in load/flush paths uses `Domain.get/2`.
- **D-02:** Preserve existing fallbacks exactly (`Foglet.Posts`, `Foglet.Boards`, `Foglet.Threads`) with no behavior drift.

### Public callback ownership

- **D-03:** Keep `load_posts/2` and `flush_read_pointers/2` public as App-dispatched screen callbacks.
- **D-04:** Treat them as intentional contract surface, not dead code; enforce with call-site and test verification.

### Loading-state behavior

- **D-05:** Adopt spinner-based loading for this phase (`AUDIT-10`) rather than plain `"Loading posts..."` text.
- **D-06:** Spinner adoption remains bounded by sparseness constraints: no visible row growth and no protected-region fill.

### Render-path purity and cache boundaries

- **D-07:** Enforce strict render purity: no state writes inside any `defp render_*`.
- **D-08:** Mutations remain limited to non-render paths (`load_posts`, `advance_post`, `scroll_post`, cache/viewport warm helpers) with tests guarding this boundary.

### the agent's Discretion

- Exact spinner placement and style details that satisfy row/region constraints.
- Exact test additions to prove callback contracts and purity boundaries.
- Exact helper extraction/refactor shape that keeps diffs minimal and behavior stable.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| READER-01 | Theme + domain lookups use Phase 0 helpers (3 call sites in this screen — the densest). [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:160] | Helper usage and fallback parity are already present in `post_reader.ex`; planning should preserve that shape while removing legacy wording/drift. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:35,163-167,210-220,307-311] |
| READER-02 | `load_posts/2` and `flush_read_pointers/2` dead-code audit per `AUDIT-12`. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:161] | Functions are used heavily by screen tests; App command handling currently performs loading/flushing in `App.do_update/2`, so callback ownership must be documented/tested, not silently deleted. [VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs:90-91,143-155; lib/foglet_bbs/tui/app.ex:433-443,469-478] |
| READER-03 | Evaluate spinner for load + flush. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:162] | Existing screen still renders plain loading text; BoardList/ThreadList show accepted spinner patterns to reuse without row growth. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:93-96; lib/foglet_bbs/tui/screens/board_list.ex:36-49; lib/foglet_bbs/tui/screens/thread_list.ex:37-47] |
| READER-04 | Keep `PostCard` + `MarkdownBody` + `Viewport` pipeline unchanged. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:163] | Current render path already composes `PostCard.render_body_lines/3` with `Viewport.update/render`; planner should treat this as immutable contract. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:75,81-83,353-360] |
| READER-05 | Enforce no mutation inside `defp render_*`. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:164] | File comment already encodes this rule and mutation lives in non-render helpers; tests should lock this boundary. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:77-80,330-338,363-433] |
| READER-06 | Full `AUDIT-05..22` plus `mix precommit` and low/no size growth. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:165] | Existing project alias `mix precommit` is the canonical quality gate and should remain phase gate. [VERIFIED: mix.exs:80-87; AGENTS.md] |
| READER-07 | Moduledoc must document load-absorb behavior. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:166] | Behavior exists (`{:update, state, []}` while posts are loading) but is only inline-commented, not clearly called out in moduledoc. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:366-371,404-407] |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` at the end; do not treat file-local tests as sufficient. [VERIFIED: CLAUDE.md]
- Use `Req` for HTTP work; avoid `:httpoison`, `:tesla`, `:httpc` (not directly needed for Phase 9). [VERIFIED: CLAUDE.md]
- Prefer Elixir stdlib for time/date handling (already followed in tests and screen helpers). [VERIFIED: CLAUDE.md; test/foglet_bbs/tui/screens/post_reader_test.exs]
- Keep Elixir gotchas in mind: no struct `Access`, no in-block pseudo-mutation assumptions, no multi-module files. [VERIFIED: CLAUDE.md]
- For tests, avoid sleeps; use deterministic synchronization when needed. [VERIFIED: CLAUDE.md]

## Summary

Phase 9 is a constrained final-screen audit where behavior is mostly correct already; the plan should optimize for contract clarity and guardrails, not feature work. [VERIFIED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md:171-189; lib/foglet_bbs/tui/screens/post_reader.ex]

`PostReader` already uses `Theme.from_state/1`, `Domain.get/2`, and the `PostCard` + `Viewport` rendering pipeline with cache warming outside render helpers; this gives a stable base for READER-01/04/05. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:35,75,77-83,163-167,210-220,307-311,330-360]

The main planning work is explicit: adopt spinner-based loading UX in a sparse-safe way, formalize public callback ownership (`load_posts/2`, `flush_read_pointers/2`) despite App-level task execution, and add proof that render helpers remain mutation-free. [VERIFIED: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md; lib/foglet_bbs/tui/app.ex:433-443,469-478; lib/foglet_bbs/tui/screens/post_reader.ex:50-97]

**Primary recommendation:** Plan one implementation track that keeps render/data flow unchanged, adds spinner + moduledoc + callback-contract tests, and gates with `mix precommit` plus READER-specific grep checks. [VERIFIED: mix.exs:80-87; .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:160-166]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Post navigation and viewport scrolling (`j/k/n/p/Space`) | API / Backend [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:99-112,363-433] | Database / Storage [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:384-397] | Screen logic runs in server-side TUI process; read-pointer effects persist through domain calls. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:224-250] |
| Post rendering pipeline (`PostCard` + markdown tuples + `Viewport`) | API / Backend [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:75,81-83,304-325,353-360] | — | Rendering is server-driven ANSI tree generation inside screen module. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] |
| Async post load/flush orchestration | API / Backend [VERIFIED: lib/foglet_bbs/tui/app.ex:433-443,469-478] | Database / Storage [VERIFIED: lib/foglet_bbs/tui/app.ex:623-649] | App owns off-process task execution; screen emits command tuples and maintains local UI state. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:145,186-187,227-229] |
| Loading-state spinner UX | API / Backend [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex:36-49; lib/foglet_bbs/tui/screens/thread_list.ex:37-47] | — | Spinner is rendered in the same screen tree; no client/runtime split exists. [VERIFIED: docs/ARCHITECTURE.md] |
| Render-path purity enforcement | API / Backend [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:77-80] | — | Purity is a code-structure and test-contract concern in server code. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:164] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir | 1.19.5 [VERIFIED: `elixir --version`] | Runtime + language for screen module and tests | Project/toolchain baseline in this workspace. [VERIFIED: mix.exs:8] |
| Erlang/OTP | 28 [VERIFIED: `elixir --version`] | BEAM runtime executing TUI and task closures | Required by all Phoenix/TUI processes in this repo. [VERIFIED: docs/ARCHITECTURE.md] |
| Phoenix | 1.8.5 [VERIFIED: mix.lock] | App shell, process/runtime integration, PubSub substrate | Existing pinned dependency; no replacement in scope. [VERIFIED: mix.exs:46; mix.lock:33] |
| Raxol | 2.4.0 [VERIFIED: mix.lock] | TUI components (`Viewport`, spinner primitives) | Existing vendor/pinned UI runtime for all screen rendering. [VERIFIED: mix.exs:64; mix.lock:45] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | bundled with Elixir 1.19.5 [VERIFIED: `elixir --version`] | Screen and App contract tests | All READER requirement regression coverage. [VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs] |
| Credo | 1.7.18 [VERIFIED: mix.lock:11] | Static style/idiom checks | `mix precommit` phase gate. [VERIFIED: mix.exs:84] |
| Sobelow | 0.14.1 [VERIFIED: mix.lock:53] | Security linting | `mix precommit` phase gate. [VERIFIED: mix.exs:85] |
| Dialyxir | 1.4.7 [VERIFIED: mix.lock:14] | Type/spec analysis | `mix precommit` phase gate. [VERIFIED: mix.exs:86] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Keep `"Loading posts..."` text [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:95] | `Widgets.Progress.Spinner` [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] | Spinner better signals indeterminate async work but must not increase row density. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:40,162] |
| Refactor callbacks private/delete | Keep public callback contract | Locked decision favors stable testable contract despite App-task ownership. [VERIFIED: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md:D-03,D-04; lib/foglet_bbs/tui/app.ex:433-443,469-478] |

**Installation:**
```bash
mix deps.get
```

**Version verification:** (hex lock verification used for this Elixir stack)
```bash
rg -n '"phoenix"|"raxol"|"credo"|"dialyxir"|"sobelow"' mix.lock
elixir --version
mix --version
```

## Architecture Patterns

### System Architecture Diagram

```text
User keypress (j/k/n/p/q/r)
        |
        v
PostReader.handle_key/2 --------------------------+
  |                                               |
  | state-only nav/scroll updates                | emits command tuple
  v                                               v
advance_post/scroll_post (mutating helpers)   {:load_posts,...} / {:flush_read_pointers,...}
  |                                               |
  +--> warm_cache + warm_viewport                v
             |                              TUI.App.do_update/2
             v                              (Command.task off-process)
       screen_state[:post_reader]                 |
             |                                    v
             +------> render/1 -> render_post_content/5 -> PostCard + Viewport
                                                  |
                                                  v
                                         Domain modules / DB pointer flush
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/screens/
├── post_reader.ex        # Phase 9 production edits (spinner, moduledoc, purity guardrails)
├── thread_list.ex        # Caller path context; keep load command contract unchanged
└── domain.ex             # Existing helper contract used by PostReader
test/foglet_bbs/tui/screens/
└── post_reader_test.exs  # Contract, loading UX, and purity-boundary regression tests
```

### Pattern 1: Keep Render Functions Read-Only

**What:** Render helpers may construct transient component state for this frame, but must not persist mutations into app state. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:77-83]
**When to use:** Any `render_*` branch in `PostReader`.
**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
{vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, _cmds} = Viewport.update({:set_children, body_lines}, vp)
body_rendered = Viewport.render(vp, %{})
```

### Pattern 2: Keep Mutations in Non-Render Helpers

**What:** `advance_post/2`, `scroll_post/2`, `load_posts/2`, and warm helpers own cache/viewport writes. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:330-338,363-433]
**When to use:** Any state change tied to navigation or lifecycle callbacks.
**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
ss = if post, do: warm_cache(ss, state, post, w), else: ss
ss = if post, do: warm_viewport(ss, state, post, w), else: ss
new_screen_state = Map.put(state.screen_state, :post_reader, ss)
```

### Pattern 3: Explicit Domain Fallback Branches

**What:** `Domain.get/2` result is matched explicitly with local fallback modules.
**When to use:** `load_posts/2`, `flush_read_pointers/2`, `parse_body/2`.
**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
posts_mod =
  case Domain.get(ctx, :posts) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Posts
  end
```

### Anti-Patterns to Avoid

- **Mutating inside `defp render_*`:** Breaks locked purity boundary and makes reflow behavior nondeterministic. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:164]
- **Replacing PostCard/Markdown/Viewport pipeline:** Explicitly out of scope for Phase 9. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:163]
- **Adding spinner rows/extra filler content:** Violates sparseness and protected-region rules. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:40,166; .planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scroll clamping/content height math | custom offset math | `Raxol.UI.Components.Display.Viewport` updates | Viewport already handles `scroll_by`, `scroll_to`, and content-height-based bounds. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:424-427] |
| Indeterminate loading glyph animation | ad-hoc spinner chars | `Foglet.TUI.Widgets.Progress.Spinner` | Reuses themed spinner styles and frame duration contract. [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] |
| Markdown line styling pipeline | inline parser/output formatting in screen | `PostCard.render_body_lines/3` with markdown tuples | Keeps rendering contract stable and aligned with existing tests. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:75,304-325; test/foglet_bbs/tui/screens/post_reader_test.exs:216-249] |

**Key insight:** This phase should enforce existing abstractions, not replace them; quality risk is from contract drift, not missing primitives. [VERIFIED: .planning/workstreams/phase-03-screen-audit/ROADMAP.md:171-189]

## Common Pitfalls

### Pitfall 1: Confusing Public Callback Contract with App Task Ownership
**What goes wrong:** Planner deletes or privatizes `load_posts/2` / `flush_read_pointers/2` because App has task-based load/flush.
**Why it happens:** `App.do_update/2` currently performs real I/O paths off-process.
**How to avoid:** Keep callbacks public per locked decisions and prove ownership via tests + comments.
**Warning signs:** Function visibility changes without corresponding context decision update. [VERIFIED: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md:D-03,D-04]

### Pitfall 2: Spinner Adoption that Breaks Sparseness
**What goes wrong:** Spinner is added with extra padding/new rows.
**Why it happens:** Reusing component demos without screen-density constraints.
**How to avoid:** Mirror `BoardList`/`ThreadList` one-row spinner+label composition only.
**Warning signs:** Added `text("")` spacers or new section wrappers in loading path. [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex:39-48; lib/foglet_bbs/tui/screens/thread_list.ex:38-47]

### Pitfall 3: Purity Regression via Cache Writes in Render
**What goes wrong:** `render_post_content/5` begins writing to `render_cache` or `screen_state`.
**Why it happens:** Attempting to "optimize" parse path inline.
**How to avoid:** Warm cache in `load_posts/2` / nav helpers only.
**Warning signs:** `Map.put`, `put_in`, or `%{state | ...}` appears under `defp render_*`. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:77-83,330-338]

## Code Examples

Verified patterns from repository sources:

### Loading Spinner Composition (Screen-Safe Pattern)
```elixir
# Source: lib/foglet_bbs/tui/screens/board_list.ex
row(style: %{gap: 1}, do: [
  Spinner.render(frame, style: :line, theme: theme),
  text("Loading…", fg: theme.dim.fg)
])
```

### Load-Absorb Behavior While Posts Are Nil/Empty
```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
if posts == [] do
  {:update, state, []}
else
  ...
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline theme/domain extraction in screen files | `Theme.from_state/1` + `Screens.Domain.get/2` | Phase 0 workstream prelude (2026-04-21) [VERIFIED: .planning/workstreams/phase-03-screen-audit/STATE.md; .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md] | Lower duplication and consistent fallback contracts in per-screen audits. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:35,163-167] |
| Plain `"Loading posts..."` text | Spinner adoption now required for Phase 9 | Locked in Phase 9 context (2026-04-22) [VERIFIED: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md:D-05] | Plan must introduce spinner without row/region growth. [VERIFIED: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md:D-06] |

**Deprecated/outdated:**
- Direct inlined `get_in(ctx, [:domain, ...])` lookups in PostReader are considered outdated for this audit; helper-based lookup is required. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md:160]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| None | All claims in this research were verified from repository artifacts in this session. [VERIFIED: paths in Sources] | — | — |

## Open Questions

1. **Should PostReader spinner animate by frame counter (monotonic-time like BoardList) or fixed frame like ThreadList?**
   - What we know: Both patterns exist in current screens. [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex:37; lib/foglet_bbs/tui/screens/thread_list.ex:42]
   - What's unclear: Which variant best fits PostReader flush/load phases under sparseness constraints.
   - Recommendation: Use one-row spinner+label and pick monotonic frame counter for visible progress, then lock with deterministic tests around rendered text presence (not exact glyph frame). [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex]

2. **How explicit should callback ownership proof be when App handles command tasks directly?**
   - What we know: Context locks callbacks as intentional public surface.
   - What's unclear: Whether tests should assert App references these callbacks or only screen-level semantics.
   - Recommendation: Add/keep screen tests for callback behavior and App tests for command task tuple behavior; avoid forcing direct App->callback call linkage that no longer exists in current architecture. [VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs; test/foglet_bbs/tui/app_test.exs:580-593]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | Compile/tests/precommit | ✓ [VERIFIED: `elixir --version`] | 1.19.5 [VERIFIED: `elixir --version`] | — |
| Mix | Task runner (`mix test`, `mix precommit`) | ✓ [VERIFIED: `mix --version`] | 1.19.5 [VERIFIED: `mix --version`] | — |
| Erlang/OTP | Runtime for app/tests | ✓ [VERIFIED: `elixir --version`] | 28 [VERIFIED: `elixir --version`] | — |

**Missing dependencies with no fallback:**
- None identified for this phase. [VERIFIED: local command checks]

**Missing dependencies with fallback:**
- None identified for this phase. [VERIFIED: local command checks]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (bundled with Elixir 1.19.5) [VERIFIED: `elixir --version`; test/foglet_bbs/tui/screens/post_reader_test.exs] |
| Config file | none — standard Mix/ExUnit defaults with `test/test_helper.exs` [VERIFIED: test/test_helper.exs] |
| Quick run command | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` [VERIFIED: test path exists] |
| Full suite command | `mix test` (plus `mix precommit` as phase gate) [VERIFIED: mix.exs:79-87] |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| READER-01 | Helper usage + fallback parity in load/flush/parse paths | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs -x` | ✅ [VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs] |
| READER-02 | Callback contract for `load_posts/2` and `flush_read_pointers/2` | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs -x` | ✅ [VERIFIED: tests at lines 90-93,143-157] |
| READER-03 | Spinner shown for loading states without row growth | unit/smoke | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs -x` | ❌ Wave 0 [VERIFIED: spinner assertion absent currently] |
| READER-04 | Post pipeline unchanged (`PostCard` + markdown + viewport) | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs -x` | ✅ [VERIFIED: tests at lines 216-290,376-440] |
| READER-05 | No render-path mutation | static + unit | `rg -n 'defp render_|put_in\\(|%\\{state \\|' lib/foglet_bbs/tui/screens/post_reader.ex` and `mix test ...` | ❌ Wave 0 (no explicit purity assertion) |
| READER-06 | Audit rubric + full quality gate | lint/type/security | `mix precommit` | ✅ [VERIFIED: mix.exs:80-87] |
| READER-07 | Moduledoc documents load-absorb behavior | unit/static | `rg -n 'load-absorb|absorb' lib/foglet_bbs/tui/screens/post_reader.ex` | ❌ Wave 0 (moduledoc note missing) |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Per wave merge:** `mix test`
- **Phase gate:** `mix precommit` before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/screens/post_reader_test.exs` — add spinner-loading assertions for READER-03.
- [ ] `test/foglet_bbs/tui/screens/post_reader_test.exs` — add render-purity contract checks for READER-05.
- [ ] `test/foglet_bbs/tui/screens/post_reader_test.exs` or static gate docs — add explicit callback ownership/proof framing for READER-02/07.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no [VERIFIED: phase scope excludes auth feature changes] | Existing auth/session model unchanged in this phase. [VERIFIED: .planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md Out of Scope] |
| V3 Session Management | no [VERIFIED: phase scope and target files] | No session protocol changes planned; only screen-level read/flush interactions. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] |
| V4 Access Control | yes [VERIFIED: flush uses user/thread/board IDs] | Keep current pointer flush path through domain modules with user-scoped IDs. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:222-250] |
| V5 Input Validation | yes [VERIFIED: markdown render guard + key handling guards] | Keep `Code.ensure_loaded` + `function_exported?` guard and bounded key handlers. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:315-325,99-148] |
| V6 Cryptography | no [VERIFIED: no crypto operations in PostReader scope] | N/A for this phase’s target files. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] |

### Known Threat Patterns for Elixir Server-Side TUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| UI freeze from synchronous DB/domain calls on navigation exit | Denial of Service | Keep `{:flush_read_pointers, ctx}` handled via `Command.task` in App. [VERIFIED: lib/foglet_bbs/tui/app.ex:469-478] |
| Unsafe dynamic module call surface from session context domain injection | Tampering | Keep helper/fallback matching and function-existence guards before dynamic calls. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:163-167,210-220,315-321] |
| Render-state corruption from mutation during render | Tampering | Enforce no write operations in `render_*`; mutations only in dedicated helpers. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex:77-83,330-338,363-433] |

## Sources

### Primary (HIGH confidence)

- [.planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-CONTEXT.md] - locked decisions and scope.
- [.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md] - READER requirements and inherited audit rubric.
- [.planning/workstreams/phase-03-screen-audit/ROADMAP.md] - phase success criteria and sequencing constraints.
- [lib/foglet_bbs/tui/screens/post_reader.ex] - current implementation contracts for loading, rendering, mutation boundaries.
- [test/foglet_bbs/tui/screens/post_reader_test.exs] - existing coverage and test seams.
- [lib/foglet_bbs/tui/app.ex] - command-task ownership for load/flush.
- [lib/foglet_bbs/tui/screens/board_list.ex] and [lib/foglet_bbs/tui/screens/thread_list.ex] - accepted spinner usage patterns.
- [lib/foglet_bbs/tui/widgets/progress/spinner.ex] and [docs/raxol/getting-started/WIDGET_GALLERY.md] - spinner API and usage semantics.
- [CLAUDE.md], [AGENTS.md], [mix.exs], [mix.lock], [.planning/config.json] - project constraints, gates, and stack versions.

### Secondary (MEDIUM confidence)

- None.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Versions are pinned and directly read from local runtime/lockfiles.
- Architecture: HIGH - Directly validated against `post_reader.ex`, `app.ex`, and locked context docs.
- Pitfalls: HIGH - Derived from current implementation plus workstream rubric and prior research artifacts.

**Research date:** 2026-04-22
**Valid until:** 2026-05-22

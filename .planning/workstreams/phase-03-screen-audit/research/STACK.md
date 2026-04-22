# Stack Research — phase-03-screen-audit

**Domain:** Retrospective screen audit + styling polish on an existing, validated Elixir/Phoenix/Raxol TUI
**Researched:** 2026-04-21
**Confidence:** HIGH

## TL;DR

**No stack additions are needed for this workstream.** The existing toolchain
(`mix precommit` → `compile --warnings-as-errors` + `format` + `credo --strict`
+ `sobelow` + `dialyzer`, plus ExUnit with the catalog smoke test and per-widget
D-18 theme-hygiene tests) already covers every correctness and styling
constraint this audit enforces. Adding tooling here would be ceremony, not
leverage — the audit is 9 screens, done once, against a widget library that
already carries its own conformance tests.

Proceed directly to per-screen audit phases. No preliminary tooling phase is
warranted.

## Evaluation — Candidate Tools

Each candidate is evaluated against the two concrete goals of this workstream:
(a) idiomatic Elixir correctness across 9 screen modules, and
(b) styling adoption of `Foglet.TUI.Widgets.*` + `Foglet.TUI.Theme`.

| Candidate | Verdict | Rationale |
|-----------|---------|-----------|
| **Recode** (automated AST rewrites) | Reject | Recode earns its keep for wide-surface-area refactors across dozens/hundreds of modules. This audit touches 9 files, once. Human review + `credo --strict` suffices, and an auto-rewrite pass would obscure the intentional read of each screen that the audit *is*. |
| **Custom Credo checks** (e.g. "no hardcoded color atoms") | Reject | The invariant is already enforced transitively: screens compose widgets, widgets carry their own D-18 theme-hygiene tests, so a screen that hardcodes a color atom would have to bypass the widget layer — which is exactly what the audit itself is checking for. Writing a custom Credo plugin is more effort than eyeballing 9 files. |
| **Boundary** (sasa1977/boundary) | Reject | Could in principle enforce "screens depend only on `Foglet.TUI.Widgets.*` and `Raxol.View.Elements`, never into `Raxol.UI.*` internals." But scope is trivially small; the rule can be stated in prose in each phase's CONTEXT and spot-checked with a `grep`. Boundary is a meaningful config + CI investment and would need a dedicated phase — not proportional to a 9-screen audit. |
| **ExUnit snapshot testing for TUI output** (`mneme`, `snapshy`, hand-rolled) | Reject | Snapshot testing is attractive for rendering regressions, but: (i) it locks down ANSI byte output *right as* upcoming milestones (Phase 4 Presence, Phase 5 Chat, Phase 6 DMs, Phase 9 Search/Oneliners) are about to mutate every screen's layout, so snapshots would churn constantly; (ii) `phase-03-polish` Phase 8 already deliberately chose the catalog smoke test + per-widget theme-hygiene path over snapshotting; (iii) the audit's primary output is *structural* (uses `ScreenFrame`? routes colors via `Theme`?) which is covered by focused assertions, not byte-for-byte snapshots. |
| **`mix xref` / `mix compile.traces`** | Already available | Ships with Mix. If a screen's widget-dependency graph comes up in review, use it ad-hoc — no install needed. |
| **`ex_unit_notifier` / test-watch tools** | Optional, out of scope | Personal dev ergonomics, not workstream-blocking. Not recommending a project-level addition. |

## What We Already Have (Sufficient For This Audit)

### Correctness substrate — covers (a)

| Tool | Catches |
|------|---------|
| `mix compile --warnings-as-errors` | Unused vars/aliases, missing `@impl`, deprecated API warnings |
| `mix format` | Formatting drift |
| `mix credo --strict` | Predicate naming, `String.to_atom/1` misuse, list-Access warnings, refactor opportunities, consistency rules |
| `mix sobelow --exit Low` | Security anti-patterns (mostly Phoenix-web, low hit rate on TUI but zero cost) |
| `mix dialyzer` (`:error_handling`, `:underspecs`, `:unmatched_returns`, `:unknown`) | Type contract violations across screen ↔ widget boundary |

This is stronger than most Elixir projects ship with. The audit should lean on it rather than add to it.

### Styling/primitive-adoption substrate — covers (b)

| Test file | Role |
|-----------|------|
| `test/foglet_bbs/tui/widgets/catalog_smoke_test.exs` | Cross-bucket smoke render — every widget renders without raising under a default theme |
| `test/foglet_bbs/tui/widgets/**/*_test.exs` (D-18) | Per-widget theme-hygiene + smoke — widgets route all colors through `Theme` slots |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | Top-level screen-composition smoke |
| `test/foglet_bbs/tui/screens/**` | Per-screen behavioural tests |

For each screen-audit phase, the pattern is already established: add targeted
assertions against the screen's composition (e.g. "renders a `ScreenFrame`
wrapping `StatusBar` + content + `KeyBar`", "does not hardcode a color atom"
via `String.contains?/2` on the module source if needed, or more cleanly, via
an assertion that the screen threads `theme:` into every widget call).

## Installation

**None.** `mix.exs` requires no changes for this workstream.

## Alternatives Considered

See "Evaluation — Candidate Tools" above — each candidate was weighed and rejected with specific rationale.

## What NOT to Add

| Avoid | Why | What to Do Instead |
|-------|-----|--------------------|
| Snapshot testing library | Locks down ANSI output exactly as Phases 4/5/6/9 prepare to mutate every screen | Use focused structural assertions (widget composition, theme threading) — the pattern used in existing screen tests |
| Boundary (`:boundary`) | Heavy config investment disproportionate to a 9-file audit | Prose rule in each phase CONTEXT + `grep` spot-check in verification |
| Custom Credo check plugin | Widget-layer D-18 tests already enforce the "no hardcoded color atom" invariant transitively | Trust the existing widget tests; review screen modules by eye for direct Raxol color atom use |
| Recode | Built for sweeping multi-module rewrites; audit scope is 9 files done deliberately once | Hand-edit each screen as part of its audit phase |
| A new dev dep of any kind | Every dep is a long-term carrying cost; this workstream ships no new runtime or test surface | Stop at the assessment — that's a valid research outcome |

## Sources

- `mix.exs` (verified 2026-04-21) — current deps list; no snapshot/Boundary/Recode present
- `CLAUDE.md` project guidelines — precommit aliases confirmed
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — confirms Phase 8 deliberately chose catalog smoke + D-18 theme-hygiene over snapshot testing
- `lib/foglet_bbs/tui/widgets/README.md` — confirms D-18 per-widget theme-hygiene test convention
- `test/foglet_bbs/tui/widgets/catalog_smoke_test.exs` (exists) — confirms catalog smoke is wired
- Conceptual fit of Recode / Boundary / Mneme evaluated against workstream scope (9-file, one-shot audit) — not verified via Context7 because recommendation is to *not* add them

---
*Stack research for: phase-03-screen-audit (polish workstream inside v1.0 milestone)*
*Researched: 2026-04-21*

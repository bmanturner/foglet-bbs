# Quick Task 260426-jdz: Fix board breadcrumb view error - Context

**Gathered:** 2026-04-26
**Status:** Ready for planning

<domain>
## Task Boundary

Fix the production TUI view error:

`{:view_error, %UndefinedFunctionError{module: Foglet.Boards.Board, function: :fetch, arity: 2}}`

</domain>

<decisions>
## Implementation Decisions

### Error Scope
- Treat this as a focused TUI rendering bug caused by Access-style struct field lookup.

### Validation
- Add a regression test with `%Foglet.Boards.Board{}` so the breadcrumb path accepts domain structs as well as plain maps.

### Agent Discretion
- Keep the fix minimal and localized to the crash site unless investigation finds the same unsafe pattern in an adjacent rendering path.

</decisions>

<specifics>
## Specific Ideas

The reported module/function pair points to `board[:name]` or equivalent dynamic Access lookup on a `%Foglet.Boards.Board{}` struct. Use `Map.get/3` or field access instead.

</specifics>

<canonical_refs>
## Canonical References

- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`

</canonical_refs>

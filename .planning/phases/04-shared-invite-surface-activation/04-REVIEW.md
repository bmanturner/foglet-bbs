---
phase: 04-shared-invite-surface-activation
reviewed: 2026-04-24T02:02:58Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/state.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_actions.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/shared/invites_actions_test.exs
  - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-04-24T02:02:58Z
**Depth:** standard
**Files Reviewed:** 14
**Status:** issues_found

## Summary

Reviewed the shared invite surface activation across Account, Moderation, Sysop, shared invite state/actions/rendering, and the associated DB-backed and render tests. The shared action module keeps invite persistence behind `Foglet.Accounts`, and the Account/Sysop paths have direct coverage for visibility, generation, refresh, and delegation.

One behavioral policy mismatch remains in Moderation: the shell uses the global invite visibility predicate, which treats sysops as invite-visible under every policy. That contradicts this phase's Moderation rule and is not covered by the current Moderation tests.

## Warnings

### WR-01: Moderation INVITES is exposed to sysops outside the `mods` policy

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:174`
**Issue:** `synced_screen_state/1` calls `ShellVisibility.invites_visible?/2` to decide whether to append the Moderation `INVITES` tab. That predicate returns true for `%{role: :sysop}` regardless of `invite_code_generators`, so a sysop routed to Moderation gets the `INVITES` tab even when the policy is `sysop_only` or `any_user`. The module docs and phase context say Moderation appends `INVITES` only when `invite_code_generators == "mods"` and the actor is a moderator. Sysops already have their own Sysop invite surface, so this creates drift between the intended surface ownership and the runtime UI.
**Fix:** Use a Moderation-specific visibility predicate instead of the global invite predicate, and add regression coverage for sysop users on the Moderation screen:

```elixir
defp moderation_invites_visible?(state) do
  case {Map.get(state, :current_user), Map.get(state, :session_context)} do
    {%{role: :mod}, %{invite_code_generators: "mods"}} -> true
    _ -> false
  end
end

# in synced_screen_state/1
labels = State.tab_labels(moderation_invites_visible?(state))
```

If the config fallback is required when `session_context` lacks the policy, keep the same role restriction and resolve the policy first:

```elixir
defp moderation_invites_visible?(%{current_user: %{role: :mod}} = state) do
  ShellVisibility.invites_visible?(state.current_user, state.session_context)
end

defp moderation_invites_visible?(_state), do: false
```

Then add tests asserting `%User{role: :sysop}` does not see Moderation `INVITES` under `sysop_only`, `mods`, or `any_user`, while `%User{role: :mod}` still sees it under `mods`.

---

_Reviewed: 2026-04-24T02:02:58Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

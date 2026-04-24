---
phase: 11
slug: posting-policy-enforcement
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit bundled with Elixir 1.19.5 |
| **Config file** | `test/test_helper.exs`, `test/support/data_case.ex` |
| **Quick run command** | `rtk mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~30 seconds for quick run; precommit runtime depends on Dialyzer cache |

---

## Sampling Rate

- **After every task commit:** Run the narrow test command for the changed context or TUI screen file.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** 60 seconds for narrow tests, excluding precommit Dialyzer cache cost.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 0 | POST-01 | T-11-01 | Rejected thread creation does not allocate message numbers or persist rows. | context | `rtk mix test test/foglet_bbs/threads/threads_test.exs` | ✅ | ⬜ pending |
| 11-01-02 | 01 | 0 | POST-02, POST-03 | T-11-02 / T-11-03 | Rejected replies and locked-thread denials do not allocate message numbers or persist rows. | context | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | ✅ | ⬜ pending |
| 11-02-01 | 02 | 0 | POST-04 | T-11-04 | TUI displays clear policy and locked-thread errors without success navigation. | screen/unit | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/threads/threads_test.exs` — POST-01 policy matrix and no-side-effect assertions.
- [ ] `test/foglet_bbs/posts/posts_test.exs` — POST-02/POST-03 policy, lock, counter, and no-side-effect assertions.
- [ ] `test/foglet_bbs/tui/screens/post_composer_test.exs` — locked-thread copy and posting-policy denial expectations.
- [ ] `test/foglet_bbs/tui/screens/new_thread_test.exs` — posting-policy denial copy and no-success-navigation expectations.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags.
- [x] Feedback latency < 60s for narrow tests.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending

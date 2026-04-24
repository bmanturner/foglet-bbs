---
phase: 06-chrome-clock-and-main-menu-wiring
reviewed: 2026-04-24T03:17:51Z
depth: standard
files_reviewed: 7
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 06: Code Review Report

## Summary

Reviewed the Phase 06 chrome clock and main-menu wiring changes at standard depth.

## Warnings

### WR-01: Main-menu status bar can crash when rendered with real App struct state

**File:** `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`

`clock_instant/1` used `get_in/2` on the real `%Foglet.TUI.App{}` state path. Structs do not implement `Access`, so the runtime main-menu render path could raise even though plain-map widget tests passed.

**Resolution:** Fixed after review by switching to `Map.get/3` for `state.session_context` and adding a regression test with `%Foglet.TUI.App{}`.

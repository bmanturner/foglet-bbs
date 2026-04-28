---
status: complete
created: 2026-04-28
quick_id: 260428-fc5
slug: the-clock-isn-t-defaulting-to-foglet-def
---

Fix unauthenticated chrome clock timezone fallback.

## Tasks

- Confirm the guest clock path bypasses session preference defaults.
- Update chrome clock fallback timezone to use `:foglet_bbs, :default_timezone`.
- Run existing focused status bar coverage without adding new tests.
- Run targeted tests, then `rtk mix precommit`.
- Update quick task summary and commit atomically.

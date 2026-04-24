# Phase 14 Blocker Log

No upstream Phase 9-13 blockers found during Plan 14-01.

No upstream Phase 9-13 blockers found during Plan 14-02. Existing focused
tests cover delivery-mode copy, break-glass user status authorization,
posting-policy terminal errors, SSH key lifecycle/authentication behavior, and
board subscription required-board enforcement.

No upstream Phase 9-13 blockers found during Plan 14-03. The root README now
surfaces SMTP mode, no-email mode, break-glass Mix tasks, nested-doc status, and
unsupported v1.2 launch caveats.

## Critical Blocker: False Reset-Password URL Promise

| Owning Phase | Requirement | Missing Evidence | Phase 14 Action | Responsible Party |
|--------------|-------------|------------------|-----------------|-------------------|
| Phase 9 / Phase 14 | MAIL-04, MAIL-06, HYGN-02, HYGN-03 | `mix foglet.user.reset_password HANDLE` prints `https://<host>/users/reset_password/<token>`, but Foglet has no supported HTTP reset-password interaction and no TUI token-consumption path. Tests also assert the fake `/users/reset_password/` URL output. | BLOCKER. Do not document this as a launch-capable break-glass workflow. Remove/change the task output and rewrite/delete URL-asserting tests unless a real SSH/TUI token consumption flow exists. | Codex during Phase 14 execution missed this false promise, documented it in README operator notes, and initially marked related tests as evidence instead of a blocker. |

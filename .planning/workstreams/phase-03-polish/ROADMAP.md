commit 3e3dd1a7f9fdd5a28d9f366ce1e2e745f6728594
Author: Brendan Turner <bfturner@foglet.io>
Date:   Mon Apr 20 13:51:40 2026 -0500

    docs(05-01): complete SizeGate module + App.view/1 cond branch plan

diff --git a/.planning/workstreams/phase-03-polish/ROADMAP.md b/.planning/workstreams/phase-03-polish/ROADMAP.md
index a54bb23..4399723 100644
--- a/.planning/workstreams/phase-03-polish/ROADMAP.md
+++ b/.planning/workstreams/phase-03-polish/ROADMAP.md
@@ -78,7 +78,7 @@ v1.0.1 is a polish/hardening pass on the SSH + Raxol TUI delivered in the main w
   2. Resizing back above the threshold restores the exact prior screen — selected row, composer draft, scroll position — with no state loss
   3. Alt-screen takeover survives resize events without border fragments or stuck frame redraws
 **Plans**: 2 plans
-- [ ] 05-01-PLAN.md — SizeGate module + App.view/1 cond branch (creates the visible gate)
+- [x] 05-01-PLAN.md — SizeGate module + App.view/1 cond branch (creates the visible gate)
 - [ ] 05-02-PLAN.md — Same-size guard + key-swallow guard + MultiLineInput preservation regression test (locks in state safety)
 **UI hint**: yes
 
@@ -106,5 +106,5 @@ Recommended order: 1 → 2 → 3 → 4 → 5 → 6.
 | 2. Markdown rendering correctness | 0/3 | Complete    | 2026-04-20 |
 | 3. Read-pointer correctness + thread-row enrichment | 4/4 | Complete | 2026-04-20 |
 | 4. Composer & thread creation end-to-end | 4/4 | Complete    | 2026-04-20 |
-| 5. Terminal size gate | 0/2 | Planned | - |
+| 5. Terminal size gate | 1/2 | In Progress | - |
 | 6. Email verification toggle + resend | 0/TBD | Not started | - |

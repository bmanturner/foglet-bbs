# FOG-134 content review: README and HTTP landing page

## Acceptance criteria used

- README explains what Foglet is, how to try the public BBS, what exists today, how to run locally, and what is intentionally not present yet.
- Landing page keeps the GitHub link and makes `ssh bbs.foglet.io` prominent.
- SSH public-key authentication is presented clearly and attractively without overstating behavior.
- The HTTP page is framed as a lobby/window into an SSH-first BBS, not a web forum UI.
- Fake shortcuts, fake links, and implied unavailable actions are removed.
- Product claims are grounded in the current source tree.

## Voice and tone rubric

Foglet copy should feel:

- Strange, but usable: atmospheric language can set the scene, but the command and project facts must stay plain.
- Terminal-native: prefer concrete SSH/TUI language over generic community-platform language.
- Human-scale: emphasize one instance, one sysop, named boards, and a place people enter.
- Honest pre-alpha: say what exists and what does not; avoid apology language that makes the project feel abandoned.
- Old-network, not cosplay: modern Elixir/OTP/Postgres/Phoenix details are acceptable when they explain reliability or boundaries.

Examples used in this pass:

- "there is a door in the fog" sets the mood, immediately followed by `ssh bbs.foglet.io`.
- "the web is only the porch light" frames the landing page without implying a browser client.
- "your ssh-agent can knock" makes public-key auth memorable while still explaining setup and fallback.
- "pre-alpha, live, and honest about its edges" is more inviting than a generic warning label.

## Source grounding inspected

Static inspection only unless noted otherwise:

- `lib/foglet_bbs/ssh/key_cb.ex`, `lib/foglet_bbs/accounts/ssh_key.ex`, and account SSH key TUI files show SSH public-key auth and key management exist.
- `lib/foglet_bbs/tui/screens/` includes login, register, verify, account, board list, thread list, post reader, post composer, sysop, moderation, and shared invites surfaces.
- `lib/foglet_bbs/oneliners.ex` and `lib/foglet_bbs/oneliners/entry.ex` show persisted oneliners exist.
- `lib/foglet_bbs/boards/subscription.ex` and related board/thread/post contexts support subscriptions, read pointers, and board/thread/post workflows.
- `lib/foglet_bbs_web/controllers/page_html/home.html.heex` was the HTTP landing page source updated by this pass.

## Product claims intentionally avoided

Avoided or removed because the current source did not support the stronger public claim during this review:

- Direct messages / private mail.
- `@handle` mentions with notifications.
- Opt-in email digests.
- Global lobby chat and per-board chat rooms.
- Presence claims such as a public who's-online feature on the landing page.
- Oban jobs, scheduled cleanups, retention policies, and delivery retry queues.
- Federation, hosted Foglet cloud, browser admin console, mobile app, and end-user web forum UI.
- Fake landing-page keyboard shortcuts such as `[D]ocs` or `[K]nock` without actual actions.

## Copy review checklist

- [x] Public invite appears as `ssh bbs.foglet.io` in README and landing page.
- [x] GitHub link remains `https://github.com/bmanturner/foglet-bbs`.
- [x] README includes local development setup and SSH connection instructions.
- [x] README explicitly lists unavailable capabilities.
- [x] Landing page treats web as lobby/window, not as the product UI.
- [x] Public-key auth copy names setup requirement and password fallback.
- [x] Removed fake bottom-bar shortcuts.
- [x] Avoided feature claims not verified in source.

## Handoff notes for CTO / implementation

- The copy pass changes only README/docs and HEEx copy. CSS/JS were not changed.
- Landing page still uses the existing visual system and classes. If the implementation owner wants stronger visual hierarchy, the copy is structured around five sections that can be styled without changing the IA.
- The bottom bar now uses plain factual text instead of shortcut hints, because the previous `[D]ocs` and `[K]nock` labels implied actions that did not exist.
- Residual risk: this was source-grounded static review. I did not validate a live rendered browser page beyond compile/format checks.

## Follow-up backlog

None from this content pass. The removed aspirational claims should stay out of public copy until product owners explicitly ship and verify those capabilities.

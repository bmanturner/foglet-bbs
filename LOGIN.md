```text
┌ Foglet ──────────────────────────────────────────────────── guest | 12:52 PM ┐
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                               you are outside.                               │
│                              knock or hang up.                               │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└ Q Quit   L Login  R Register  F Forgot password  T Reset token ──────────────┘
```

## Issues / Desired Fixes

- Consolidate Forgot password and Reset token into a single page, since they are closely related.
- Add this ascii artwork as a placeholder for now. Centered properly:
                   ______              __      __
                  / ____/___  ____ _  / /___  / /_
                 / /_  / __ \/ __ `/ / / __ \/ __/
                / __/ / /_/ / /_/ / / /  __/ /_
               /_/    \____/\__, / /_/\___/\__/
                           /____/

                      -- you are outside --
                         knock or hang up.

## Empty Space Ideas

- Show a small "signal panel" with live system state: uptime, connected sessions, active boards, recent post count, and whether registrations are open.
- Render a slow ASCII fog bank that drifts behind or around the center copy, subtle enough that the login options still feel calm.
- Display a rotating one-line excerpt from the newest public post, with author and board omitted or anonymized until login if privacy matters.
- Show "lights in windows": a tiny city/building silhouette where lit windows map to currently active sessions or recently active boards.
- Turn the center into a porch/door scene: the existing "you are outside. knock or hang up." copy sits under a static ASCII doorway, with the command bar as the actual doorbell.
- Add a presence constellation: each online user is a dim star, moderators/sysops are brighter points, and recent activity creates short-lived trails.
- Show a compact BBS bulletin strip: "3 boards active today", "12 unread public threads", "last post 4m ago", "2 people online".
- Render a static ANSI-art Foglet mark or wordmark, tuned for 80x24, then let wider terminals expand into richer art.
- Use the empty space as a "message of the day" panel sourced from runtime config, so sysops can set announcements without code changes.
- Show a read-only public board teaser: newest thread titles from boards visible to guests, if guest visibility becomes an intentional product decision.
- Animate a cursor/prompt vignette: a terminal prompt types and deletes small phrases like `connect`, `identify`, `enter`, `listen`.
- Show system weather rather than literal weather: "quiet", "busy", "new arrivals", "maintenance soon", derived from recent activity and config.
- Make the art reflect time of day: sparse stars at night, pale fog in morning, heavier static at late hours, all deterministic and low-cost.
- Show invite/registration state artistically: an open gate when registration is open, a locked gate when invite-only, a lantern when password reset is available.
- Add a tiny "carrier signal" waveform whose amplitude responds to current session count or PubSub activity.
- Use the space for first-run onboarding only when the system has no users yet: a sysop setup prompt, then disappear forever after setup.
- Show a minimal public stats dashboard: total boards, total threads, total posts, newest board, newest thread age.
- Create a slow "radar sweep" of recent activity by board category, where blips appear when posts are created.
- Use a poem-like static welcome that matches the terse current voice, changing rarely and stored in config.
- Let sysops choose the login composition mode: `minimal`, `motd`, `stats`, `presence`, `art`, or `hybrid`.
- Show a "who's around" count without handles: "5 present", "2 writing", "1 sysop watching", preserving privacy before authentication.
- Render a board map: categories as rooms/hallways, with brightness showing recent posting activity.
- Show local node/network status if federation ever lands: connected peers, sync health, and last replicated event.
- Use the space for a safety/status banner only when needed: maintenance mode, registrations closed, degraded database, email delivery disabled.
- Build a seasonal/static art slot that can be customized per instance, making each Foglet feel like a particular place rather than a generic product.
- Mix presence and art: a foggy field of dots where every visible dot is either an active session, a recent post, or a board with unread activity.
- Mix MOTD and motion: the message is carved into fog/static, periodically becoming clearer, then dissolving.
- Mix stats and doorway art: the doorway stays static, but small labels around it update with online count, newest post age, and registration mode.
- Mix public teaser and privacy: show thread shapes and activity levels without titles until login, like "board 3: two fresh threads".
- Keep one deliberately empty mode: the blank space is part of the mood, with only the two-line welcome, for instances that want the stark threshold feeling.

## Login Mode Render

```text
┌ Foglet ▸ Login ──────────────────────────────────────────── guest | 01:08 PM ┐
│Handle:   ▌                                                                   │
│Password:                                                                     │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└ Navigate  Enter Submit/Next   Esc Cancel   Field  Tab Switch field ──────────┘
```

## Login Mode Issues / Desired Fixes

- Remove `Enter` as a next-field action. `Tab` should focus the next field, `Shift+Tab` should focus the previous field, and `Enter` should attempt to submit the form regardless of which field is focused.

## Register Mode Render

```text
┌ Foglet ▸ Register ───────────────────────────────────────── guest | 01:20 PM ┐
│Handle:           ▌                                                           │
│Email:                                                                        │
│Password:                                                                     │
│Confirm password:                                                             │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└ Navigate  Enter Next/Submit   Esc Cancel   Field  Tab Switch field ──────────┘
```

## Register Mode Issues / Desired Fixes

- Add a centered panel titled `Create Identity`; make it wide enough to fit the form comfortably, including a 20-character handle field.
- When an SSH public key has been detected, show a checkbox asking `Register SSH PubKey?`.
- If checked, successful registration should add the detected SSH public key to the database for the new user.
- If account verification is required, subsequent SSH logins with that key should still redirect to the verify screen until verification is complete.
- Verify form validation. No duplicate usernames allowed, no duplicate SSH pubkeys allowed, etc.
- Remove `Enter` as a next-field action. `Tab` should focus the next field, `Shift+Tab` should focus the previous field, and `Enter` should attempt to submit the form regardless of which field is focused.
- The cursor seems misplaced. It's far to the right of where the input begins.
- Across the top (1 line padding from chrome) explain the registration mode

## Invite Mode Render

```text
┌ Foglet ▸ Register ───────────────────────────────────────── guest | 01:39 PM ┐
│Invite code: ▌                                                                │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└ Navigate  Enter Submit   Esc Cancel ─────────────────────────────────────────┘
```

## Invite Mode Issues / Desired Fixes
- Move form to centered panel with title 'Carry a Code?'
- Use same form input as Verify mode

## Verify Mode Render

```text
┌ Foglet ▸ Verify ─────────────────────────────────────────── guest | 01:43 PM ┐
│Enter the 6-character verification code:                                      │
│                                                                              │
│  [█_____]                                                                    │
│                                                                              │
│Attempts: 0/5                                                                 │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└ Navigate  Enter Submit   Esc Cancel   Backspace Delete ──────────────────────┘
```

## Verify Mode Issues / Desired Fixes
- Remove 'Enter the 6-character verification code:'
- Place form in centered panel with title 'Confirm the Knock'
- There's supposed to be a resend functionality on this page.
- Remove 'Backspace Delete' from the command bar.
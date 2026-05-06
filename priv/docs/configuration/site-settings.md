%{
  title: "Site settings",
  weight: 20
}
---

Site settings are the live, sysop-editable configuration values stored in
Postgres and read through `Foglet.Config`. They change site behavior without a
redeploy. Secrets and deployment wiring still belong in environment variables,
not here.

Sysops edit these values from the SSH TUI Sysop workspace. The SITE tab covers
registration, invites, email delivery, verification, guest access, and invite
caps. The LIMITS tab covers numeric posting and verification limits.

## How live settings are stored

Foglet stores runtime settings in the `configuration` table as JSON values and
caches reads in an ETS table. A write goes to Postgres first, then invalidates
the cached key so the next read sees the new value.

Interactive writes use `Foglet.Config.put(actor, key, value)`, which checks that
the actor may edit site configuration. Sysops may edit these values; demoted or
non-sysop users are rejected even if the UI is still visible in an old session.

Trusted setup paths such as seeds and tests use `Foglet.Config.put!/3`. Public
operators should normally use the TUI, not hand-edit the database.

## SITE settings

| Setting | Stored key | Default | Values | Notes |
| --- | --- | --- | --- | --- |
| Account registration | `registration_mode` | `open` | `open`, `invite_only`, `sysop_approved` | Controls how new accounts enter the system. |
| Invite code generators | `invite_code_generators` | `sysop_only` | `sysop_only`, `mods`, `any_user` | Controls who may create invite codes. |
| Email delivery | `delivery_mode` | `no_email` | `email`, `no_email` | Controls whether Foglet attempts transactional email. SMTP environment variables still decide whether an actual SMTP adapter is available. |
| Require email verification | `require_email_verification` | `false` | boolean | When true, new registrations must verify by email before gaining access. This cannot be enabled while Email delivery is set to `no_email`. |
| Guest mode | `guest_mode_enabled` | `true` | boolean | Allows unauthenticated visitors to enter read-only Guest Mode. Can be overridden at boot by `FOGLET_GUEST_MODE_ENABLED`. |
| Invite generation cap | `invite_generation_per_user_limit` | `0` | integer, minimum `0` | Applies when Invite code generators is `any_user`. `0` means unlimited. Hidden in the SITE tab unless any-user invite generation is selected. |

The SITE screen uses operator-facing labels such as "Open — anyone can sign up"
and "No email (offline mode)". The stored values remain the raw keys shown in
the table.

## LIMITS settings

| Setting | Stored key | Default | Constraint | Notes |
| --- | --- | --- | --- | --- |
| Post length limit | `max_post_length` | `8192` | integer, minimum `1` | Maximum post body length, in characters. |
| Thread title limit | `max_thread_title_length` | `60` | integer, minimum `1` | Maximum thread title length, in characters. |
| Verification resend wait | `email_verify_resend_cooldown_seconds` | `60` | integer, minimum `1` | Minimum seconds between resend-code requests on the verification screen. |

The LIMITS tab accepts whole numbers only. Enter saves the current set of limit
values. Values below the minimum are rejected before they become active.

## Email and verification must agree

Foglet rejects this combination:

- Email delivery: `no_email`
- Require email verification: `true`

That site would ask new users to verify an email that the system refuses to
send. Change Email delivery to `email` before enabling required verification.

`delivery_mode = email` only tells Foglet to attempt transactional email. For
real delivery, SMTP must also be configured through environment variables and
the application must be restarted with those variables present.

## Guest Mode override

`guest_mode_enabled` is DB-backed and can be changed live. `FOGLET_GUEST_MODE_ENABLED`
is a deploy-time override read at boot. If that environment variable is set,
`Foglet.Config.guest_mode_enabled?/0` returns the environment value instead of
the database value for that boot.

Use the environment override when you need an operational kill switch. Remove it
and restart to return control to the SITE setting.

## Recommended change flow

1. Change one setting at a time from the Sysop workspace.
2. If a setting depends on deployment wiring, confirm the environment first.
   Email delivery is the common case.
3. Test the caller-facing path immediately: register a test account, enter Guest
   Mode, create an invite, or send a test email as appropriate.
4. If the behavior does not match the setting, check application logs and the
   underlying environment variables before changing database rows by hand.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| SITE or LIMITS rejects a save with a permission error | The current account may no longer be a sysop. Log out and back in, or verify roles from an operator task. |
| Email verification cannot be enabled | Email delivery is probably still `no_email`. Set Email delivery to `email` first. |
| Email delivery is `email` but no messages arrive | Confirm SMTP environment variables are set and the application was restarted. Then use the test-email action and inspect logs. |
| Guest Mode remains enabled or disabled after changing SITE | Check whether `FOGLET_GUEST_MODE_ENABLED` is set in the boot environment. |
| Invite cap is not visible | It only appears when Invite code generators is set to "Any signed-in user". |
| Limit field says to enter a whole number | The LIMITS tab accepts integers only; remove decimals, spaces, or units. |

## Do not store secrets here

The runtime configuration table is not a secret store. Keep these in environment
variables or your platform's secret manager instead:

- database URLs
- `SECRET_KEY_BASE`
- SMTP passwords
- SSH host private keys
- reset, invite, or verification tokens

The body coheres from stable parts. Secrets are not one of them.

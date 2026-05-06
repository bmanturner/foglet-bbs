%{
  title: "Email",
  weight: 30
}
---

Foglet uses email for account verification, password reset instructions, account
approval/rejection notifications, pending-approval notices, and sysop test
messages. Email is optional: a small instance can run in no-email mode, but any
flow that requires delivery must stay disabled until SMTP is configured.

There are two separate switches:

- SMTP environment variables wire the mailer adapter at boot.
- The live SITE setting `delivery_mode` decides whether Foglet attempts to send
  transactional mail.

Both must agree before production mail leaves the node.

## Configure SMTP at boot

Set `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST` to enable the SMTP adapter. Without
one of those variables, Foglet uses its compile-time mailer adapter for the
current environment.

```sh
export FOGLET_MAIL_FROM='bbs@example.net'
export FOGLET_SMTP_RELAY='smtp.example.net'
export FOGLET_SMTP_PORT='587'
export FOGLET_SMTP_USERNAME='smtp-user'
export FOGLET_SMTP_PASSWORD='<smtp-password>'
export FOGLET_SMTP_TLS='always'
export FOGLET_SMTP_AUTH='always'
```

Then restart the application. Runtime SMTP settings are read in
`config/runtime.exs` before the supervision tree starts.

## SMTP variable reference

| Variable | Default | Notes |
| --- | --- | --- |
| `FOGLET_MAIL_FROM` | `no-reply@localhost` | Sender address used with the display name `Foglet BBS`. |
| `FOGLET_SMTP_RELAY` | unset | Preferred SMTP relay hostname. Enables the SMTP adapter when set. |
| `FOGLET_SMTP_HOST` | unset | Backward-compatible relay hostname. Used if `FOGLET_SMTP_RELAY` is not set. |
| `FOGLET_SMTP_PORT` | `587` | SMTP port. |
| `FOGLET_SMTP_USERNAME` | unset | SMTP username, if your relay needs one. |
| `FOGLET_SMTP_PASSWORD` | unset | SMTP password. Store it as a secret, not in source or DB-backed config. |
| `FOGLET_SMTP_SSL` | false | Set to `true` or `1` for implicit SSL. |
| `FOGLET_SMTP_TLS` | `if_available` | STARTTLS mode passed to Swoosh as an atom. Common values are `always`, `never`, and `if_available`. |
| `FOGLET_SMTP_AUTH` | `if_available` | SMTP auth mode passed to Swoosh as an atom. Common values are `always`, `never`, and `if_available`. |

Foglet builds SMTP TLS options with peer verification, CA certificates, server
name indication using the relay host, and hostname checking. If your provider
uses a private CA or unusual certificate chain, expect delivery failures until
the host trust store is correct.

## Enable delivery in SITE settings

After SMTP is configured and the application has restarted, sign in over SSH as
a sysop and open the Sysop workspace.

1. Open the SITE tab.
2. Set Email delivery to `Send email`.
3. If desired, set Require email verification to true.
4. With Email delivery selected, press `T` to send a test email to your own
   account email address.

The test email is always sent to the acting sysop's account email. There is no
arbitrary-recipient test action. The message contains no verification codes,
reset tokens, invite codes, passwords, SSH key material, or other secrets.

## No-email mode

The default live setting is `delivery_mode = no_email`. In this mode, Foglet
short-circuits transactional delivery before calling the mailer. This is useful
for local installs, private nodes that handle accounts manually, and deployments
that are not ready to send email.

No-email mode has consequences:

- Required email verification cannot be enabled.
- Verification delivery is unavailable.
- Password reset email is unavailable.
- The sysop test-email action is hidden or reports no-email mode.
- Account flows that depend on email must be handled another way or left off.

Do not enable `require_email_verification` until SMTP is configured and
`delivery_mode` is `email`.

## What Foglet sends

| Message | Trigger | Recipient |
| --- | --- | --- |
| Verification code | Account verification flow when delivery is enabled | The registering user's email address |
| Password reset instructions | Password reset flow when delivery is enabled | The account user's email address |
| Account approved | Sysop approves a pending account | The approved user |
| Registration rejected | Sysop rejects a pending account | The rejected user |
| Pending approval notice | A new account waits for sysop approval | Sysops with email addresses |
| Test email | Sysop presses `T` on SITE Email delivery | The acting sysop's own account email |

Messages are text-only and direct users back to the SSH terminal flow.

## Development and test behavior

In development, the default mailer is Swoosh's local adapter. When development
routes are enabled, captured messages are available in the local Swoosh mailbox
served by Phoenix. This is a developer convenience, not a production mailbox.

In tests, Foglet uses Swoosh's test adapter so assertions can inspect delivered
messages without using a real SMTP server.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Test email action is not available | SITE Email delivery is probably set to no-email mode. Change it to Send email. |
| Test email says to add an email to your account | The acting sysop account has no email address. Add one before testing delivery. |
| Email delivery is enabled but nothing arrives | Confirm `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST` is present at boot, then check SMTP username, password, TLS mode, port, and provider logs. |
| Startup succeeds but provider rejects messages | Check `FOGLET_MAIL_FROM`; many providers require a verified sender domain or exact sender address. |
| TLS or certificate errors appear in logs | Verify the relay hostname matches its certificate and the host trust store has the required CA certificates. |
| Verification cannot be required | Change SITE Email delivery from no-email mode to Send email first. |

Logs for failed sysop test email include the operation, mail type, delivery
mode, recipient user id, and a failure reason. They intentionally avoid logging
message bodies, verification codes, reset tokens, invite codes, or SMTP secrets.

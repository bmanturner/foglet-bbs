# Error Logging and Privacy Rules

Foglet logs at operational boundaries so sysops can diagnose production failures without exposing private user data in log streams.

## Rules

- Log the boundary and operation that failed, not raw payloads.
- Prefer low-cardinality operation names such as `verification_code`, `password_reset`, or `approval_notification`.
- Use internal ids when needed for correlation, for example `recipient_user_id` and `related_user_id`.
- Do not log raw verification codes, reset tokens, invite codes, passwords, session secrets, SSH private material, full email structs/bodies, email addresses, handles, or user-entered free text.
- Keep account-recovery and verification user-facing responses generic where account enumeration is a risk; backend logs may distinguish actual internal delivery attempts from outward generic responses.
- Preserve no-email/operator mode behavior; absence of email delivery is not an error.

## Transactional email boundary

Use `Foglet.Mailer.deliver_transactional/2` for transactional account email. It wraps `Swoosh.Mailer.deliver/1`, returns the same `{:ok, delivery}` or `{:error, reason}` shape, and logs provider/config/network failures as:

`transactional_email_delivery_failed mail_type=<type> delivery_mode=<mode> recipient_user_id=<id> related_user_id=<id> reason=<sanitized reason>`

The wrapper intentionally does not log the `Swoosh.Email` struct because that struct contains addresses and text bodies with one-time codes/tokens.

## Audited boundaries in FOG-666

- Email verification delivery now logs provider failures while returning `{:error, :delivery_failed}` to keep verification UI copy generic.
- Password reset delivery now logs provider failures only after a real active account match and token insert, while callers still receive the generic reset response.
- Pending-registration sysop notifications now log provider failures per sysop recipient without blocking registration.
- Approval and rejection notifications now log provider failures while preserving the existing status-transition result shape.

Broader subsystem observability remains intentionally smaller-scope: existing targeted logs already cover task failures, board-server startup failures, config write failures, SSH/session warnings, and door-runner failures. Larger structured telemetry/error-reporting work should be tracked separately rather than mixed into the transactional email privacy fix.

%{
  title: "Profile and SSH keys",
  weight: 30
}
---

Your account has public profile fields, private account fields, and SSH keys.
Foglet keeps those boundaries separate: a profile card can show public identity
without exposing email addresses, reset tokens, invite metadata, or SSH key
material.

## Open account settings

Open `Account` from the main menu after you sign in. Guests do not have account
settings.

The account screen is split into sections. Use the command bar for the exact
keys on your build; the common pattern is arrows or `j` / `k` to move, `Enter`
to edit or activate, and `Q` or `Esc` to back out.

## Public profile fields

The current profile editor exposes:

- Location
- Tagline
- Real name

Location and tagline are public profile fields. They can appear in public
profile cards along with your handle, handle color, role, post count, karma,
join date, last-seen information, and presence summary.

Real name is account data, not part of the public profile payload used by the
profile-card boundary. Set it only if your sysop asks for it or you are
comfortable storing it on the instance.

When you edit a profile field, Foglet opens a small form for that one field and
saves through the account context. Validation errors return you to the field
with the failed value still visible.

## Public profile cards

Profile cards intentionally whitelist what they show. They exclude:

- Email address
- Password or password-reset state
- Verification codes and metadata
- Invite codes and invite history
- SSH public keys
- Operator-only account details

If a profile card shows a field, treat it as public to other callers who can see
the same post or user surface.

## SSH keys

Foglet can associate SSH public keys with your account so you can authenticate
without typing a password, depending on the sysop's SSH setup.

There are two user-facing paths to know:

- During registration, if your SSH client offers a public key that Foglet does
  not already know, the form can ask whether to save that key to the new
  account.
- After account creation, manage keys from the account screen when key
  management is enabled in your build.

Only public keys belong in Foglet. Never paste a private key into the BBS, a
support request, an issue, or an email. Private keys stay on your machine.

A public key usually starts with `ssh-ed25519`, `ecdsa-sha2-nistp256`, or
`ssh-rsa`, followed by a long blob and an optional comment. Prefer Ed25519 keys
for new accounts unless your client or sysop requires something else.

## Password recovery

From the login menu, press `F` to start password recovery. Enter the email
address on the account. Foglet responds with a privacy-preserving message: if
that email is on file, reset instructions are sent.

If email delivery is disabled, Foglet tells you to contact the sysop for an
operator-assisted reset token. After you have that token, return to the login
menu and press `T` to enter it.

Password reset behavior depends on the sysop's email and verification settings.
If the screen says email is unavailable, the fix is operational; retrying the
same form will not make mail work.

## Keep access recoverable

- Keep at least one current SSH public key on the account if your sysop supports
  key login.
- Keep your email address reachable if the instance uses email verification or
  password reset.
- Ask the sysop to remove old keys when you lose a laptop or rotate credentials.
- Do not share reset tokens. They are credentials until used or expired.

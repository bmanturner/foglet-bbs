%{
  title: "Terminal basics",
  weight: 10
}
---

Foglet is used over SSH. The web server carries public documentation, health
checks, and operator surfaces; the BBS itself is the terminal UI that appears
after you connect.

## Connect over SSH

```sh
ssh your-handle@bbs.example.org -p 2222
```

Your sysop chooses the host name and SSH port. If they run Foglet on the normal
SSH port, omit `-p 2222`.

The first connection may show an SSH host-key warning. Treat it like any other
SSH server: confirm the fingerprint with the sysop before accepting it. Foglet
can also see a public key offered by your SSH client. During registration, an
unmatched offered key can be saved to your new account if you opt in.

## The login screen

The opening menu is short:

- `L` opens the login form.
- `R` opens registration when the sysop allows new accounts.
- `F` starts password recovery.
- `G` enters guest mode when the sysop allows guests.

There is also an operator-assisted reset path for people who already have a raw
reset token from the sysop: press `T` from the login menu.

In the login form, type your handle, press `Enter` or `Tab` to move to the
password field, then press `Enter` again to submit. `Esc` returns to the login
menu. If your account still needs email verification, Foglet sends a code and
moves you to the verification screen. If email is disabled or delivery fails,
the screen says so and tells you to contact the sysop.

Accounts that are pending approval, rejected, or suspended cannot enter the BBS.
Those states are enforced after authentication; hiding a menu item is not the
security boundary.

## Register an account

Registration mode is set by the sysop:

- Open registration asks for handle, email, password, and password confirmation.
- Invite-only registration asks for an invite code first.
- Disabled registration removes the registration entry from the login menu.

Use `Tab` and `Shift+Tab` to move between fields. Press `Enter` to advance or
submit. If your SSH client offered a public key that is not already attached to
an account, the registration form includes an opt-in field for saving it.

After registration, your account may be active immediately or may wait for sysop
approval, depending on the site settings.

## Guest mode

If guest mode is enabled, `G` enters the BBS without an account. Guests can read
what the sysop exposes to guests, but they cannot post, subscribe to boards, or
use account-only actions. When a guest tries an account-only action, Foglet
opens a denial message instead of pretending the action worked.

## Move around the TUI

Foglet shows the available keys in the command bar at the bottom of each screen.
The common pattern is:

- `Up` / `Down` move selection. Many lists also accept `j` / `k`.
- `Enter` opens the selected item or submits the active form.
- `Tab` moves focus or switches edit/preview mode, depending on the screen.
- `Esc` cancels the current form or modal.
- `Q` backs out of board, thread, and reader screens.
- `Ctrl+S` submits composers.
- `Ctrl+C` is a fallback cancel on compose screens and exits from the login
  surface.

The command bar is the authority for the current screen. If this guide and the
screen disagree, trust the screen and tell the sysop the docs are stale.

## Terminal size

Foglet is built for an 80-column terminal and works better with a little more
height. If the interface looks clipped, enlarge the terminal and reconnect or
resize the SSH window. The TUI receives resize events and redraws its screens.

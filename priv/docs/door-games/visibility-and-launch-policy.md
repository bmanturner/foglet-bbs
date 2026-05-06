%{
  title: "Visibility and launch policy",
  weight: 60
}
---

Door visibility is a launch gate, not just a display hint. Foglet filters the selector with `Foglet.Doors.list_browsable/1` and checks `launchable?/2` again before side effects. Hidden UI is not authorization.

## Roles

- Guests may browse member demo doors only when demo doors are enabled, but they cannot launch.
- Suspended, pending, rejected, and deleted users cannot launch doors.
- Users can launch `members` doors.
- Moderators can launch `members` and `mods_only` doors.
- Sysops can launch all door visibility levels.

## Auth scope

Current public operator manifests should use `site`. The manifest struct also accepts board scope shapes for future policy, but public docs should not promise board-scoped door catalogs until the product surface exposes them.

## Confirmation before handoff

The Door Games TUI opens a selector first. Pressing Enter on a launchable door opens a confirmation modal. Only confirmation emits the explicit launch effect that starts the runner.

The confirmation matters because full-screen doors take over the caller's terminal. Copy should warn clearly without pleading: Foglet will hand the terminal to the door and bring you back when it exits.

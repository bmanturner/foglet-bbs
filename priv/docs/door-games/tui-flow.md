%{
  title: "TUI flow",
  weight: 140
}
---

The Door Games terminal flow is a list, a confirmation, a handoff, and a return. It is designed so callers do not need to know manifest ids, runtime atoms, or executable paths.

## Flow

1. An authenticated caller opens Door Games from the main menu when browsable doors exist.
2. The selector lists visible doors and keeps selection in screen-local state.
3. Up/Down or `j`/`k` moves through the list.
4. Enter opens a launch confirmation for the selected door.
5. Confirming emits `Foglet.TUI.Effect.launch_door/2`.
6. Foglet gives the terminal to the door.
7. When the door exits, crashes, times out, or disconnects, Foglet cleans up and returns to the TUI with a status message.

## Empty and guest states

Guests may see browsable member demo doors when demos are enabled, but launching opens the guest denial modal. If no doors are browsable, the Door Games entry should not overpromise availability.

## Copy posture

Door copy should be curt and concrete. Say what will happen: Foglet will hand the terminal to the door and bring the caller back when it exits. Do not explain PTY, manifests, or adapters in caller-facing prompts.

## Wide terminals

The screen has room for detail at wider sizes. Keep the 80x24 path useful first; side panels are enhancement, not the contract.

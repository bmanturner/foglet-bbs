%{
  title: "Native Elixir doors",
  weight: 70
}
---

Native Elixir doors run inside the BEAM and implement Foglet's door callback boundary. They are best for first-party games or diagnostics that should stay inside Foglet's supervision and deployment model.

## When to use a native door

Use a native door when the game can be implemented as Elixir callbacks and does not need to exec an external program. Native doors avoid OS executable permissions, PTY helper availability, dropfiles, and process-user sandbox setup.

## Current limits

Native doors are configured from code/config, not through a public JSON module-name loader. Do not expose arbitrary module loading to operators without a separate design and security review.

## Demo example

The built-in `native-hello` manifest points at `Foglet.Doors.Demo.NativeHello`. It is available only when `FOGLET_ENABLE_DEMO_DOORS` is truthy. Use it to verify the launch/return path without spawning an OS process.

## Runtime behavior

The runner owns native callback execution, input, resize forwarding, timeout, crash handling, disconnect cleanup, and the exit notification back to the TUI. A native callback crash is treated as a door crash, not as a reason to restart the door behind the caller's back.

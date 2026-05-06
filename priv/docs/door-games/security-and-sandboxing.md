%{
  title: "Security and sandboxing",
  weight: 110
}
---

Treat every external or classic door as untrusted until you have reviewed the executable, paths, runtime user, persistence needs, and network behavior. Foglet narrows the handoff; it does not make arbitrary programs safe.

## What Foglet narrows

- Manifests must validate before listing or launch.
- External commands and working directories must be absolute paths.
- Door processes receive a clean environment, not the Foglet service environment.
- Sensitive environment names are rejected from manifest env and audit allowlists.
- Temporary context and dropfile files are runner-owned and cleaned up.
- Timeout, idle-timeout, disconnect, crash, and process cleanup are owned by the runner.

## Restricted-user sandbox

The sandbox mode `restricted_user_process_group` asks the helper to run the child as a configured OS user/group and clean up the child process group. It fails closed when the helper is missing or cannot switch user.

This is useful defense-in-depth, not full containment. It does not provide filesystem mount isolation, network policy, seccomp, namespaces, containers, microVMs, or resource quotas.

## Container/Fly caveat

The current Docker/Fly path runs the release image as `nobody`. That container baseline cannot switch to a second restricted door user without an approved runtime/deployment change. Do not promise arbitrary third-party code support on that path.

## Operator checklist

- Put door executables outside writable upload areas.
- Use a dedicated OS user for sandboxed doors where your host permits it.
- Give the door only the working directory it needs.
- Keep secrets out of manifests and wrapper scripts.
- Test timeout, crash, and disconnect cleanup before advertising a door.

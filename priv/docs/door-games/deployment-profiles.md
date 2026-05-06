%{
  title: "Deployment profiles",
  weight: 120
}
---

Door Games depend on host capabilities. Choose a deployment profile before enabling external or classic doors.

## Local development

Good for native demos, external echo demos, manifest validation, and first-pass classic dropfile checks. Enable demo doors only while testing:

```sh
FOGLET_ENABLE_DEMO_DOORS=true mix phx.server
```

## VPS or bare host

This is the strongest current profile for external/classic doors. You can install Python 3, keep the PTY helper available, create a restricted OS user, set file permissions, and persist a manifest/executable directory.

Recommended settings:

- `FOGLET_DOOR_MANIFEST_DIR=/srv/foglet/doors/manifests`
- executable files under `/srv/foglet/doors` or another operator-owned path
- restricted user/group for untrusted external programs
- service logs retained for manifest rejection and runtime failures

## Docker and Fly

Use Docker/Fly for native demos and carefully reviewed external commands only. The current image user model limits restricted-user sandboxing because the release runs as `nobody` and cannot switch to a second door user by default.

If you need broad third-party door hosting, use a host profile that can enforce the sandbox you intend, or treat the work as a deployment architecture change requiring CTO approval.

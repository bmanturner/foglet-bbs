%{
  title: "QA and release checks",
  weight: 160
}
---

Use this checklist before advertising Door Games on an instance or approving a change that affects doors. It is public operator guidance, not an internal release script.

## Static checks

- Manifests validate and invalid files are logged without exposing secrets.
- User-facing copy does not mention internal issue trackers, development refs, fixed test credentials, or planning artifacts.
- Public docs describe implemented behavior only.
- External/classic examples use absolute paths and no secret env names.

## Runtime checks

Verify at least one path for each runtime you intend to enable:

- Native door launches and returns.
- External PTY door launches and returns.
- Classic dropfile door receives the expected fixed-name files.
- Resize reaches the door or degrades acceptably for the chosen backend.
- Timeout cleans up the process and returns to Foglet.
- Crash or non-zero exit returns a clear status.
- Disconnect cleanup does not leave the child running.

## Terminal checks

- Test 80x24.
- Test one cramped size.
- Test one wide size if you rely on the detail panel.
- Confirm the terminal is usable after return.

## Release bar

Do not enable arbitrary third-party external/classic doors until the deployment profile matches the risk: helper present, restricted user available where needed, file permissions reviewed, secrets out of reach, and rollback path understood.

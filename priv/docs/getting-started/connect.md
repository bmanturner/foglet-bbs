%{
  title: "Connecting over SSH",
  description: "How to reach the BBS from your terminal.",
  weight: 2
}
---
# Connecting over SSH

The BBS is an SSH-first system. The `/docs` surface you are reading right now
is documentation about that system — not the system itself.

## Public pre-alpha

```
ssh bbs.foglet.io
```

You will be prompted for a handle and a password, or — once enabled — your
SSH key will be matched against your registered key fingerprints.

## What you should see

A terminal UI loads with a list of categories and boards. Use the arrow keys
to navigate, `Enter` to drill in, and `?` for context-sensitive help inside
any screen.

> If your terminal renders garbled characters, set `LANG=en_US.UTF-8` and try
> again. The TUI assumes UTF-8 and a 256-color terminal.

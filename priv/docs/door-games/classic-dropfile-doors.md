%{
  title: "Classic dropfile doors",
  weight: 90
}
---

Classic dropfile doors are external programs that expect old BBS metadata files before launch. Foglet can generate a fixed set of classic files from safe session metadata, write them into the runner-owned launch directory, and remove them during cleanup.

## Supported formats

- `chain_txt` writes `CHAIN.TXT`.
- `door_sys` writes `DOOR.SYS`.
- `door32_sys` writes `DOOR32.SYS`.
- `dorinfo_def` writes `DORINFO.DEF`.

Rendered files use CRLF line endings. File layouts are owned by Foglet's renderer modules. Manifests declare formats; they cannot choose filenames or arbitrary paths.

## Manifest shape

Use `runtime: "classic_dropfile"`, set absolute `command` and `working_dir`, then declare either:

```json
"dropfile_formats": ["door_sys", "dorinfo_def"]
```

or detailed entries:

```json
"dropfiles": [
  {"format": "door_sys", "encoding": "cp437", "expose_path": "env"}
]
```

When `expose_path` is `env`, Foglet sets format-specific variables such as `FOGLET_DROPFILE_DOOR_SYS` plus `FOGLET_DROPFILE_DIR`.

## Compatibility warning

Classic compatibility is per-door work. Some old games assume DOS paths, node files, fossil drivers, local screen modes, or writable install directories. Foglet provides dropfiles and a terminal bridge; it does not emulate a 1990s host.

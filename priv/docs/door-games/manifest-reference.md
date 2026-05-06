%{
  title: "Manifest reference",
  weight: 50
}
---

A door manifest is a JSON object validated into `Foglet.Doors.Manifest`. Foglet accepts string keys and normalizes known enum strings. Unknown keys are ignored by the current manifest struct unless a nested dropfile declaration rejects them.

## Required fields

- `id`: stable internal id.
- `slug`: stable name used for lookup.
- `display_name`: name shown to callers.
- `description`: one-sentence selector description.
- `runtime`: `native_elixir`, `external_pty`, or `classic_dropfile`.
- `timeout_ms`: positive integer absolute lifetime cap.
- `visibility`: `members`, `mods_only`, or `sysop_only`.
- `auth_scope`: `site` or a future board scope. Public JSON should use `site` unless code has supplied a board tuple.

## Runtime-specific fields

External and classic doors require:

- `command`: absolute executable path.
- `working_dir`: absolute working directory.

External and classic doors may also set:

- `args`: list of string arguments.
- `env`: explicit string environment values. Sensitive names are rejected.
- `env_allowlist`: uppercase env names safe to show unredacted in audit metadata.
- `pty` or `pty?`: boolean; defaults to `true`.
- `idle_timeout_ms`: optional positive integer inactivity cap.
- `output_encoding`: `utf8` or `cp437`; defaults to `utf8`.
- `sandbox`: sandbox settings.

Native Elixir doors use `module` in code/config, not in public JSON operator examples.

## Dropfile fields

Classic doors can declare either `dropfile_formats` or detailed `dropfiles`. Supported formats are:

- `chain_txt` -> `CHAIN.TXT`
- `door_sys` -> `DOOR.SYS`
- `door32_sys` -> `DOOR32.SYS`
- `dorinfo_def` -> `DORINFO.DEF`

A detailed dropfile item supports:

- `format`: one supported format.
- `identity`: currently `handle`.
- `transport`: currently `filesystem`.
- `encoding`: `cp437` or `utf8`.
- `cwd`: `door_working_dir` or `session_working_dir`.
- `expose_path`: `env` or `none`.

Manifests cannot set arbitrary dropfile filenames or paths.

## Sensitive environment names

Foglet rejects known secret-bearing names in `env` and `env_allowlist`, including database URLs, secret key bases, API keys, tokens, and package-manager or repository credentials. Keep secrets outside door manifests.

# Phase 12: Account SSH Key Management - Research

**Researched:** 2026-04-24
**Domain:** SSH public-key account lifecycle in Elixir/OTP, Ecto/Postgres, and Raxol TUI
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Domain Key Lifecycle
- **D-01:** SSH key add, list, and revoke behavior belongs in `Foglet.Accounts`; callers should not bypass the context or call `Repo` directly from TUI code.
- **D-02:** Ownership-safe key operations should take the current `%Foglet.Accounts.User{}` actor and a key identifier or submitted attrs, then enforce user ownership inside Accounts.
- **D-03:** Revocation should hard-delete the owned `ssh_keys` row. The existing schema has no `revoked_at`/status field, and account deletion already hard-deletes SSH keys. Planners should not add a soft-revocation migration unless new evidence makes hard deletion unsafe.

### Authentication And Last-Used Recording
- **D-04:** Successful public-key authentication should update `last_used_at` inside an Accounts authentication lookup path that finds the matching key and non-deleted user together, updates only that key, and returns the user.
- **D-05:** `Foglet.SSH.CLIHandler` should remain orchestration code: pop the stashed public key, encode it, call Accounts, and start the session. It should not own SSH key persistence rules.
- **D-06:** Failed, invalid, unregistered, revoked, deleted-user, password, and guest-login paths must not update SSH key usage metadata.

### Account TUI Integration
- **D-07:** Add `SSH KEYS` as another Account tab using the existing `PROFILE` / `PREFS` / conditional `INVITES` tab pattern.
- **D-08:** Keep Account key UI state screen-local and pure over already-loaded state. Persistence and refresh actions should route through Accounts-facing actions or commands, not direct `Repo` access.
- **D-09:** Use sibling Account modules for key form/actions behavior, mirroring the existing `ProfileForm`, `PrefsForm`, and shared invites action/surface organization rather than bolting all logic into `Account.render/1`.
- **D-10:** Key list and revoke selection should use existing terminal-native widgets and themed render patterns, especially the tab, list/selection, table, modal, and modal-form primitives where they fit.

### Test Shape
- **D-11:** Extend focused Accounts SSH key tests for validation, duplicate handling, ownership-safe revoke, lookup, and last-used behavior.
- **D-12:** Extend SSH tests around `CLIHandler`/public-key auth for registered, unregistered, revoked, deleted-user, and last-used metadata behavior.
- **D-13:** Extend Account screen tests for the `SSH KEYS` tab, zero-key empty state, key list rendering, add flow errors, revoke flow, refresh behavior, and command routing.
- **D-14:** Keep tests deterministic: use direct context calls, supervised processes, monitors, or state inspection instead of `Process.sleep/1`.

### the agent's Discretion
- Exact key list layout, timestamp formatting details within existing user preference conventions, empty-state wording, modal copy, and whether the add flow uses a full modal form or a screen-local form are left to planner discretion, provided the locked acceptance criteria remain satisfied.
- Exact public function names may be chosen by the planner, but the context boundary and ownership shape above are locked.

### Folded Todos
None.

### Claude's Discretion
- Exact key list layout, timestamp formatting details within existing user preference conventions, empty-state wording, modal copy, and whether the add flow uses a full modal form or a screen-local form are left to planner discretion, provided the locked acceptance criteria remain satisfied.
- Exact public function names may be chosen by the planner, but the context boundary and ownership shape above are locked.

### Deferred Ideas (OUT OF SCOPE)
None -- analysis stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| KEYS-01 | User can open an Account `SSH KEYS` tab from the terminal UI. | Extend `Account.State.tab_labels/1`, `Tabs`, and `Account.render_tab_body/3` using existing Account tab delegation. [VERIFIED: .planning/REQUIREMENTS.md; lib/foglet_bbs/tui/screens/account.ex; lib/foglet_bbs/tui/screens/account/state.ex] |
| KEYS-02 | User can add a valid OpenSSH public key with a label from Account. | Reuse `Accounts.register_ssh_key/2` and `SSHKey.changeset/2`; route TUI submission through an Account sibling actions module. [VERIFIED: lib/foglet_bbs/accounts.ex; lib/foglet_bbs/accounts/ssh_key.ex] |
| KEYS-03 | User can list their SSH keys with label, fingerprint, created time, and last-used time when available. | Reuse `Accounts.list_ssh_keys/1`; render rows with themed list/table primitives and UTC timestamp formatting. [VERIFIED: lib/foglet_bbs/accounts.ex; lib/foglet_bbs/tui/widgets/README.md] |
| KEYS-04 | User can revoke one of their own SSH keys from Account. | Add an actor-owned `Foglet.Accounts` revoke API that deletes by both `id` and `user_id`, then refreshes TUI state. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md; priv/repo/migrations/20260418000003_create_ssh_keys.exs] |
| KEYS-05 | User can authenticate with a registered SSH public key, and successful public-key authentication records last-used metadata. | Add an Accounts lookup that computes fingerprint, finds key plus non-deleted user, updates matched key `last_used_at`, and returns user; call it from `CLIHandler.resolve_pubkey_user/1`. [VERIFIED: lib/foglet_bbs/accounts.ex; lib/foglet_bbs/ssh/cli_handler.ex] |
</phase_requirements>

## Summary

Phase 12 should be implemented by extending the existing `ssh_keys` data model, `Foglet.Accounts` context, `Foglet.SSH.CLIHandler` pubkey handoff, and Account TUI tab pattern. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md; lib/foglet_bbs/accounts.ex; lib/foglet_bbs/ssh/cli_handler.ex; lib/foglet_bbs/tui/screens/account.ex] The project already stores OpenSSH public keys, computes SHA256 fingerprints server-side through OTP SSH/public-key APIs, and lists keys by owner. [VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex; lib/foglet_bbs/accounts.ex; docs/DATA_MODEL.md] The missing pieces are ownership-safe revoke, last-used recording on successful public-key auth, and a terminal-native Account `SSH KEYS` surface. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md]

The established architecture pattern is context-owned persistence with screen-local TUI state and SSH orchestration that delegates identity rules to Accounts. [VERIFIED: CLAUDE.md; .planning/codebase/ARCHITECTURE.md] Do not add a browser UI, a new key parsing dependency, a `revoked_at` migration, or direct `Repo` calls from TUI code. [VERIFIED: CLAUDE.md; .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**Primary recommendation:** Add `Accounts.revoke_ssh_key/2` and `Accounts.authenticate_by_public_key/1` or equivalent, keep `CLIHandler` as a thin caller, and implement Account `SSH KEYS` via sibling `SSHKeysState`/`SSHKeysActions`/`SSHKeysSurface` modules using existing Tabs, SelectionList/Table, and Modal.Form widgets. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_actions.ex; lib/foglet_bbs/tui/screens/shared/invites_surface.ex; lib/foglet_bbs/tui/widgets/README.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Key validation and fingerprinting | API / Backend (`Foglet.Accounts`) | Database / Storage | Validation and SHA256 fingerprint computation already live in `SSHKey.changeset/2`; DB unique indexes enforce duplicate safety. [VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex; priv/repo/migrations/20260418000003_create_ssh_keys.exs] |
| Key list/add/revoke persistence | API / Backend (`Foglet.Accounts`) | Database / Storage | Context modules own transactions, authorization/ownership, and persistence; TUI must not bypass them. [VERIFIED: CLAUDE.md] |
| Registered-key login resolution | API / Backend (`Foglet.Accounts`) | SSH Interface | `CLIHandler` obtains and encodes the stashed key, but Accounts owns registered-key lookup and last-used metadata. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md; lib/foglet_bbs/ssh/cli_handler.ex] |
| Pubkey correlation during SSH handshake | SSH Interface | ETS ephemeral state | `KeyCB.is_auth_key/3` stashes the public key and `CLIHandler` pops it on channel-up; ETS is ephemeral and reconstructable. [VERIFIED: lib/foglet_bbs/ssh/key_cb.ex; lib/foglet_bbs/ssh/pubkey_stash.ex; .planning/codebase/ARCHITECTURE.md] |
| Account `SSH KEYS` UI | TUI Layer | API / Backend | Account screen owns tab rendering and key handling; mutations route to Accounts actions, not Repo. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex] |

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first; Phoenix is infrastructure and must not gain end-user browser workflows for this phase. [VERIFIED: CLAUDE.md]
- Use `rtk` as the shell command prefix for repo commands. [VERIFIED: CLAUDE.md]
- `Foglet.Accounts` owns users, auth, roles, invites, tokens, SSH keys, and deletion. [VERIFIED: CLAUDE.md]
- Domain workflows belong in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. [VERIFIED: CLAUDE.md]
- Postgres is durable authority; ETS and processes are ephemeral. [VERIFIED: CLAUDE.md]
- Context modules own transactions, authorization checks, preload choices, PubSub side effects, and cross-schema invariants. [VERIFIED: CLAUDE.md]
- Programmatically set foreign keys before changeset construction; do not add `user_id` to `cast/3` for caller convenience. [VERIFIED: CLAUDE.md]
- `Foglet.SSH.CLIHandler` owns SSH channel lifecycle; UI behavior belongs in `Foglet.TUI.App` and screens. [VERIFIED: CLAUDE.md]
- `Foglet.TUI.App` owns global screen routing; screens own screen-local rendering and key handling. [VERIFIED: CLAUDE.md]
- Widgets route colors through `Foglet.TUI.Theme`, receive theme explicitly, and keep render functions pure over loaded state. [VERIFIED: CLAUDE.md; lib/foglet_bbs/tui/widgets/README.md]
- Use `start_supervised!/1`; avoid `Process.sleep/1` and `Process.alive?/1` in tests. [VERIFIED: CLAUDE.md]
- Run `mix precommit` when implementation is complete. [VERIFIED: CLAUDE.md]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Erlang/OTP `:ssh` / `:ssh_file` / `:public_key` | OTP 28 locally; docs checked against ssh v5.5.1 | Parse/encode SSH public keys and compute host-key-style SHA256 fingerprints. | Built into OTP and already used by Foglet; `ssh_file.decode/2` decodes OpenSSH/RFC4716 public keys and `ssh_server_key_api` defines `is_auth_key/3`. [VERIFIED: local `elixir --version`; CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html; CITED: https://www.erlang.org/doc/apps/ssh/ssh_server_key_api.html; VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex] |
| Ecto / Ecto SQL | Ecto 3.13.5, Ecto SQL 3.13.5 | Changesets, constraints, Repo queries, migrations. | Existing app stack; `unique_constraint/3` converts DB uniqueness violations into changeset errors, and `update_all/3` can atomically update matched rows but does not auto-update timestamps. [VERIFIED: mix.lock; CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html; CITED: https://hexdocs.pm/ecto/Ecto.Repo.html] |
| Postgrex / PostgreSQL | Postgrex 0.22.0; local psql 14.20 | Durable `ssh_keys` storage and unique indexes. | Existing repo adapter; current migration uses unique fingerprint and `(user_id,label)` indexes. [VERIFIED: mix.lock; VERIFIED: priv/repo/migrations/20260418000003_create_ssh_keys.exs; VERIFIED: local `psql --version`] |
| Raxol / Foglet widgets | Raxol 2.4.0 in lock; vendored path dependency in `mix.exs` | Terminal UI lifecycle, tabs, lists/tables, modal forms. | Existing Account screen and widget library use Raxol components with Foglet theme wrappers. [VERIFIED: mix.exs; mix.lock; lib/foglet_bbs/tui/widgets/README.md; CITED: https://hex.pm/packages/raxol] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Bodyguard | 2.4.3 | Authorization policy framework. | Not required for self-owned key operations unless project chooses explicit policy action; ownership must still be enforced inside Accounts. [VERIFIED: mix.lock; VERIFIED: CLAUDE.md; CITED: https://hex.pm/packages/bodyguard] |
| Timex | 3.7.13 | Existing time formatting dependency. | Prefer existing user preference conventions if timestamp formatting already uses Timex elsewhere; plain `Calendar.strftime/2` is already used in TUI shared surfaces. [VERIFIED: mix.lock; lib/foglet_bbs/tui/screens/shared/invites_surface.ex] |
| ExUnit + DataCase | Built into Elixir 1.19.5; project DataCase | Domain, SSH, and TUI tests. | Existing test infrastructure mirrors source paths and provides DB sandbox helpers. [VERIFIED: local `mix --version`; .planning/codebase/TESTING.md; test/support/data_case.ex] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| OTP `:ssh_file.decode/2` | Regex or manual base64 parsing | Do not hand-roll; OpenSSH authorized-key lines allow key types, base64 payloads, comments, and optional options. OTP already supports OpenSSH/RFC4716 decoding. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html; CITED: https://manpages.debian.org/experimental/openssh-server/authorized_keys.5.en.html] |
| Hard-delete revoke | Add `revoked_at` and filter everywhere | Locked out by D-03 unless new evidence appears; current schema and account deletion already hard-delete keys. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md; priv/repo/migrations/20260418000003_create_ssh_keys.exs] |
| Account sibling modules | Put all logic in `Account.render/1` | Sibling modules match existing `ProfileForm`, `PrefsForm`, and shared invites actions/surface pattern; large render modules are harder to test. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex] |

**Installation:**

```bash
# No new dependencies required.
rtk mix deps.get
```

**Version verification:** Package versions were verified from `mix.lock`, local runtime commands, and Hex package pages. [VERIFIED: mix.lock; local `elixir --version`; local `mix --version`; CITED: https://hex.pm/packages/ecto_sql; CITED: https://hex.pm/packages/postgrex; CITED: https://hex.pm/packages/raxol]

## Architecture Patterns

### System Architecture Diagram

```text
Account SSH KEYS tab input
  -> Foglet.TUI.Screens.Account.handle_key/2
  -> SSHKeysActions module maps key/form events
  -> Foglet.Accounts.register_ssh_key/list_ssh_keys/revoke_ssh_key
  -> SSHKey.changeset validates OpenSSH key and computes fingerprint
  -> Postgres ssh_keys unique indexes enforce duplicates
  -> refreshed SSHKeysState renders list/errors through themed widgets

SSH client offers public key
  -> Foglet.SSH.KeyCB.is_auth_key/3
  -> Foglet.SSH.PubkeyStash.put(peer, public_key)
  -> CLIHandler channel_up pops and encodes public key
  -> Foglet.Accounts.authenticate_by_public_key/1
      -> decode/fingerprint key
      -> find matching ssh_keys row joined to non-deleted user
      -> update only matched key last_used_at
      -> return user
  -> CLIHandler starts authenticated session or guest session
```

### Recommended Project Structure

```text
lib/foglet_bbs/
├── accounts.ex                         # add revoke + metadata-recording auth lookup
├── accounts/ssh_key.ex                 # keep parse/fingerprint validation here
├── ssh/cli_handler.ex                  # call new Accounts auth path only
└── tui/screens/account/
    ├── state.ex                        # add SSH KEYS tab state fields
    ├── ssh_keys_actions.ex             # load/add/revoke/error mapping
    ├── ssh_keys_state.ex               # screen-local items/form/selection/errors
    └── ssh_keys_surface.ex             # pure themed render
```

Tests should extend `test/foglet_bbs/accounts/accounts_test.exs`, `test/foglet_bbs/accounts/ssh_key_test.exs`, `test/foglet_bbs/ssh/cli_handler_test.exs`, and `test/foglet_bbs/tui/screens/account_test.exs`. [VERIFIED: .planning/codebase/TESTING.md; existing test files]

### Pattern 1: Context-Owned Key Lifecycle

**What:** All add/list/revoke/authentication lookup functions live in `Foglet.Accounts`; TUI and SSH code call public context APIs. [VERIFIED: CLAUDE.md; .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**When to use:** Every operation that reads or mutates `ssh_keys`. [VERIFIED: CLAUDE.md]

**Example:**

```elixir
# Source: existing project pattern in lib/foglet_bbs/accounts.ex and Ecto constraints docs.
@spec revoke_ssh_key(User.t(), Ecto.UUID.t()) :: {:ok, SSHKey.t()} | {:error, :not_found}
def revoke_ssh_key(%User{} = actor, key_id) do
  case Repo.get_by(SSHKey, id: key_id, user_id: actor.id) do
    %SSHKey{} = key -> Repo.delete(key)
    nil -> {:error, :not_found}
  end
end
```

This shape enforces ownership in the query, not in the UI. [VERIFIED: CLAUDE.md]

### Pattern 2: Metadata-Recording Public-Key Authentication

**What:** Add a new Accounts function for successful auth that updates `last_used_at` only after a matching key and non-deleted user are found. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**When to use:** `CLIHandler.resolve_pubkey_user/1` should call this path; legacy read-only lookup can remain for tests or non-mutating callers if useful. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

**Example:**

```elixir
# Source: Ecto Repo.update_all docs and existing get_user_by_public_key/1 query.
def authenticate_by_public_key(public_key_text) when is_binary(public_key_text) do
  with {:ok, fp} <- SSHKey.compute_fingerprint(public_key_text),
       %SSHKey{} = key <- get_active_key_by_fingerprint(fp),
       %User{deleted_at: nil} = user <- Repo.get(User, key.user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    {1, _} = Repo.update_all(from(k in SSHKey, where: k.id == ^key.id), set: [last_used_at: now])
    {:ok, user}
  else
    _ -> {:error, :not_found}
  end
end
```

`Repo.update_all/3` does not update autogenerated `updated_at`, so set `updated_at` explicitly only if the product wants key-row modification time to move with last-use. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]

### Pattern 3: Account Sibling Actions/Surface

**What:** Mirror Invites with `SSHKeysState`, `SSHKeysActions`, and `SSHKeysSurface`; keep state local and rendering pure. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_state.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex; lib/foglet_bbs/tui/screens/shared/invites_surface.ex]

**When to use:** Add/list/revoke interactions in the Account `SSH KEYS` tab. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**Example:**

```elixir
# Source: InvitesActions pattern in lib/foglet_bbs/tui/screens/shared/invites_actions.ex.
def handle_key(key, %User{} = actor, %SSHKeysState{} = state) when key in ["r", "R"] do
  actor
  |> Accounts.list_ssh_keys()
  |> then(&{:ok, SSHKeysState.loaded(state, &1)})
end
```

### Anti-Patterns to Avoid

- **Direct Repo access from Account TUI:** violates project boundary and makes ownership checks UI-dependent. [VERIFIED: CLAUDE.md]
- **Soft revoke without schema/query coverage:** contradicts D-03 and creates a fail-open risk if lookup forgets to filter revoked rows. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]
- **Updating `last_used_at` before full auth success:** would record failed, invalid, revoked, deleted-user, password, or guest attempts, violating D-06. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]
- **Manual OpenSSH key parsing:** misses valid formats/options and duplicates OTP functionality. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html; CITED: https://manpages.debian.org/experimental/openssh-server/authorized_keys.5.en.html]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OpenSSH public-key parsing | Regex/base64 parser | `:ssh_file.decode(text, :public_key)` | Official OTP decoder handles OpenSSH/RFC4716 public key input. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] |
| SHA256 fingerprint format | Custom digest/base64 formatting | `:ssh.hostkey_fingerprint(:sha256, key)` | Existing code already produces `SHA256:` fingerprints through OTP. [VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex] |
| Duplicate detection | Pre-insert lookup only | DB unique indexes plus `unique_constraint/3` | Ecto docs warn pre-checks are race-prone; DB constraints are data-race safe. [CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html; VERIFIED: priv/repo/migrations/20260418000003_create_ssh_keys.exs] |
| Ownership enforcement | Hidden buttons or selected-row filtering | `where: key.id == ^id and key.user_id == ^actor.id` in Accounts | UI visibility is not authorization; context must enforce ownership. [VERIFIED: CLAUDE.md] |
| Key-management widgets | New terminal component set | Existing Tabs, SelectionList/Table, Modal.Form | Foglet already has themed wrappers and contracts. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] |

**Key insight:** The hard problems are boundary placement and fail-closed auth semantics, not parsing or UI primitives; the codebase already has standard solutions for parsing, persistence constraints, and terminal widgets. [VERIFIED: codebase files above]

## Common Pitfalls

### Pitfall 1: `last_used_at` Updates on Failed Attempts

**What goes wrong:** An invalid/unregistered/deleted-user key changes metadata. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**Why it happens:** The update is placed immediately after fingerprint computation instead of after matching a non-deleted user and key row. [ASSUMED]

**How to avoid:** Use a single Accounts auth path that returns `{:ok, user}` only after updating exactly one matched key; all `else` branches return `{:error, :not_found}` without writes. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]

**Warning signs:** Tests for invalid, unregistered, revoked, deleted-user, password, and guest paths are missing. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md]

### Pitfall 2: `update_all/3` Does Not Touch `updated_at`

**What goes wrong:** Tests or UI assume `updated_at` changes when `last_used_at` changes. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]

**Why it happens:** Ecto explicitly documents that `update_all` does not update autogenerated fields such as `updated_at`. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]

**How to avoid:** Assert `last_used_at`, not `updated_at`, or explicitly set `updated_at: now` if the product wants that semantics. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]

**Warning signs:** A test compares `updated_at` before/after key auth. [ASSUMED]

### Pitfall 3: Constraint Errors Surface on Unexpected Fields

**What goes wrong:** Duplicate `(user_id,label)` tests expect only `:label`, but Ecto may associate a compound constraint with the first configured field unless `:error_key`/explicit names are used. [CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html; VERIFIED: test/foglet_bbs/accounts/ssh_key_test.exs]

**Why it happens:** `unique_constraint/3` on compound fields defaults the error key to the first field in the list. [CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html]

**How to avoid:** Keep or adjust tests to match the actual changeset error mapping; TUI error mapping should normalize duplicate label/fingerprint messages into user-facing copy. [VERIFIED: test/foglet_bbs/accounts/ssh_key_test.exs]

**Warning signs:** Terminal UI displays `user_id has already been taken`. [ASSUMED]

### Pitfall 4: Account Tab Index Drift

**What goes wrong:** Adding `SSH KEYS` changes the index of conditional `INVITES`, breaking digit navigation tests. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex; test/foglet_bbs/tui/screens/account_test.exs]

**Why it happens:** Account tabs are positional and tests use digit navigation. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex; test/foglet_bbs/tui/screens/account_test.exs]

**How to avoid:** Update `State.tab_labels/1`, clamp active indexes, and adjust tests for `PROFILE`, `PREFS`, `SSH KEYS`, optional `INVITES` order. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex]

**Warning signs:** Existing `"3"` INVITES tests fail after inserting the new tab. [VERIFIED: test/foglet_bbs/tui/screens/account_test.exs]

### Pitfall 5: Key Comment Privacy in UI

**What goes wrong:** The UI displays raw `public_key` comments or full key material instead of label/fingerprint. [ASSUMED]

**Why it happens:** OpenSSH public keys can include a user-chosen comment field. [CITED: https://manpages.debian.org/experimental/openssh-server/authorized_keys.5.en.html]

**How to avoid:** List label, fingerprint, created time, and last-used only; avoid full public-key display unless explicitly requested later. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md]

**Warning signs:** Account key table includes a full `ssh-ed25519 AAAA... user@host` string. [ASSUMED]

## Code Examples

Verified patterns from official and project sources:

### Decode OpenSSH Key and Compute Fingerprint

```elixir
# Source: lib/foglet_bbs/accounts/ssh_key.ex; OTP ssh_file docs.
case :ssh_file.decode(String.trim(public_key_text), :public_key) do
  [{key, _comments} | _] ->
    {:ok, :ssh.hostkey_fingerprint(:sha256, key) |> to_string()}

  [] ->
    {:error, "invalid OpenSSH public key: empty"}

  {:error, reason} ->
    {:error, "invalid OpenSSH public key: #{inspect(reason)}"}
end
```

### Normalize Changeset Errors for Terminal Copy

```elixir
# Source: lib/foglet_bbs/tui/screens/shared/invites_actions.ex.
changeset
|> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
|> Enum.map_join("; ", fn {field, messages} ->
  "#{field} #{Enum.join(messages, ", ")}"
end)
```

### Render List Rows With Existing Selection Widget

```elixir
# Source: lib/foglet_bbs/tui/screens/shared/invites_surface.ex.
SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
  item
  |> row_label()
  |> ListRow.render(selected?, theme)
end)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `:public_key.ssh_decode/2` / `ssh_encode/2` | `:ssh_file.decode/2` / `encode/2` | OTP docs mark public_key SSH encode/decode as deprecated and point to `ssh_file`. [CITED: https://www.erlang.org/docs/24/man/public_key; CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] | Keep existing `:ssh_file` usage; do not switch to deprecated APIs. |
| Manual authorized_keys file checks | Custom `ssh_server_key_api` callback plus app-level DB lookup | Existing Foglet architecture already stashes callback key then resolves through Accounts. [VERIFIED: lib/foglet_bbs/ssh/key_cb.ex; .planning/codebase/ARCHITECTURE.md] | Preserve `CLIHandler` orchestration and Accounts boundary. |
| Browser account settings | SSH-first terminal Account screen | Project milestone explicitly excludes end-user browser workflows. [VERIFIED: CLAUDE.md; .planning/REQUIREMENTS.md] | Implement only TUI Account management. |

**Deprecated/outdated:**
- `:public_key.ssh_decode/2` / `ssh_encode/2`: documented as deprecated; use `ssh_file:decode/2` / `encode/2`. [CITED: https://www.erlang.org/docs/24/man/public_key]
- UI-only authorization checks: project rules require context mutation authorization/ownership checks. [VERIFIED: CLAUDE.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Invalid placement of last-used update is a likely implementation mistake. | Common Pitfalls | Planner may underemphasize negative-path tests. |
| A2 | Tests may accidentally assert `updated_at` changes. | Common Pitfalls | Test plan could encode wrong Ecto semantics. |
| A3 | Raw key comments/full key display may be a privacy concern. | Common Pitfalls | UI might expose more account metadata than acceptance criteria require. |

## Open Questions

1. **Should successful auth update `updated_at` as well as `last_used_at`?**
   - What we know: `last_used_at` is required; `update_all/3` will not auto-touch `updated_at`. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md; CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]
   - What's unclear: Product semantics for key row modification time. [ASSUMED]
   - Recommendation: Only assert and display `last_used_at`; do not rely on `updated_at`. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-SPEC.md]

2. **Should `get_user_by_public_key/1` remain read-only?**
   - What we know: Existing callers/tests use it as a lookup; D-04 needs a metadata-recording lookup for successful auth. [VERIFIED: lib/foglet_bbs/accounts.ex; .planning/phases/12-account-ssh-key-management/12-CONTEXT.md]
   - What's unclear: Whether to change existing function semantics or add a new `authenticate_by_public_key/1`. [ASSUMED]
   - Recommendation: Add a new metadata-recording function for `CLIHandler` and keep `get_user_by_public_key/1` read-only for compatibility. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | Required repo command prefix | Yes | wraps Mix 1.19.5 / OTP 28 | Direct `mix` only for diagnostics, but planner should use `rtk`. [VERIFIED: local command] |
| Elixir | Compile/test | Yes | 1.19.5 with Erlang/OTP 28 | None needed. [VERIFIED: local command] |
| Mix | Dependencies/test/precommit | Yes | 1.19.5 | None needed. [VERIFIED: local command] |
| PostgreSQL client | DB-backed tests | Yes | psql 14.20 | Test aliases manage DB; no fallback required. [VERIFIED: local command; mix.exs] |
| `ssh-keygen` | Optional manual fixture/debug validation | Yes | macOS usage output available; no version flag result from `-V` without arg | OTP parsing tests are primary fallback. [VERIFIED: local command] |
| Node | GSD graph/status tooling | Yes | v24.11.1 | Graphify disabled; not required. [VERIFIED: local command] |

**Missing dependencies with no fallback:** None found. [VERIFIED: local commands]

**Missing dependencies with fallback:** Graphify is disabled; codebase grep and direct file reads were used instead. [VERIFIED: graphify status command]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Elixir 1.19.5; DataCase for DB tests. [VERIFIED: local command; .planning/codebase/TESTING.md] |
| Config file | `test/test_helper.exs`; DataCase in `test/support/data_case.ex`. [VERIFIED: .planning/codebase/TESTING.md] |
| Quick run command | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/ssh/cli_handler_test.exs test/foglet_bbs/tui/screens/account_test.exs` |
| Full suite command | `rtk mix test`; final gate `rtk mix precommit`. [VERIFIED: CLAUDE.md; mix.exs] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| KEYS-01 | Account exposes selectable `SSH KEYS` tab and empty state. | TUI unit | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | Yes |
| KEYS-02 | Add valid key; invalid/blank/duplicate inputs show errors. | Domain + TUI unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/tui/screens/account_test.exs` | Yes |
| KEYS-03 | List own keys with label, fingerprint, created, last-used/never-used. | Domain + TUI unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/account_test.exs` | Yes |
| KEYS-04 | Revoke owned key; reject other user's key; refresh list. | Domain + TUI unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/account_test.exs` | Yes |
| KEYS-05 | Registered-key auth succeeds and updates only matched key `last_used_at`; failed paths do not update. | Domain + SSH integration-ish unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` | Yes |

### Sampling Rate

- **Per task commit:** Run the narrow file(s) touched by the task. [VERIFIED: .planning/codebase/TESTING.md]
- **Per wave merge:** Run the quick command above. [VERIFIED: .planning/codebase/TESTING.md]
- **Phase gate:** `rtk mix precommit` green before `/gsd-verify-work`. [VERIFIED: CLAUDE.md; mix.exs]

### Wave 0 Gaps

- [ ] Add tests for `Accounts.revoke_ssh_key/2` ownership and hard-delete behavior. [VERIFIED: existing tests do not cover revoke]
- [ ] Add tests for metadata-recording public-key auth and no-update negative paths. [VERIFIED: existing tests cover read-only lookup, not last-used]
- [ ] Add Account screen tests for `SSH KEYS` tab, add/revoke flows, validation copy, and refreshed list. [VERIFIED: existing Account tests cover PROFILE/PREFS/INVITES but not SSH KEYS]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | Yes | Registered SSH public-key auth through OTP SSH callback handoff and Accounts DB lookup. [VERIFIED: lib/foglet_bbs/ssh/key_cb.ex; lib/foglet_bbs/accounts.ex] |
| V3 Session Management | Yes | Existing `Foglet.Sessions.Supervisor` starts authenticated sessions after Accounts returns a user. [VERIFIED: .planning/codebase/ARCHITECTURE.md; lib/foglet_bbs/ssh/cli_handler.ex] |
| V4 Access Control | Yes | Context-owned ownership checks for revoke/list/add; UI visibility is not authorization. [VERIFIED: CLAUDE.md] |
| V5 Input Validation | Yes | `SSHKey.changeset/2` validates required label/public_key and parses keys through OTP. [VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex] |
| V6 Cryptography | Yes | OTP `:ssh_file` and `:ssh.hostkey_fingerprint/2`; no custom crypto. [VERIFIED: lib/foglet_bbs/accounts/ssh_key.ex; CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] |

### Known Threat Patterns for SSH Key Management

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Key registration parser bypass | Tampering | Use OTP `:ssh_file.decode/2`, not regex parsing. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] |
| Duplicate key takeover/confusion | Spoofing | Global unique `fingerprint` index plus Ecto `unique_constraint/3`. [VERIFIED: priv/repo/migrations/20260418000003_create_ssh_keys.exs; CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html] |
| Revoke another user's key | Elevation of privilege | Delete by `id` and `user_id` inside Accounts; never trust selected UI rows alone. [VERIFIED: CLAUDE.md] |
| Revoked/deleted-user key still logs in | Spoofing | Hard-delete revoked keys; lookup joins non-deleted user and returns `:not_found` otherwise. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md; lib/foglet_bbs/accounts.ex] |
| Metadata poisoning | Repudiation | Update `last_used_at` only after successful registered-key authentication. [VERIFIED: .planning/phases/12-account-ssh-key-management/12-CONTEXT.md] |

## Sources

### Primary (HIGH confidence)

- `CLAUDE.md` / `AGENTS.md` - project boundaries, testing, TUI, context, and persistence directives. [VERIFIED]
- `.planning/phases/12-account-ssh-key-management/12-CONTEXT.md` - locked implementation decisions. [VERIFIED]
- `.planning/phases/12-account-ssh-key-management/12-SPEC.md` - phase requirements and acceptance criteria. [VERIFIED]
- `docs/DATA_MODEL.md` - `ssh_keys` schema and timestamp/index conventions. [VERIFIED]
- `lib/foglet_bbs/accounts.ex`, `accounts/ssh_key.ex`, `ssh/cli_handler.ex`, `ssh/key_cb.ex`, `ssh/pubkey_stash.ex` - current implementation. [VERIFIED]
- `lib/foglet_bbs/tui/screens/account*.ex` and shared invites modules - Account tab/action/surface patterns. [VERIFIED]
- `lib/foglet_bbs/tui/widgets/README.md` and Raxol widget gallery - widget contracts and available primitives. [VERIFIED]
- Erlang OTP SSH docs: `ssh_file`, `ssh_server_key_api`, and public_key deprecation note. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html; https://www.erlang.org/doc/apps/ssh/ssh_server_key_api.html; https://www.erlang.org/docs/24/man/public_key]
- Ecto docs: `Ecto.Changeset.unique_constraint/3`, `Ecto.Repo.update_all/3`. [CITED: https://hexdocs.pm/ecto/Ecto.Changeset.html; https://hexdocs.pm/ecto/Ecto.Repo.html]

### Secondary (MEDIUM confidence)

- Hex package pages for current ecosystem package versions. [CITED: https://hex.pm/packages/ecto_sql; https://hex.pm/packages/postgrex; https://hex.pm/packages/raxol; https://hex.pm/packages/bodyguard]
- Debian/OpenSSH authorized_keys manpage for public key line format. [CITED: https://manpages.debian.org/experimental/openssh-server/authorized_keys.5.en.html]

### Tertiary (LOW confidence)

- None used for implementation-critical claims.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - existing project stack plus official OTP/Ecto docs and Hex package verification. [VERIFIED/CITED]
- Architecture: HIGH - locked phase decisions and codebase architecture agree. [VERIFIED]
- Pitfalls: MEDIUM - several are directly verified from docs/code; UI privacy and likely mistake patterns are marked assumed. [VERIFIED/CITED/ASSUMED]

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for project-local architecture; 2026-05-01 for package currency.

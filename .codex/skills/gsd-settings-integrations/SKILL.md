---
name: "gsd-settings-integrations"
description: "Configure third-party API keys, code-review CLI routing, and agent-skill injection"
metadata:
  short-description: "Configure third-party API keys, code-review CLI routing, and agent-skill injection"
---

<codex_skill_adapter>
## A. Skill Invocation
- This skill is invoked by mentioning `$gsd-settings-integrations`.
- Treat all user text after `$gsd-settings-integrations` as `{{GSD_ARGS}}`.
- If no arguments are present, treat `{{GSD_ARGS}}` as empty.

## B. AskUserQuestion → request_user_input Mapping
GSD workflows use `AskUserQuestion` (Claude Code syntax). Translate to Codex `request_user_input`:

Parameter mapping:
- `header` → `header`
- `question` → `question`
- Options formatted as `"Label" — description` → `{label: "Label", description: "description"}`
- Generate `id` from header: lowercase, replace spaces with underscores

Batched calls:
- `AskUserQuestion([q1, q2])` → single `request_user_input` with multiple entries in `questions[]`

Multi-select workaround:
- Codex has no `multiSelect`. Use sequential single-selects, or present a numbered freeform list asking the user to enter comma-separated numbers.

Execute mode fallback:
- When `request_user_input` is rejected (Execute mode), present a plain-text numbered list and pick a reasonable default.

## C. Task() → spawn_agent Mapping
GSD workflows use `Task(...)` (Claude Code syntax). Translate to Codex collaboration tools:

Direct mapping:
- `Task(subagent_type="X", prompt="Y")` → `spawn_agent(agent_type="X", message="Y")`
- `Task(model="...")` → omit. `spawn_agent` has no inline `model` parameter;
  GSD embeds the resolved per-agent model directly into each agent's `.toml`
  at install time so `model_overrides` from `.planning/config.json` and
  `~/.gsd/defaults.json` are honored automatically by Codex's agent router.
- `fork_context: false` by default — GSD agents load their own context via `<files_to_read>` blocks

Spawn restriction:
- Codex restricts `spawn_agent` to cases where the user has explicitly
  requested sub-agents. When automatic spawning is not permitted, do the
  work inline in the current agent rather than attempting to force a spawn.

Parallel fan-out:
- Spawn multiple agents → collect agent IDs → `wait(ids)` for all to complete

Result parsing:
- Look for structured markers in agent output: `CHECKPOINT`, `PLAN COMPLETE`, `SUMMARY`, etc.
- `close_agent(id)` after collecting results from each agent
</codex_skill_adapter>

<objective>
Interactive configuration of GSD's third-party integration surface:
- Search API keys: `brave_search`, `firecrawl`, `exa_search`, and
  the `search_gitignored` toggle
- Code-review CLI routing: `review.models.{claude,codex,gemini,opencode}`
- Agent-skill injection: `agent_skills.<agent-type>`

API keys are stored plaintext in `.planning/config.json` but are masked
(`****<last-4>`) in every piece of interactive output. The workflow never
echoes plaintext to stdout, stderr, or any log.

This command is deliberately distinct from `$gsd-settings` (workflow toggles)
and any `$gsd-settings-advanced` tuning surface. It handles *connectivity*,
not pipeline shape.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/settings-integrations.md
</execution_context>

<process>
**Follow the settings-integrations workflow** from
`@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/settings-integrations.md`.

The workflow handles:
1. Resolving `$GSD_CONFIG_PATH` (flat vs workstream)
2. Reading current integration values (masked for display)
3. Section 1 — Search Integrations: Brave / Firecrawl / Exa / search_gitignored
4. Section 2 — Review CLI Routing: review.models.{claude,codex,gemini,opencode}
5. Section 3 — Agent Skills Injection: agent_skills.<agent-type>
6. Writing values via `gsd-sdk query config-set` (which merges, preserving
   unrelated keys)
7. Masked confirmation display
</process>

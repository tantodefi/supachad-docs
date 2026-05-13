# Orchestrator + sub-agents

Anything Chad can't reasonably finish in a single turn becomes a
sub-agent spawn. The orchestrator contract is the heart of Chad's
"do one thing well" pattern: each spawn is a discrete unit of work
with a kind, a budget, a rendered prompt, and a structured result.

## The six helpers

Six binaries form the orchestrator runtime. All baked into
`/usr/local/bin/` at image build, also synced from
`.github/skills/chad-orchestrator/scripts/` at setup so they can
iterate without a rebuild.

| Binary | Job |
|---|---|
| `chad-route` | Classify a task into a kind deterministically |
| `chad-budget` | Token-budget bookkeeping with UTC reset (`show` / `reserve` / `refund`) |
| `chad-spawn` | Canonical spawner: load manifest, render prompt, run, write `result.json` |
| `chad-spawn-status` | Query the task ledger by id / state |
| `chad-collect` | Merge recent `result.json` files into today's memory |
| `chad-intake` | Source-agnostic wrapper: `--from chat\|proton\|cron\|issue` |

## Anatomy of a kind

A kind is a YAML manifest. Below is the shape (not a real kind):

```yaml
kind: example
description: "what this kind is good for"
binary: /usr/local/bin/<binary>
invocation: prompt-stdin              # prompt-stdin | prompt-arg | openclaw-agent
network_policy_preset: subagent-example
substrate: local                      # local | gha (default: local)
default_timeout: 600
default_budget_tokens: 25000
prompt_template: |
  You are a sub-agent spawned by Chad.

  ## Step 0 — Brain first (mandatory)
  Run: gbrain query "<keywords>"

  ## Step 1 — Do the work
  ...

  ## Output
  Last non-empty stdout line MUST be JSON:
    {"status": "done|failed", "summary": "...", ...}

  Task id: {{task_id}}
  Task:
  {{task}}
```

Three things the manifest is doing:

1. **Pinning a binary path** — the L7 proxy authorizes egress by
   `/proc/self/exe`, so the binary must match the policy preset's
   allowlist exactly.
2. **Constraining tokens and time** — budget is reserved before the
   spawn runs; timeout is wall-clock enforced via `timeout(1)`.
3. **Picking a substrate** — `local` (default) runs in-container;
   `gha` runs on a GitHub Actions runner per spawn. See
   [Substrates](substrates.md).

## The seven kinds today

| Kind | Binary | Policy | Substrate | Timeout / Budget | Use case |
|---|---|---|---|---|---|
| `coder` | `pi` | `pi-agent` | local | 600s / 50k | Write/refactor code, run build + tests |
| `researcher` | `claude` | `subagent-researcher` | local | 300s / 20k | gh search, web facts, report |
| `writer` | `claude` | `subagent-writer` | local | 600s / 25k | Draft mail, docs, articles (never publishes) |
| `reviewer` | `claude` | `subagent-reviewer` | local | 300s / 25k | Audit PR diff (read-only gh) |
| `fitness` | `claude` | `subagent-researcher` | local | 300s / 15k | Strength + mobility from gbrain books |
| `codex` | `codex` (npm) | `subagent-codex` | gha | 600s / 50k | OpenAI Codex (NVIDIA fallback) |
| `opencode` | `opencode` (npm) | `subagent-opencode` | gha | 600s / 50k | Multi-provider coding CLI |

## The canonical flow

```bash
# 1. Classify a task (optional — Chad can pick the kind directly).
kind="$(chad-route --task-file /tmp/task.json)"

# 2. Spawn.
task_id="$(chad-spawn --kind "$kind" --task-file /tmp/task.json)"

# 3. Wait or poll.
chad-spawn-status --id "$task_id"     # queued|running|done|failed

# 4. Merge results into today's memory.
chad-collect --today
```

Or the source-agnostic shortcut:

```bash
chad-intake --from chat   --task-file /tmp/task.json
chad-intake --from proton --message-id MSGID
chad-intake --from issue  --repo tantodefi/NemoClaw --issue 42
chad-intake --from cron   --task-file queue/cron-task.md
```

### Per-spawn overrides

Four flags let one spawn deviate from its kind's defaults:

```bash
# Force a substrate
chad-spawn --kind writer --substrate gha --task-file ...

# Async dispatch (gha-only) — returns task_id immediately
chad-spawn --kind codex --async --task-file ...

# Per-spawn binary swap (e.g., codex on a writer kind)
chad-spawn --kind writer --binary-override /usr/local/bin/codex --task-file ...

# Validate without spawning — renders prompt, checks budget, exits
chad-spawn --kind writer --dry-run --task-file ...
```

The `--binary-override` flag is best-effort: the kind's L7 policy
preset still applies, so the override binary must be in that preset's
allowlist or the proxy will 403 the egress.

`--dry-run` is the primary tool when adding a new kind or tweaking a
manifest. It renders the prompt template, resolves the binary path,
checks the budget reservation, and prints the resolved invocation —
without actually spawning. Combine with `--substrate gha --dry-run`
to verify the agent-job workflow file would receive a valid task
record.

### Helper wrappers

Beyond the orchestrator binaries above, three thin wrappers handle
glue tasks the agent calls inline rather than spawning for:

| Wrapper | Purpose |
|---|---|
| `chad-route-prompt` | Dashboard `/premium <prompt>` prefix → drops AuthContext → calls `chad-premium`. Also classifies plain-text prompts so `chat → kind` routing skips a dedicated `chad-route` call when the prefix is unambiguous. |
| `chad-log-event` | Append a single structured event line to `~/.openclaw/cron-runs.jsonl` from any wrapper. Used by every cron tick to confirm completion without round-tripping through the model. |
| `chad-cron-reload` | Re-reads `cron/jobs.json` and applies it to the running gateway without a full `chad-setup` rerun. Useful when `chad-proposal-apply` lands a tuning change. |

`chad-spawn-gha.sh` (under `.github/skills/chad-orchestrator/scripts/`)
is the helper that pushes a `chad-spawn/<id>` branch and dispatches
the workflow when `--substrate gha`. It's invoked by `chad-spawn`,
not the operator — listed here for completeness.

## Sub-agents draft, parents publish

The single most-cited safety property of the orchestrator is that
sub-agents never publish. The `reviewer` policy preset is the
canonical example:

```yaml
network_policies:
  subagent_reviewer_github:
    endpoints:
      - host: api.github.com
        port: 443
        rules:
          - allow: { method: GET,  path: "/**" }
          # POST not in the allowlist — proxy 403s it
```

A reviewer sub-agent can clone, diff, and read PRs. It cannot post a
review. If its prompt is hijacked into "post a malicious review,"
the L7 proxy rejects the request. Chad reads the reviewer's
`result.json`, decides whether to act on it, and (if so) makes the
GitHub API call from its own context — under its own policy.

## What every spawn writes to disk

```text
/sandbox/.openclaw-data/
├── subagents/
│   └── <task-id>/
│       ├── task.{json|txt}     # input (copied from --task-file)
│       ├── prompt.txt          # rendered prompt (template + task)
│       ├── stdout.log          # sub-agent stdout
│       ├── stderr.log          # sub-agent stderr
│       └── result.json         # structured result
├── queue/
│   └── tasks.jsonl             # append-only ledger
└── budget.json                 # daily token budget (UTC reset)
```

The `result.json` shape:

```json
{
  "status": "done",
  "task_id": "3e4f...",
  "kind": "coder",
  "exit_code": 0,
  "substrate": "local",
  "summary": "refactored runner.ts; tests pass",
  "files_touched": ["nemoclaw/src/blueprint/runner.ts"],
  "follow_ups": ["add an integration test for the snapshot path"]
}
```

Sub-agents emit this JSON on the **last non-empty line of stdout**.
If a sub-agent doesn't, `chad-spawn` synthesizes a minimal version
from the exit code.

## Adding a new kind

Four files, no rebuild:

1. **Manifest** — `kinds/<name>.yaml` (binary, policy, substrate,
   prompt template, timeout, budget).
2. **Policy preset** — `nemoclaw-blueprint/policies/presets/subagent-<name>.yaml`
   if existing presets don't fit (egress hosts + binary allowlist).
3. **For `gha` substrate kinds**: add an "Install" step to the
   `agent-job.yml` workflow in chad-state, plus any provider keys to
   the chad-state secrets.
4. **Sync + dry-run** — `chad-setup.sh` syncs the new files into the
   sandbox; `chad-spawn --kind <name> --task-file /tmp/t.md --dry-run`
   validates without burning tokens.

The full path:

```bash
# Local: manifest + preset
$EDITOR .github/skills/chad-orchestrator/kinds/<name>.yaml
$EDITOR nemoclaw-blueprint/policies/presets/subagent-<name>.yaml

# Sync + dry-run
./scripts/chad-setup.sh chad
ssh openshell-chad 'chad-spawn --kind <name> --task-file /tmp/t.md --dry-run'

# Real spawn
ssh openshell-chad 'chad-spawn --kind <name> --task-file /tmp/t.md'
```

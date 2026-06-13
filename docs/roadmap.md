# Roadmap

The orchestrator that landed on `chad-dev` was, by design, a
**minimum viable contract** — enough surface area to prove the
sandbox + sub-agent + autonomy story end-to-end, no more. Several
improvements were deliberately held for follow-up; some have shipped
since the initial cut. Status is current as of the
[Changelog](changelog.md) head.

## Shipped

| Item | Where | Notes |
|---|---|---|
| Nested-spawn isolation | gha substrate | Sub-agents can spawn onto a per-job GitHub Actions runner instead of sharing Chad's container. Phases A–C all shipped 2026-05-06. See [Substrates](substrates.md). |
| Async sub-agent spawn | `chad-spawn --async --substrate gha` | Returns task id immediately. `chad-spawn-poll` cron (every 5 min) reconciles `result.json` from the runner branch. Branch retention via `chad-spawn-gc` weekly cron. |
| Hermes-style memory curator | `chad-memory-curator` weekly | Inactivity-gated, snapshot-first, draft-only consolidation pass over the LTM. See [Memory](memory.md). |
| Self-modify safe-list (cron tunings) | `chad-proposal-apply` daily | Reads structured proposals from `chad-budget-audit`, applies narrow safe-list (`timeoutSeconds`, `maxOutputTokens` within ±2× current). Gated by `chad-action-gate chad_self_modify_cron`. |
| NVIDIA fallback for OpenAI-compat kinds | `codex` and `opencode` kinds | Falls through to `integrate.api.nvidia.com` when `OPENAI_API_KEY` is absent. |
| Premium escalation | `chad-premium` + AuthContext | Anthropic Claude routing for tasks where Nemotron's reasoning depth feels shallow. See [Premium escalation](premium.md). |
| Open WebUI front-end | `chad-shim.py` + docker-compose | Chad as an OpenAI-compat model. See [Front-ends](front-ends.md). |
| Nemotron 3 Ultra 550B + reasoning | hosted inference profiles | Newest NVIDIA open model as default; reasoning on by default after the tool-call harness bug was retested and found absent in Ultra. Self-hosted profiles stay on Super 120B. |
| Smithers evolutionary experiments (shadow) | `scripts/chad-smithers/` | Durable host-side runner: model router, evolutionary selection (start wide → score in parallel → keep what works), crash-resume, nightly launchd job posting the leaderboard to OpenWebUI. Shadow beside `chad-experiment-cron`. |
| Moshi notifications + phone approval | `moshi-hook` agent hooks + `chad-tmux` | Host `claude` runs notify the phone and route approval gates to it; `chad-tmux` gives phone-attachable host sessions. |

## Phase 2 — held for follow-up

These are tracked in `chad-readme.md` §10. Each is a deliberate
defer, not an oversight.

### k3s-pod substrate

A per-spawn pod in a local k3s cluster would give the isolation of
the GHA runner *and* the L7 policy enforcement of the local
substrate. Today you pick one or the other. The blocker is operating
a k3s control plane on the host machine — possible, just real
overhead for a single-operator setup.

**When it'll matter:** the moment a sub-agent kind genuinely needs
both isolation and L7 enforcement. The fitness kind doesn't
(read-only). The codex/opencode kinds don't (in-flight, sandboxed by
GHA). A coder kind that writes to multiple repos in one spawn
would.

### Cron DSL

`chad-intake --from cron` takes a task file today. A YAML DSL would
let Chad register new crons at runtime — *"every Tuesday 9 a.m.,
spawn a reviewer against my open PRs."*

**Why deferred:** the autonomy surface for a self-registering cron
is non-trivial. The current set is operator-curated; allowing Chad
to register his own crons means another `chad-action-gate`
action type and a careful safe-list.

### `openclaw-sandbox.yaml` split

The single 346-line policy file is at its complexity ceiling.
Splitting per-domain (inference / github / messaging / browsing)
would make policy review tractable and let presets compose more
cleanly.

**Why deferred:** the merge tool that compiles per-domain files
back into a single OPA policy doesn't exist yet. The cost is
higher than the benefit until the file gets larger.

### Multi-Chad scheduling

One k3s cluster, multiple Chads, a shared scheduler that routes by
kind + load. Needed the moment a second user shows up.

**Why deferred:** there is no second user yet. When there is, the
Open WebUI session split (one Chad per identity) is the first thing
that has to land.

### MCP hub

Expose the orchestrator helpers (`chad-spawn`, `chad-budget`,
`chad-collect`, …) as MCP tools so a non-Chad agent (Claude Code, a
local editor) can drive the same sub-agent contract without Chad
in the middle.

**Why deferred:** the orchestrator helpers' contract is
binary-stable today (stdout sentinels, JSON in `result.json`).
Wrapping them in MCP is straightforward; the open question is
whether non-Chad callers should be allowed to bypass the action
gate, and the answer is "no" but the implementation needs care.

### Diff-checked, compressed backups

`chad-backup-to-github` does per-file sha-diff today. A Phase-2
consolidation would do a single tree-sha diff per backup run —
roughly one API call instead of one per file. Saves ~400 calls per
day on the current backup set.

**Why deferred:** the per-file path is correct, just inefficient.
The cron schedule (every 6 h) absorbs the inefficiency for now.

### Webhook-based completion for async spawns

Today `chad-spawn-poll` polls every 5 minutes. A webhook receiver
in Chad's gateway would replace the poll with push semantics —
zero reconciliation lag, no work when nothing's in flight.

**Why deferred:** the gateway doesn't speak inbound webhooks yet.
Adding that surface is a non-trivial security review (incoming
HTTP from GitHub is its own threat model).

## Out of scope, on purpose

A few things that won't be roadmapped because the design says no:

- **Chad-as-a-product.** This is a single-operator agent built
  against a private state repo. "Reproducible by anyone" is in
  [Reproducing](reproducing.md), but a hosted multi-tenant version
  is not the design.
- **`github_pr_merge: auto`.** The autonomy roadmap says `block`
  is likely permanent. A merge is irreversible and synthesizes
  CI signal that humans should still gate on.
- **`chad_self_modify_identity: auto`.** Identity files
  (`SOUL.md`, `IDENTITY.md`, `USER.md`) are operator-owned. Chad
  can propose; only the operator applies.

## How to read this page

The shipped list is what `chad-dev` does today. The Phase 2 list is
what *might* land next, in some order, when there's reason. The
"out of scope" list is what won't, and the reasoning is the
interesting part — every "no" is a place where the design
intentionally chose limits over capability.

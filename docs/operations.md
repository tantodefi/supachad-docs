# Operations: the cron schedule

Chad's contract with the day is the cron list. Twelve standing jobs (plus three host-side launchd watchdogs that supervise the pod from outside),
all registered by `chad-setup.sh`, all budget-guarded, all
deliberately conservative — every fire tokenizes a prompt and spawns
a model call, so the rule is: fewer, cheaper runs.

## The twelve jobs

| Job | Cadence | Budget guard | What it does |
|---|---|---|---|
| `email-check` | `0 2,6-23 * * *` (19×/day) | skip if remaining < 30k | Reads mail via `proton-tool`, follows `EMAIL-POLICY.md`, logs to today's memory. Drafts replies through `chad-drafter`; routes `auto` ones through `chad-autosend-replies`, parks `draft` for review. |
| `workspace-backup` | every 6h | n/a | `chad-backup-to-github` with sha-diff check. Ships `workspace/` to chad-state. |
| `issue-triage` | daily 10:00 UTC | skip if remaining < 3×N×70k | `chad-issue-triage` — scores open issues, routes top 2 through a researcher kind. |
| `gbrain-dream` | nightly 03:30 UTC | skip if remaining < 50k | `chad-gbrain-dream` — embed-stale + extract-graph + extract-timeline. Detached. Writes 24h delta digest. |
| `self-improve` | weekly Sun 03:00 UTC | skip if remaining < 2×budget | `chad-self-improve` — proposes 1–3 durable improvements based on last week's signal. **Draft-only.** |
| `chad-budget-audit` | weekly Mon 04:00 UTC | n/a | Compares last-50-runs telemetry vs `task-profiles.json`. Rolls up premium spend. Appends recommendations to `feedback-proposals.md`. |
| `chad-proposal-apply` | daily 04:30 UTC | n/a | Reads latest proposals JSON, applies narrow safe-list cron tunings. Gated by `chad-action-gate chad_self_modify_cron`. |
| `chad-skill-watch` | daily 09:00 UTC | n/a | Diffs the live skill catalog against last snapshot. Surfaces additions/removals/changes. |
| `memory-curator` | weekly Sat 04:00 UTC | inactivity-gated + budget guard | `chad-memory-curator` — Hermes-style consolidation. Snapshots first, spawns researcher with curator prompt, **draft-only**. |
| `spawn-poll` *(host launchd, not openclaw cron)* | every 5min | n/a | Moved from openclaw cron to a host-side launchd watchdog (`dev.nemoclaw.chad-spawn-poll`) on 2026-05-14. The previous agent-turn cron cost ~12.7M tokens/day and 288 dashboard entries to invoke a 5-second shell reconciler. Same script, no agent turn. |
| `spawn-gc` | weekly Mon 02:30 UTC | n/a | `chad-spawn-gc` — branch retention for `chad-spawn/*` on chad-state. |
| `experiment-night` | nightly 02:00 UTC | per-operator concurrent budget (default 3) | Four-phase autonomous experiment loop: propose from memory, observe running, evaluate at the eval window, auto-schedule calendar coordination. Auto-promotes or auto-retires per a regression threshold (default -0.30). Bounded by per-operator concurrent budget. See [Autonomy](autonomy.md). |

## Why the schedule looks the way it does

Several constraints shaped the cadence:

**Embedded inference is slow.** Chad's primary model
(`nvidia/nemotron-3-super-120b-a12b`) takes multiple seconds per
turn. Cron prompts are therefore one-line wrapper invocations —
the wrapper does the heavy work in shell or Python, and the model
just acks the result.

**Multi-turn tool calling is fragile** under embedded models. Heavy
work that needs multi-step reasoning happens *inside* a sub-agent
spawn, not in the cron prompt. The cron is the trigger; the spawn
is the worker.

**The token budget is daily.** Honor-based cap of 500k tokens, UTC
reset. A runaway Monday should not drain Tuesday's pool. Every cron
checks `chad-budget show --field remaining_tokens` near the top;
if reserve is too low, the wrapper falls through to a no-op or
queues a draft for the next run.

**Email cadence beats human latency.** 19×/day is enough that
allowlisted correspondents see a reply within an hour. Going
faster (every 30 min, 48×/day) burns ~60% more tokens with no
perceptible improvement.

## Wrapper invariant

Every cron prompt is **a one-line wrapper invocation**. Example:

```
Run `chad-gbrain-dream`. The wrapper syncs workspace docs into the
brain, detaches the slow embed/extract steps, and writes its own
summary to today's memory. Confirm it printed `gbrain dream
complete`, then exit.
```

The model fires the wrapper. The wrapper does the work. Long-running
operations detach via `nohup ... & disown` and write results to
`memory/<UTC-date>.md` — the next cron tick reads that log to
confirm completion.

This pattern decouples the model's wall-clock time from the work's
wall-clock time. A 5-minute embedding job doesn't tie up the
embedded model's session for 5 minutes.

## Where the work actually happens

The cron prompts are short. The wrappers are not. The full source
catalog is in `scripts/chad-cron-wrappers/`:

- **Inbox sweep:** `chad-mail-check`, `chad-mail-send`,
  `chad-email-check-cron`, `chad-autosend-replies`, `chad-drafter`,
  `chad-action-gate`
- **Brain maintenance:** `chad-gbrain-dream`, `chad-ensure-today-memory`
- **Issue triage:** `chad-issue-triage-cron`
- **Self-improvement:** `chad-self-improve`, `chad-budget-audit`,
  `chad-proposal-apply`, `chad-skill-watch`
- **Memory curator:** `chad-memory-curator`, `chad-memory-snapshot`
- **Spawn substrate:** `chad-spawn-poll`, `chad-spawn-gc`
- **Plumbing:** `chad-route-prompt`, `chad-auth-context`,
  `chad-premium`, `chad-premium-client`, `chad-dump-logs`,
  `chad-cron-reload`, `chad-workspace-backup`, `chad-log-event`

Each wrapper has SPDX headers and shellcheck-clean. The source repo
is the canonical reference; this page is the schedule overview.

## Audit & observability

- **Every wrapper appends to today's memory file**
  (`memory/<UTC-date>.md`) so the next session sees a record of what
  fired.
- **Every action-gate decision** lands in
  `auto-action-log.jsonl`. See [Autonomy](autonomy.md).
- **Every spawn writes** to `subagents/<task-id>/`. See
  [Orchestrator](orchestrator.md).
- **Every cron run is logged by openclaw** at
  `~/.openclaw/cron-runs.jsonl`. Failures surface via the next
  `chad-budget-audit`.

## Per-cron context tuning

Each cron job runs in an isolated session, so by default the gateway
loads its full bootstrap context — skill descriptions, identity
files, plugin manifests — into every fire. For wrapper-only crons
that only need to ack a sentinel line, that's wasteful. The gateway
exposes a `--light-context` flag that swaps the bootstrap for a
slimmed one:

```bash
# Apply to one cron
openclaw cron edit <job-id> --light-context

# Apply to all
for id in $(openclaw cron list --json | jq -r '.jobs[].id'); do
  openclaw cron edit "$id" --light-context
done
```

Observed input-token savings on Nemotron, same wrapper, same
sentinel:

| Cron | Before | After | Reduction |
|---|---|---|---|
| `chad-skill-watch` | ~177k | ~48k | 73% |
| `chad-proposal-apply` | ~177k | ~32k | 82% |
| `chad-budget-audit` | ~64k → still varies | ~64k | depends on findings count |

`chad-setup.sh` will re-apply `--light-context` to every cron it
registers. If you migrate older crons by hand, the for-loop above
is idempotent.

## Idle-timeout floor

The Nemotron path occasionally hangs mid-stream. Without an idle
timeout, hung sessions can sit for many minutes before the cron
scheduler gives up. Set a floor in `openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "inference/nvidia/nemotron-3-super-120b-a12b" },
      "timeoutSeconds": 600,
      "llm": { "idleTimeoutSeconds": 60 }
    }
  }
}
```

A hung session now fails fast (60 s of no model output) and the
next cron tick retries. Combine with `--light-context` and most
wrapper-only crons finish in 30-100 s.

## Delivery flags (load-bearing)

Every cron job must be registered with `--no-deliver
--best-effort-deliver`, persisting as `delivery.mode = "none",
delivery.bestEffort = true` in `cron/jobs.json`. Without these,
the gateway's default behavior is "deliver the wrapper's stdout to
the last messaging channel," which fails closed when no channel is
configured (the chad sandbox has none) and surfaces as an
`Error` cron status — even when the wrapper itself ran fine.

`chad-setup.sh` registers every chad-owned cron with these flags,
patches pre-existing crons on every run (idempotent), and the
chad-readme calls this out as load-bearing.

## What changed recently

- Added `memory-curator` (weekly Sat) — Hermes-style memory
  consolidation. Inactivity-gated.
- Added `spawn-poll` (every 5 min) — async gha spawn reconciler.
- Added `spawn-gc` (weekly Mon) — chad-state branch retention.
- Added `chad-proposal-apply` (daily) and `chad-skill-watch` (daily)
  to close the self-improvement loop alongside `chad-budget-audit`.
- `gbrain-dream` cadence corrected to 03:30 UTC (was sometimes
  documented as 03:00).
- `email-check` reduced from 48×/day to 19×/day for ~60% token
  savings. See [the introduction](intro.md) for context.
- `--light-context` flag applied to every cron — typical 70–80%
  input-token reduction on wrapper-only fires.
- `agents.defaults.llm.idleTimeoutSeconds = 60` added — bounds
  worst-case latency when Nemotron hangs.

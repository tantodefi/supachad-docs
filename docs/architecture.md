# Architecture

Chad is a small amount of glue across a stack of things that already
work. The interesting design is in the boundaries: where Chad's process
ends and OpenShell's gateway begins; where a sub-agent's filesystem
ends and the GitHub Actions runner's begins; where the autonomy
boundary sits relative to each external action.

## The concentric rings (plus an outer supervisor tier)

A naked CLI agent has no blast-radius story. Chad runs inside three
boundaries, each with a different threat model — plus a fourth
supervisor tier that lives _outside_ the pod and watches it from the
host so token-expensive supervision doesn't run inside the agent layer.

```mermaid
graph TB
  subgraph L0["L0 · Host (operator machine)"]
    H1[nemoclaw CLI]
    H2[Cloudflare tunnel]
    H3[Credentials + SSH keys]
    H4[chad-tunnel<br/>SSH local-forward<br/>:8901 → chad-shim]
  end

  subgraph L1["L1 · Host supervisors (launchd, 5-min cadence)"]
    W1[chad-gateway-watchdog<br/>OOM-recover gateway<br/>with 4 GB heap]
    W2[chad-shim-watchdog<br/>restart shim on death]
    W3[chad-spawn-poll<br/>reconcile GHA spawns]
    W4[chad-webui-ingest<br/>chats → gbrain]
    W5[nvidia-liveness<br/>model dropdown sweep]
  end

  subgraph L2["L2 · Container (OpenShell pod)"]
    C1[Gateway user · capsh drops]
    C2[L7 proxy + OPA policy<br/>MITM TLS for inspect hosts]
    C3[L1 → L2 SSH ingress<br/>only path in]
  end

  subgraph L3["L3 · Sandbox (sandbox user, uid 998)"]
    direction TB
    S0[openclaw gateway<br/>port 18789]
    S1[Chad main agent<br/>+ 12 standing crons]
    S2[chad-shim.py<br/>port 8901<br/>OpenAI bridge]
    S3[Sub-agents<br/>local + gha]
    S4[Memory stores<br/>gbrain · lancedb · wiki]
    S5["bin/ shims<br/>(wrapper-bug fixes)"]
  end

  subgraph L4["L4 · Per-spawn breakout"]
    G1[GitHub Actions runner<br/>fresh VM per workflow]
  end

  L0 --> L2
  L1 -.supervises.-> L2
  L1 -.supervises.-> L3
  L2 --> L3
  L3 -.spawns.-> L4
  L3 -.event-stream.-> L1

  classDef host fill:#fef3c7,stroke:#d97706,color:#000
  classDef watch fill:#fde68a,stroke:#b45309,color:#000
  classDef container fill:#ddd6fe,stroke:#7c3aed,color:#000
  classDef sandbox fill:#c7d2fe,stroke:#4f46e5,color:#000
  classDef gha fill:#fecaca,stroke:#dc2626,color:#000
  class L0 host
  class L1 watch
  class L2 container
  class L3 sandbox
  class L4 gha
```

| Tier | What lives here | What enforces the boundary | Failure mode + recovery |
|---|---|---|---|
| **L0 · Host** | nemoclaw CLI, credentials, Cloudflare tunnel, SSH keys | OS user, file permissions, SSH keys | Host crash = everything stops; restart laptop |
| **L1 · Host supervisors** | 5-min launchd cadence — gateway watchdog, shim watchdog, spawn-poll, webui-ingest, nvidia-liveness | macOS launchd; each plist is independent | If a watchdog dies, launchd restarts it; no in-band supervision needed |
| **L2 · Container** | OpenShell gateway user, L7 proxy, OPA policy engine | Linux capabilities (capsh drops), policy hash check at boot | Container restart resets all in-process state but state on bind-mounts persists |
| **L3 · Sandbox** | openclaw gateway, Chad agent, chad-shim.py, sub-agents, memory stores, wrapper-bug shims | Per-binary L7 egress allowlists pinned by `/proc/self/exe`; per-operator API-key fail-closed | Gateway OOM → L1 watchdog respawns with 4 GB heap; shim crash → L1 watchdog restarts within 5 min |
| **L4 · GHA runner** | One-off sub-agent spawns under `substrate: gha` | Fresh VM per workflow run, no shared state with Chad | Lossy by design; results round-trip via `chad-state` branches |

Three of the rings (L0, L2, L3) are kernel/OS-enforced. The L7
allowlists at the sandbox layer are policy-enforced — same syscall
vocabulary, but the squid+OPA combination decides whether each egress
flow is in-policy. **L1 is the supervisor tier** — it runs no agent
turns and consumes zero inference tokens. State changes detected by
L1 (gateway restarts, shim crashes, spawn-poll reconciliations) flow
back to L3 via the `agent-inbox.jsonl` event stream so the next cron
agent turn can pick up overnight incidents.

L4 is a per-spawn substrate choice, not an always-on ring.
See [Substrates](substrates.md).

!!! warning "L3.5 loses L7 enforcement"
    The GHA breakout swaps *kernel-isolation* for *policy-isolation*.
    A spawn under `substrate: gha` runs in a fresh GitHub Actions VM
    — strong isolation from Chad's container — but the L7 proxy +
    OPA stack does not exist on the runner side. Per-binary egress
    allowlists that hold inside L3 do **not** hold on the runner.
    Pick `gha` for self-contained jobs (codex writing a markdown
    report, opencode hitting a public API). Pick `local` for jobs
    that need L7 enforcement (anything writing back to `chad-state`,
    anything touching premium credentials).

## The spawn flow

A typical chad-spawn invocation walks through this:

```mermaid
sequenceDiagram
participant Caller
participant Spawn
participant Budget
participant Ledger
participant Worker
participant Memory
Caller->>Spawn: chad-spawn kind X task-file T
Spawn->>Budget: reserve N tokens
Budget-->>Spawn: ok or exit 77
Spawn->>Ledger: append status queued
Spawn->>Ledger: append status running
Spawn->>Worker: run binary with prompt
Worker-->>Spawn: result JSON
Spawn->>Ledger: append status done
Spawn->>Memory: chad-collect merges result
```

The conditional split between the two substrates:

- **`local`** — `Spawn` runs the binary in-container under timeout, captures stdout, parses the last line as JSON.
- **`gha`** — `Spawn` pushes a `chad-spawn/<id>` branch with the rendered prompt and dispatches an `agent-job.yml` workflow. With `--async`, it returns the task id immediately; the `chad-spawn-poll` cron reconciles when the runner commits `result.json` back. With `--sync`, it polls until the branch updates.

Self-messages (`Spawn->>Spawn`) like *render prompt from manifest* and *push spawn branch* happen between the steps above; they're elided here so the swimlanes stay readable.

Participants in plain English:

- **Caller** — Chad, a cron wrapper, or a chat turn.
- **Spawn** — `chad-spawn`, the orchestrator entry point.
- **Budget** — `chad-budget`, daily token reservation.
- **Ledger** — `queue/tasks.jsonl`, append-only task record.
- **Sub** — the sub-agent binary (kind-dependent).
- **Memory** — today's `workspace/memory/<date>.md` file.

## The seven sub-agent kinds

Each kind is a YAML manifest pinning a binary, a network policy
preset, a default substrate, and a prompt template.

| Kind | Binary | Substrate | What it's for |
|---|---|---|---|
| `coder` | `pi` | local | Write/refactor code with build + tests |
| `researcher` | `claude` | local | Brain-first lookups; gh search if brain insufficient |
| `writer` | `claude` | local | Draft mail/docs; never publishes |
| `reviewer` | `claude` | local | Audit a PR diff; GET-only on GitHub |
| `fitness` | `claude` | local | Strength + mobility from gbrain-ingested books |
| `codex` | `codex` (npm) | gha | OpenAI Codex; NVIDIA fallback when no `OPENAI_API_KEY` |
| `opencode` | `opencode` (npm) | gha | Multi-provider; honors `OPENAI_BASE_URL` |

Adding a new kind is four files (manifest, policy preset, optionally a
runner install step, sync) — no recompile, no image rebuild. Details
in [Orchestrator](orchestrator.md).

The kinds above are **chad-spawn** — imperative one-shot sub-agents.
A second, complementary orchestrator, **chad-Smithers**, handles
*durable multi-step workflows* (experiments, model fusion, the
autonomy ladder) with SQLite-backed crash-resume and a web IDE at
`runs.supachad.com`. The two are bridged, not exclusive: a Smithers
workflow can offload a heavy step to the `gha` substrate via
`chad-spawn-gha`. See [Runs IDE](runs-ide.md).

## The four memory layers

```mermaid
graph LR
  subgraph WS["Always-injected (per-session)"]
    A[IDENTITY · SOUL · USER]
    B[AGENTS · TOOLS · MEMORY]
  end
  subgraph LTM["Semantic LTM (autoCapture)"]
    C[memory-lancedb<br/>NV-Embed-v1 · 4096-dim]
  end
  subgraph WIKI["Named-entity wiki (bridge)"]
    D[memory-wiki vault<br/>Obsidian-style]
  end
  subgraph BRAIN["Cross-domain hybrid"]
    E[gbrain<br/>PGLite vector + graph]
  end

  Session([Chad session]) --> WS
  Session -. recall .-> LTM
  Session -. recall .-> WIKI
  Session -. CLI subprocess .-> BRAIN
```

What goes where:

- **Identity / principles / autonomy policy** → workspace files. Loaded
  into every main session. Operator-owned, not curated by Chad.
- **"Remember this preference / decision / contact"** → memory-lancedb.
  Captures fire automatically on multilingual triggers
  (remember/preferences/decisions/possessives).
- **Per-system reference / per-correspondent rich page** → memory-wiki
  vault. Look up by name. Backlinks form a graph.
- **Cross-domain knowledge / book chunks / research** → gbrain. Two
  books fully ingested for the `fitness` kind today.

The full decision tree is in [Memory stack](memory.md).

## The autonomy boundary

Every external action passes through the action gate:

```mermaid
flowchart LR
  A[Action proposed<br/>e.g. send mail to X] --> G{chad-action-gate}
  G -->|auto| S[Ship it]
  G -->|draft| P[Park for review]
  G -->|block| X[Refuse]
  G -->|budget| Q[Defer]
  G -->|killed| K[Halted by .auto-disabled]
  S --> L[Audit log<br/>auto-action-log.jsonl]
  P --> R[Today's memory file]
  X --> R
```

The gate's policy is `/sandbox/.openclaw-data/auto-actions.json`. It's
intended to be **readable** — the autonomy roadmap is the diff between
"what's `auto` today" and "what's `draft` or `block` today." See
[Autonomy](autonomy.md).

## Two execution substrates

Sub-agent spawns route to one of two backends:

| Substrate | Runs in | Isolation | Network policy | Async |
|---|---|---|---|---|
| `local` | Chad's container | Process tree shared with parent | L7 policy preset enforced | No (sync only) |
| `gha` | Fresh GitHub Actions runner | Per-spawn VM | Lost — runner has wide egress | Yes (`--async`) |

The `local` substrate is right when the sub-agent needs gbrain, the
sandbox source clone, or NVIDIA inference. The `gha` substrate is
right when the sub-agent is self-contained — codex writing a markdown
report from a prompt, opencode running against an external repo.
Durable Smithers workflows also offload heavy steps to `gha` through
the `runSpawn()` bridge — see [Runs IDE](runs-ide.md).

## Where the source lives

- **NemoClaw** (NVIDIA-owned blueprint) — [tantodefi/NemoClaw](https://github.com/tantodefi/NemoClaw)
  on the `chad-dev` branch. The hardened sandbox image, the policy
  presets, the orchestrator scripts, the cron wrappers.
- **gbrain** — [tantodefi/gbrain](https://github.com/tantodefi/gbrain).
  PGLite-backed knowledge brain.
- **chad-state** (private) — `tantodefi/chad-state`. Backup of the
  workspace dir + the agent-job workflow for the GHA substrate. Not
  publicly readable; no link.
- **OpenClaw** — [openclaw.ai](https://openclaw.ai). The agent
  runtime Chad runs as.
- **OpenShell** — [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell).
  The sandbox + L7 gateway.

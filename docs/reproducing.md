# Reproducing Chad

Honest answer first: **Chad is not trivially reproducible.** A faithful
clone needs four pieces of infrastructure the operator runs at their
own cost, plus access to two specific GitHub repos that are public
but tightly coupled. This page lays out what's needed and where the
sharp edges are.

## What you'd need

### 1. Hardware / sandbox

A machine that can run an OpenShell sandbox pod. The reference
deployment is a Mac M4 Pro with 24 GB RAM and Docker Desktop, but
any host that runs Linux containers with k3s or Docker works.
Resource floor:

- **CPU/GPU.** Embedded inference runs the agent loop;
  `nvidia/nemotron-3-super-120b-a12b` lives behind the
  `inference.local` gateway in the reference setup. Hosting that
  inference yourself needs a GPU box; using the free NVIDIA
  Endpoints tier needs only network egress.
- **RAM.** 16 GB is uncomfortable but possible; 24+ GB recommended.
- **Disk.** ~10 GB for the sandbox image, plus PVC for state.

### 2. Mailbox

A dedicated Proton account is required for the agent's own mailbox
(e.g. `agent@example.com` — distinct from the operator's personal
inbox). The agent reads/writes via the `go-proton-api` library wrapped
in `proton-tool`, with credentials stored in
`/sandbox/.nemoclaw/credentials.json`.

You **cannot** point Chad at your personal mailbox without
significant policy work — the autonomy roadmap assumes Chad's
mailbox is its own, distinct from the operator's. Self-replies are
explicitly blocked in `auto-actions.json` (the agent address gets
`block` while operator addresses get `auto`) precisely because the
loop would be catastrophic otherwise.

### 3. GitHub identity

A separate GitHub account with **classic PAT** (`ghp_*`, not
fine-grained `github_pat_*`) — this is the agent's own GitHub
identity, distinct from the operator's account.

The classic-vs-fine-grained distinction is load-bearing:
fine-grained PATs cannot see other-owner repos even with
collaborator grants. If your Chad needs read/write access to a
private state repo owned by your operator account,
the classic PAT is the only way.

### 4. Inference provider keys

At minimum one of:

- **`NVIDIA_API_KEY`** (`nvapi-*`) — free tier from
  [build.nvidia.com](https://build.nvidia.com). Powers Nemotron
  inference, embeddings (`nv-embed-v1`), and is the GHA-substrate
  fallback for codex/opencode kinds.
- **`OPENAI_API_KEY`** — for codex/opencode kinds when you want
  real OpenAI.
- **`ANTHROPIC_API_KEY`** — for the `claude`-based kinds (researcher,
  writer, reviewer, fitness) and for premium escalation.

`NVIDIA_API_KEY` alone is enough to bring Chad up. Add the other
two as you need their specific kinds.

### 5. Two state repos

- **NemoClaw** (`tantodefi/NemoClaw` on `chad-dev` branch) — the
  hardened sandbox image, blueprint, scripts, kinds. Public, MIT/Apache.
  Forkable.
- **chad-state** — *private*. Holds the workspace backups and the
  `agent-job.yml` workflow for the GHA substrate.

If you fork NemoClaw, your fork's `chad-dev` plus your own private
chad-state are the runtime substrate. The orchestrator's `chad-spawn`
and `chad-backup-to-github` both target chad-state via
`CHAD_STATE_REPO` env var, so you can swap repos with one config
change.

## What's not portable

- **Workspace identity files.** `IDENTITY.md` / `USER.md` /
  `SOUL.md` / `MEMORY.md` are operator-specific. The reference
  versions document two named operators (a developer and a
  domain-expert collaborator); your fork starts these blank or
  with your own users.
- **gbrain content.** The fitness sub-agent kind cites *Starting
  Strength* and *Becoming a Supple Leopard* chunks ingested into
  gbrain. These are operator-curated knowledge, not part of the
  default install — you'd ingest your own.
- **Cron schedule.** Reference cadence is tuned for one operator's
  workload. Different volumes warrant different schedules.

## What's portable

- Sandbox blueprint, L7 policy presets, image build
- Six orchestrator helpers + seven sub-agent kinds
- Hermes-style curator + memory snapshot pattern
- GHA substrate with NVIDIA fallback
- Action gate + autonomy policy framework
- Cron wrapper architecture (one-line invocations + detached jobs)

## Minimum viable Chad

The cheapest possible setup:

1. Fork `NVIDIA/NemoClaw`. Track `chad-dev`.
2. Create a private `<your-org>/chad-state` repo for backups.
3. Get an `NVIDIA_API_KEY` (free).
4. Provision an OpenShell sandbox via `nemoclaw sandbox create`.
5. Deploy creds + scripts: `./scripts/chad-setup.sh chad`.
6. Run `chad-state-bootstrap` to install the GHA workflow.
7. `gh secret set NVIDIA_API_KEY --repo <your-org>/chad-state ...`.
8. Reduce `auto-actions.json` to your own allowlist. The policy
   shape, the kill-switch file, the daily budget map, and the audit
   log live on the [Autonomy](autonomy.md) page — start there before
   editing.
9. Touch `.auto-disabled` until you're ready.

This gets you Chad-shaped runtime: sandbox + memory stack + cron
schedule + gha substrate. No claude kinds (need Anthropic key), no
proton mailbox (until you set one up), no gbrain content (until you
ingest some).

## When Chad is the wrong answer

If you want a chat agent: this isn't it. Chad's value is the
always-on layer.

If you want a single-prompt assistant: too much infrastructure for
the payoff.

If you don't have a workload that needs trust ratcheting: skip the
action gate and most of this design.

If you want to run agents but not maintain the hardened sandbox:
[NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) directly,
without the chad-dev orchestrator overlay, is a more reasonable
starting point.

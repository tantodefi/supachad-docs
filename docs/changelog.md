# Changelog

A curated record of what shipped on `chad-dev`. Hand-edited from
git log; not exhaustive. Conventional Commits scope (`feat(chad/*)`)
maps to the headings below.

## 2026-05-13

### Memory pipeline consolidation + gateway watchdog

Three jobs now converge OpenWebUI chats, workspace events, and system
docs into a single bounded gbrain. `chad-gbrain-prune` (sandbox cron,
Sundays 02:00 UTC) is the new weekly retention sweep: deletes
`memory/<date>` and `events/<date>` pages older than 365 days,
`chat/<id>` pages older than 180 days, and workspace
`dream-digest-*.md`/`feedback_*.md`/`prune-log-*.md` files older
than 30 days. Default `DRY_RUN=1`; protects `system/*`, `agent/*`,
and the workspace `<date>.md` journal (source-of-truth).
`chad-webui-ingest` (host launchd, 04:30 UTC daily) reads chats
updated in the last 25 h from `~/.nemoclaw/openwebui/data/webui.db`
(turns live in the `chat.chat` JSON column — not the `message`
table, which is for channels), renders each as markdown with
frontmatter, and SSHes the content into the sandbox via
`gbrain put chat/<chat-id>`. After ingest, the next
`chad-gbrain-dream` pass picks chats up alongside the workspace
journal. The dream wrapper now surfaces the `Embedded/Chunks`
ratio in `dream-digest-<date>.md` and writes
`feedback_embed_staleness_<date>.md` if coverage drops below 95%
(catches a silently-stalled detached `gbrain embed --stale`).

`chad-gateway-watchdog` (host launchd, every 5 min) is the new
supervisor for the OpenClaw gateway. The chad pod has no PID-1
supervisor for the gateway process — when it crashed on
2026-05-12 with a V8 OOM at the default 1.7 GB heap, nothing
restarted it for 9 hours, silently failing every cron and
chad-shim call. The watchdog pings the WS port via SSH, kills any
stale process if needed, and relaunches with
`NODE_OPTIONS=--max-old-space-size=4096` to push the OOM
threshold further out.

**Critical doc fix.** Discovered during the same audit: the chad
pod has **no PVC backing `/sandbox`** — verified via
`kubectl get pod chad -n openshell -o jsonpath='{.spec.volumes[*].name}'`.
The only mounts are `openshell-client-tls`,
`openshell-supervisor-bin`, and the kube-api-access SA volume.
Running `kubectl delete pod chad` wipes ~1.2 GB of state. `chad-readme.md`
§ 8 and `docs/workspace/workspace-files.md` were updated to remove
the old "PVC outlives container restarts" claim and add an
SSH-tar backup recipe to take before any pod-recreating operation.
The proper fix is a PVC for `/sandbox` in the nemoclaw-blueprint
StatefulSet.

## 2026-05-12

### OpenWebUI auto-curated dropdown + cloudflared HTTP/2 fix

The model picker in OpenWebUI is now auto-curated. A host launchd
job (`nvidia-liveness`, daily 04:00 UTC) probes every model in
NVIDIA Build's `/v1/models` with a one-token chat completion,
classifies each as `live` / `dead` / `unknown` / `transient`
(HTTP 410 Gone marks dead immediately; 4xx/5xx need three
consecutive strikes; network timeouts preserve previous status),
ranks them per-provider by parsed version + params, and writes
`featured` + per-model status to `~/.nemoclaw/openwebui/liveness.json`.
A separate sibling proxy (`nvidia-proxy`, host launchd, KeepAlive)
sits in front of `integrate.api.nvidia.com` — passes through every
request unchanged except `GET /v1/models`, which it filters to the
featured set. OpenWebUI's `OPENAI_API_BASE_URL` points at the
proxy so the dropdown stays current with NVIDIA's catalog and
hides EOL'd models the day they're flagged.

Curation is one TOML file (`scripts/openwebui/nvidia-curation.toml`)
with `per_provider_limit` and a glob `exclude` list. Default is
flagship-only — ~14 models. Curated `model` rows in `webui.db` whose
`base_model_id` is dead get auto-soft-disabled (`is_active=0`)
by the liveness sweep, so the dead-llama-3.1-405b entries that had
been producing user-visible 410 errors stopped appearing.

Separately: cloudflared on the tunnel side was reconnecting every
10–30 minutes with QUIC stream timeouts ("no recent network
activity"). Residential routers / NAT firewalls / mobile carriers
prune idle UDP flows aggressively. Forcing `--protocol http2`
moves the transport to TCP and removes the entire failure class
at ~5–15 ms of extra latency per request.

Also pinned `WEBUI_SECRET_KEY` from `.env` so container recreates
don't regenerate the file inside the image layer, which had been
invalidating every existing browser JWT and bouncing users back
to the sign-in page on every redeploy.

## 2026-05-11

### Sandbox survival hardening

The Bonjour mDNS plugin was crash-looping the gateway on the
loopback-only sandbox. Disabled it in `openclaw.json`'s
`agents.defaults`. Raised `agents.defaults.llm.idleTimeoutSeconds`
from 60 s to 180 s so the slow cold-start path on
`nvidia/nemotron-3-super-120b-a12b` doesn't trip the idle gate
mid-tool-call. Consolidated the split-brain
`feedback-proposals.md` path so the `chad-self-improve` wrapper
and the curator agree on a single canonical location. Rewrote
the `proton-calendar` SKILL.md with a cron-boundary decision
table and a link to EMAIL-POLICY so subagents don't reach for the
calendar when an email reply would do.

A new `chad-readme.md` § 11.5 documents the deploy gap between
`source/scripts/chad-cron-wrappers/` and `/usr/local/bin/` on the
running image, plus the `kubectl cp` recovery procedure when a
wrapper needs to be pushed without rebuilding the image.

## 2026-05-07

### Cron context optimization + reliability cleanup

Applied `--light-context` to every registered cron via
`openclaw cron edit`. Observed input-token reductions of 70–82% on
wrapper-only fires (e.g. `chad-skill-watch` 177k → 48k, duration
167 s → 55 s). Added
`agents.defaults.llm.idleTimeoutSeconds = 60` to `openclaw.json` so
hung Nemotron sessions fail fast instead of sitting until the
600 s job timeout. Re-registered the three crons that were
documented but missing from the live gateway
(`memory-curator`, `spawn-poll`, `spawn-gc`); the chad-readme
listed nine but `chad-setup.sh` had since grown to register
eleven. Sticky `Error` statuses on `chad-proposal-apply`,
`chad-skill-watch`, `self-improve`, and `chad-budget-audit` cleared
once the underlying delivery `Channel is required` failure was
resolved by re-applying `--no-deliver --best-effort-deliver` to
every job.

## 2026-05-06

### Phase C — async sub-agent spawns

`chad-spawn --async --substrate gha` now returns a task_id immediately
and writes a `running` ledger entry. The new `chad-spawn-poll` cron
(every 5 min) reconciles when the GHA runner commits result.json back
to the spawn branch, transitioning the ledger and triggering
`chad-collect`. Async mode deletion via `chad-spawn-gc` (weekly Mon)
prevents `chad-spawn/*` branches from accruing on chad-state. Added
`opencode` kind + preset (multi-provider coding CLI) and a new
`--binary-override` flag for per-spawn binary swap (e.g., spawning
`writer` with the `codex` binary instead of `claude` while keeping
the writer's prompt template and timeout). The kind's L7 policy
preset still applies — the override binary must be in that preset's
allowlist. Ledger entries now carry `substrate` and `async` fields.

### NVIDIA fallback in the GHA agent-job runner

The runner now picks an inference provider at workflow time. With only
`NVIDIA_API_KEY` set, codex / opencode kinds route through
`integrate.api.nvidia.com/v1` (OpenAI-compatible) targeting Nemotron;
adding `OPENAI_API_KEY` automatically upgrades to real OpenAI.
`claude` requires `ANTHROPIC_API_KEY` (no NVIDIA fallback —
Anthropic-only). The resolved provider lands in `result.json` so
chad-collect knows which backend produced each output.

### GHA substrate for chad-spawn (popebot pattern)

Sub-agent spawns can now route to a GitHub Actions runner per job.
New `--substrate <local|gha>` flag on chad-spawn, kind manifests gain
a `substrate` field, `chad-spawn-gha.sh` helper handles
push + dispatch + sync poll. Workflow template + `chad-state-bootstrap`
installer ship in the source repo. The branch on chad-state *is* the
job record — no jobs table, no queue service.

### Codex kind stub + design doc

First non-built-in kind, validating the "no recompile, no image
rebuild" extensibility claim. Architecture for spawn substrates
captured in `docs/design/spawn-as-github-run.md`.

### Hermes-style memory curator + pre-mutation snapshots

`chad-memory-curator` runs weekly Sat 04:00 UTC. Inactivity-gated,
budget-guarded, draft-only. Snapshots lancedb + wiki + workspace
before any work via `chad-memory-snapshot` (tar.gz, keep last 5,
reversible rollback). Memory-lancedb `autoCapture` self-healed to
`true` by chad-setup.sh Step 3e — the unlock for Chad's previously
empty LTM. Step 3f actively removes gbrain from `mcp.servers` if
re-introduced (PGLite single-process file lock means MCP serve
blocks every cron wrapper that uses gbrain CLI).

## 2026-05-05

### Memory plugin stack wired

memory-lancedb (NV-Embed-v1 4096-dim) + memory-wiki (bridge mode) +
active-memory + tokenjuice configured and loaded. Two-layer architecture:
semantic LTM via lancedb, named-entity wiki for retrieval-by-name.

### Self-improvement loops closed

`chad-self-improve` weekly cron, `chad-budget-audit` weekly cron,
`chad-proposal-apply` daily cron with safe-list. Cron-tuning
proposals can land via the gate; anything riskier stays draft-only.

## 2026-04-30 → 2026-05-04

NIM embeddings overlay and gbrain integration. Workflow regression
matrix with variants and parallel sub-agent harness. Fitness kind +
brain-first pattern. Premium routing with Anthropic side-channel.
Per-task budget profiles + model registry. Hybrid Phase-1/Phase-2
cron wrapper infrastructure.

---

The current state of `chad-dev` is what the rest of these docs
describe. If anything here feels stale, the source repo is the
canonical reference — please file an issue.

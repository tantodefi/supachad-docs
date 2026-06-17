# Memory stack

Chad has four distinct memory surfaces. They don't compete; each
serves a different shape of recall. The "where do I write what"
question has a three-line answer, captured at the bottom of this page.

## The four layers

### 1. Always-injected workspace files

**Path:** `/sandbox/.openclaw-data/workspace/*.md`

Loaded automatically by openclaw at session start (main session only).
Each file is a few-thousand-character markdown doc, char-bounded so
it stays in the system prompt without crowding out task context.

| File | Purpose |
|---|---|
| `IDENTITY.md` | Who Chad is, autonomy policy, kill switch |
| `SOUL.md` | Principles, brain-first rule, cron discipline |
| `USER.md` | Per-operator pages (with disambiguation rules) |
| `AGENTS.md` | Workspace contract, daily memory pattern |
| `TOOLS.md` | Operational cheat sheet (paths, creds, commands) |
| `MEMORY.md` | Curated long-term memory — main-session only |
| `HEARTBEAT.md` | Liveness pulse |

`MEMORY.md` is intentionally main-session-only — when Chad is in a
shared context (group chat, third-party correspondent), this file is
not loaded so personal notes don't leak. The boundary is enforced at
the openclaw session-type level.

### 2. memory-lancedb (semantic LTM)

**Backend:** NVIDIA NV-Embed-v1 at 4096 dimensions, served from
`integrate.api.nvidia.com/v1`.
**DB:** `/sandbox/.openclaw-data/memory/lancedb`.

Captures fire automatically. The `MEMORY_TRIGGERS` regex array (built
into the plugin) covers multilingual cues for *remember*, *preferences*,
*decisions*, *contact info*, *possessives*, and *always/never* — when
something Chad processes looks like a fact worth keeping, it lands
here.

Configuration:

```json
{
  "autoRecall": true,
  "autoCapture": true,
  "captureMaxChars": 1500,
  "embedding": {
    "model": "nvidia/nv-embed-v1",
    "baseUrl": "https://integrate.api.nvidia.com/v1",
    "dimensions": 4096
  }
}
```

`chad-setup.sh` Step 3e self-heals `autoCapture: true` on every setup
run — without it, the triggers exist but no captures land. Step 3d
applies a small patch to the plugin so the `dimensions` parameter
doesn't get sent in embed requests (NVIDIA's endpoint rejects it).

### 3. memory-wiki (named-entity knowledge)

**Vault:** `/sandbox/.openclaw-data/wiki/main/`. **Render:** Obsidian
(`[[wikilinks]]`). **Mode:** bridge with `readMemoryArtifacts: true`,
which means pages here surface in main-session recall.

Currently empty by design — populates organically as autoCapture +
hand-written entries accumulate. Worth a wiki page when:

- The entity is queried by *name* repeatedly (a correspondent, a
  recurring topic)
- The content is heavier than `USER.md`'s summary section can hold
- Multiple memory entries on the same topic deserve a hub page

### 4. gbrain (cross-domain hybrid vector + graph)

**CLI:** `/usr/local/bin/gbrain`. **DB:** `/sandbox/.gbrain/brain.pglite`.
**Access:** subprocess CLI only — see the gotcha below.

```bash
gbrain query "<question>"      # hybrid vector+graph search
gbrain search "<keywords>"     # keyword-only (works even if embeddings stale)
gbrain put-page --title "..." --content "..." --tags ...
gbrain doctor                  # check embeddings backend
gbrain stats                   # page/chunk counts
```

Two books are fully ingested for the `fitness` sub-agent kind:
*Starting Strength* (Rippetoe, 313 chunks) and *Becoming a Supple
Leopard* (Starrett, 677 chunks). The `fitness` kind is instructed to
search gbrain first and only fall back to web fetches if the brain
returns nothing.

!!! warning "PGLite is single-process"
    gbrain runs on PGLite (embedded Postgres-WASM). It supports **one
    connection per data directory at a time**. Concurrent access aborts.

    Chad therefore does **not** register gbrain as an MCP server — a
    long-running `gbrain serve` would hold the file lock and block
    every cron wrapper that uses gbrain CLI. `chad-setup.sh` Step 3f
    actively removes the MCP entry if it reappears.

### 5. active-memory (orchestrator, not a store)

The retrieval orchestrator. Reads from layers 1–4 and injects relevant
content into the system prompt per turn. Configured to scope to
`agents=["main"]`, `chatTypes=["direct"]` — sub-agents do **not**
get retrieval injection automatically; they see only what their kind
manifest puts in their prompt.

**What active-memory injects per turn:**

- **Always-on workspace files** (layer 1) — full text. Bounded by file
  char limits; the operator owns those budgets.
- **lancedb autoRecall** (layer 2) — top-k semantic matches against
  the turn's input. `k` and similarity threshold are tunable in
  `openclaw.json`.
- **Wiki pages by name** (layer 3) — only when the model explicitly
  asks (no implicit injection — wiki access is intent-driven).
- **gbrain results** (layer 4) — never auto-injected. Queries are
  explicit subprocess calls because of the PGLite single-connection
  rule.

**Why sub-agents are excluded:** active-memory injection is sized for
Chad's main session prompt budget. Replicating it for every sub-agent
spawn would multiply token spend with no proportional benefit — most
sub-agents are scoped to a single task and need only what their kind
manifest provides. Sub-agents that *do* need brain access (researcher,
fitness) call `gbrain query` directly inside their prompt template.

**Configuration lives in** `/sandbox/.openclaw/openclaw.json` under the
`activeMemory` key — agents, chat types, retrieval thresholds, and
the per-store enabled flags. The file is `444` (read-only) outside of
explicit `chad-setup` invocations.

## Newer state surfaces (2026-05-13/14)

Three runtime-state directories added in May 2026, all under
`/sandbox/.openclaw-data/` and all included in the workspace backup
manifest (so they survive pod resets):

| Path | Purpose |
|---|---|
| `identities/<slug>.md` | Per-operator persona files prepended by `chad-shim` to user messages. One file per operator slug (email local-part), plus `default.md` for unknown senders. Edits land without a shim restart (mtime-cached). |
| `state/experiments/{config,ledger,active,archive}` | Autonomous experiment lifecycle state. `config.json` carries the budget + thresholds + tag map; `ledger.jsonl` is the append-only event log; `active/<id>.json` is the running record; `archive/<id>.json` is the snapshot at promote/retire. See [Autonomy](autonomy.md). |
| `state/agent-inbox.jsonl` | Append-only structured event stream from host-side launchd watchdogs (`chad-gateway-watchdog`, `chad-shim-watchdog`, `chad-spawn-poll`). Cron agent turns can `tail` this at startup to surface state changes that happened between turns. |

These are tracked in `chad-workspace-files.txt` under `[runtime-dirs]`,
so the same `workspace-backup` cron that round-trips memory + crons +
identities also ships them to `chad-state`.

## Pre-mutation safety net

Before any bulk memory operation, `chad-memory-snapshot create`
tar-gzips:

- `/sandbox/.openclaw-data/memory/lancedb`
- `/sandbox/.openclaw-data/wiki/main`
- `/sandbox/.openclaw-data/workspace`
- `/sandbox/.openclaw-data/curator-runs/latest`

into `/sandbox/.openclaw-data/memory-snapshots/<utc>/`. Last 5
retained. Rollback is itself reversible — it snapshots current state
first.

## The Hermes-style curator

`chad-memory-curator` runs weekly (Sat 04:00 UTC). It:

1. Inactivity-gates: skips if a previous curator run was less than
   7 days ago, or if there was an autonomous action in the last hour.
2. Budget-guards: refuses to spawn if remaining tokens < 2× the
   reserve.
3. Snapshots: calls `chad-memory-snapshot create` before any work.
4. Spawns a `researcher` sub-agent with the curator prompt over recent
   LTM + workspace `MEMORY.md` + the last week of daily memory files.
5. Writes proposals to
   `curator-runs/<utc>/proposals.json` — **draft-only**. The operator
   reviews and applies; the curator and the `memory-curator.jsx`
   workflow are both `Approval`-gated, and pre-mutation snapshots make
   any apply reversible.

The output schema:

```json
{
  "lift_to_memory_md": [
    { "text": "...", "reason": "...", "source_ref": "ltm:<id>" }
  ],
  "consolidate": [
    { "keep_id": "ltm:<id>", "merge_ids": ["ltm:<id>", "..."], "reason": "..." }
  ],
  "archive": [
    { "id": "ltm:<id>", "reason": "..." }
  ],
  "summary": "<one-sentence overview>"
}
```

## Where do I write what?

| Question | Goes in |
|---|---|
| "Who am I, what's my mailbox, what's the kill switch?" | already there: `IDENTITY.md` |
| "What are the operating principles?" | already there: `SOUL.md` |
| "Remember this preference / decision / contact" | memory-lancedb (autoCapture catches it) |
| "Document this recurring gotcha or system reference" | memory-wiki page |
| "Cross-domain knowledge / book chunk / research finding" | `gbrain put-page ...` |
| "Daily session log" | `workspace/memory/<UTC-date>.md` (auto by wrappers) |
| "Curated long-term self-knowledge" | `MEMORY.md` (main session only) |

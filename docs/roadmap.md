# Capabilities & boundaries

What Chad does today, and what the design deliberately refuses to do.
This page is current state, not a wishlist. Status tracks the
[Changelog](changelog.md) head.

## Capabilities

| Capability | Where | Notes |
|---|---|---|
| Nested-spawn isolation | `gha` substrate | Sub-agents spawn onto a per-job GitHub Actions runner instead of sharing Chad's container. See [Substrates](substrates.md). |
| Async sub-agent spawn | `chad-spawn --async --substrate gha` | Returns task id immediately. `chad-spawn-poll` reconciles `result.json` from the runner branch; `chad-spawn-gc` retires branches weekly. |
| Hermes-style memory curator | `chad-memory-curator` weekly + `memory-curator.jsx` | Inactivity-gated, snapshot-first, draft-only LTM consolidation. See [Memory](memory.md). |
| Self-modify safe-list (cron tunings) | `chad-proposal-apply` daily | Applies a narrow safe-list (`timeoutSeconds`, `maxOutputTokens` within ±2×), gated by `chad-action-gate chad_self_modify_cron`. |
| NVIDIA fallback for OpenAI-compat kinds | `codex`, `opencode` kinds | Falls through to `integrate.api.nvidia.com` when `OPENAI_API_KEY` is absent. |
| Premium escalation | `chad-premium` + AuthContext | Anthropic Claude routing for depth Nemotron lacks. See [Premium escalation](premium.md). |
| Open WebUI front-end | `chad-shim.py` + docker-compose | Chad as an OpenAI-compat model. See [Front-ends](front-ends.md). |
| Nemotron 3 Ultra 550B + reasoning | hosted inference profiles | Newest NVIDIA open model, reasoning on by default. Self-hosted profiles stay on Super 120B. |
| Smithers evolutionary experiments | `scripts/chad-smithers/experiments.jsx` | Durable host-side runner: model router, evolutionary selection, crash-resume, nightly leaderboard note to OpenWebUI. |
| Moshi notifications + phone approval | `moshi-hook` hooks + `chad-tmux` | Host `claude` runs notify the phone and route approval gates to it. |
| Runs IDE for Smithers workflows | `runs.supachad.com` (`serve-runs.js` + `chad-runs`) | Web IDE over the Smithers DBs: run history, live task tree, `.jsx` editor, leaderboard, browser launch/cancel/approve/fork. See [Runs IDE](runs-ide.md). |
| Model fusion + daily model refresh | `fusion.jsx` + `refresh-models.js` | One prompt across N models in parallel → fuse; roster auto-refreshed daily from NVIDIA's `/v1/models`. |
| Two orchestrators, bridged | chad-spawn + chad-Smithers | One-shot GHA-isolated sub-agents *and* durable workflows; `runSpawn()` offloads heavy workflow steps via `chad-spawn`. See [Orchestrator](orchestrator.md). |
| chad-spawn / cron features as workflows | `issue-triage` · `content-pipeline` · `self-improve` · `memory-curator` · `log-digest` | Multi-step / durable / inspectable flows run as crash-resumable workflows with `Approval` gates. See [Runs IDE](runs-ide.md). |

## Deliberate non-goals

These won't be built, and the reasoning is the point — every "no" is a
place the design chose a limit over a capability.

- **Chad-as-a-product.** This is a single-operator agent against a
  private state repo. "Reproducible by anyone" is covered in
  [Reproducing](reproducing.md), but a hosted multi-tenant version is
  not the design.
- **`github_pr_merge: auto`.** `block` is permanent. A merge is
  irreversible and synthesizes CI signal that humans should gate.
- **`chad_self_modify_identity: auto`.** Identity files (`SOUL.md`,
  `IDENTITY.md`, `USER.md`) are operator-owned. Chad can propose; only
  the operator applies.

The shipped capabilities are what `chad-dev` does today. If a claim
here disagrees with the source, the source wins — please file an issue.

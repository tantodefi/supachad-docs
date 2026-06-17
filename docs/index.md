---
title: Supachad docs
---

# Supachad

<p style="font-size: 1.15rem; color: var(--md-default-fg-color--light); max-width: 38em;">
An always-on agent that runs while you sleep. Sandboxed, budgeted,
earns autonomy gradually. These docs cover the architecture, the
runtime contracts, and the operational surface — what Chad is and
how Chad works.
</p>

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } **New here?**

    ---

    Read [the introduction](intro.md) for the 90-second tour. What
    Chad is, what makes it different from a chat agent, and the three
    properties that drive every architectural decision.

    [:octicons-arrow-right-24: Introduction](intro.md)

-   :material-cube-outline:{ .lg .middle } **Architecture**

    ---

    Three concentric isolation rings, four memory layers, two
    execution substrates. The full design with diagrams.

    [:octicons-arrow-right-24: Overview](architecture.md)

-   :material-account-multiple-outline:{ .lg .middle } **Sub-agents**

    ---

    Seven kinds, each pinned to a binary path under an L7 network
    policy. How spawning works and how to add a new kind.

    [:octicons-arrow-right-24: Orchestrator](orchestrator.md)

-   :material-shield-lock-outline:{ .lg .middle } **Autonomy**

    ---

    Every irreversible action runs through `chad-action-gate`. The
    autonomy boundary is a JSON file you can read.

    [:octicons-arrow-right-24: Autonomy](autonomy.md)

-   :material-database-outline:{ .lg .middle } **Memory**

    ---

    Four stores, four shapes. Always-injected workspace files,
    semantic LTM, named-entity wiki, hybrid vector+graph brain.

    [:octicons-arrow-right-24: Memory stack](memory.md)

-   :material-clock-outline:{ .lg .middle } **Operations**

    ---

    Eleven standing crons. The schedule is the agent's contract with
    the day. Each cron is a budget-guarded one-line wrapper.

    [:octicons-arrow-right-24: Cron schedule](operations.md)

-   :material-flash-outline:{ .lg .middle } **Premium escalation**

    ---

    When Nemotron's depth runs out, Chad escalates to Anthropic
    Claude through a tightly gated wrapper. AuthContext, L7-pinned
    binary identity, weekly spend roll-up.

    [:octicons-arrow-right-24: Premium](premium.md)

-   :material-monitor-dashboard:{ .lg .middle } **Front-ends**

    ---

    Open WebUI as the chat surface. Chad exposed as an OpenAI-compat
    model. Same gateway, same memory, same action gate as a cron.

    [:octicons-arrow-right-24: Front-ends](front-ends.md)

-   :material-sitemap-outline:{ .lg .middle } **Runs IDE**

    ---

    A web IDE for durable Smithers workflows at `runs.supachad.com`.
    Watch, edit, and launch runs with full history, crash-resume, and
    model fusion across the whole NVIDIA catalog.

    [:octicons-arrow-right-24: Runs IDE](runs-ide.md)

-   :material-map-outline:{ .lg .middle } **Roadmap**

    ---

    What's shipped, what's deferred, what's deliberately out of
    scope. Phase 2 follow-ups and the reasoning behind each "no".

    [:octicons-arrow-right-24: Roadmap](roadmap.md)

</div>

## Recent

The full sequence is in [the changelog](changelog.md). The current
state of `chad-dev` is what these docs describe — if a claim here
disagrees with the source, the source wins; please file an issue.

- **Runs IDE at runs.supachad.com.** A web IDE for durable Smithers
  workflows — run history, live tree, `.jsx` editor, model fusion. See
  [Runs IDE](runs-ide.md).
- **Nemotron 3 Ultra 550B + reasoning by default.** Newest NVIDIA
  open model on the hosted profiles; the tool-call harness bug is
  absent in Ultra.
- **Phase C — async GHA spawns.** `chad-spawn --async`,
  reconciler cron, branch retention, opencode kind,
  `--binary-override` flag.
- **NVIDIA fallback in the GHA runner.** codex / opencode auto-route
  to `integrate.api.nvidia.com` when no `OPENAI_API_KEY` is set.
- **GHA substrate landed.** Sub-agents can spawn into a per-job
  GitHub Actions runner — popebot-style branch-as-job-record.
- **Hermes-style memory curator.** Weekly draft-only consolidation
  pass over the LTM. Pre-mutation snapshots make it reversible.

## What this site is not

- Not a NemoClaw user manual — that lives in the [parent project](https://github.com/NVIDIA/NemoClaw)'s
  Sphinx docs. NemoClaw is the *hardened sandbox blueprint* Chad runs
  inside; these docs are *Chad-specific*.
- Not a "run your own Chad" guide — Chad relies on private
  credentials (Proton, Anthropic, NVIDIA) and a private state repo.
  See [Reproducing](reproducing.md) for the honest answer.
- Not branded marketing. The voice is direct and technical because
  the audience is too.

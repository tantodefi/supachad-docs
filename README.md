# supachad-docs

MkDocs Material site for **docs.supachad.com**. Documents Chad's
architecture, runtime contracts, and operational surface — the
source of truth for what's running on `chad-dev`.

## Local preview

```bash
pip install mkdocs-material
mkdocs serve   # http://localhost:8000
```

Or with a containerized build:

```bash
docker run --rm -p 8000:8000 -v "$PWD":/docs squidfunk/mkdocs-material
```

## Deploy

Cloudflare Pages — recommended:

1. CF dashboard → Workers & Pages → Create → connect this repo.
2. Build command: `pip install mkdocs-material && mkdocs build`
3. Build output directory: `site`
4. Custom domain: `docs.supachad.com`

GitHub Action included at `.github/workflows/deploy.yml` does the
build on push to `main`. If you wire it to a Pages project's "Direct
Upload" mode you can skip the dashboard build configuration.

## Content layout

```
docs/
├── index.md              ← landing page (cards, recent ships)
├── intro.md              ← 90-second tour
├── architecture.md       ← three rings, spawn flow, memory layers (with mermaid)
├── memory.md             ← four memory layers + decision tree
├── orchestrator.md       ← seven sub-agent kinds, manifest shape
├── substrates.md         ← local vs gha, provider routing, async mode
├── autonomy.md           ← action gate, policy file, kill switch
├── operations.md         ← nine cron jobs, schedule rationale
├── reproducing.md        ← honest answer about what's needed
├── changelog.md          ← curated from git log
├── _source/              ← optional: synced files from parent repo
├── assets/               ← chad-mark.svg, diagrams
└── stylesheets/extra.css ← visual identity overrides
```

Hand-authored pages (everything except `_source/`) are written for
the public audience and stay under operator control. Synced files
(via `scripts/sync-from-nemoclaw.sh`) are optional reference copies
of source-of-truth docs from `tantodefi/NemoClaw`.

## Sync (optional)

```bash
./scripts/sync-from-nemoclaw.sh                    # uses ../source if present
./scripts/sync-from-nemoclaw.sh --ref chad-dev     # explicit ref
NEMO_SOURCE=~/path/to/NemoClaw ./scripts/sync-from-nemoclaw.sh
```

Each synced file gets an "AUTO-SYNCED" header so readers know the
canonical home and the sync timestamp. Hand-authored pages are not
touched by sync.

## Editing voice

- Direct, technical, opinionated — match the `SOUL.md` voice. No
  warm-up sentences. No "Great question!"
- `code spans` for binaries, paths, env vars, and policy field names.
- Mermaid for sequences and flows. Plain markdown tables for
  matrices.
- Keep page intros to 2-3 sentences before the first heading.

## Visual identity

Tokens live in `docs/stylesheets/extra.css`. Dark navy background,
warm amber primary, cool teal accent. Same palette as the landing
site at `supachad.com`.

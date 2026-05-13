# Deploying the docs + landing sites

Both `supachad-docs` (this site) and `supachad-landing` (the marketing
front page at the root domain) are GitHub-Actions → Cloudflare-Pages
deploys. Same pattern, no servers, ~30 seconds from push to live.

## The lanes

| Source | What deploys | Where |
|---|---|---|
| Push to `main` (either repo) | Production build | `docs.supachad.com` / `supachad.com` |
| Push to any other branch | Preview build | `<branch>.<project>.pages.dev` |
| Open or update a PR | Preview build + URL comment on the PR | same as above |
| Manual `workflow_dispatch` | One-off deploy of the dispatched ref | same as above |

The PR comment is updated in-place on every push to the PR (single comment,
not a wall). The `mkdocs build --strict` step doubles as a PR check — broken
nav, broken anchors, or undeclared assets fail the workflow before anything
reaches Cloudflare.

## Auto-sync from NemoClaw

A scheduled workflow (`sync-from-nemoclaw.yml`) pulls allowlisted source
files from `tantodefi/NemoClaw#chad-dev` into `docs/_source/` daily at
06:17 UTC. If anything changed, it opens or updates a single PR
(`chore/sync-from-nemoclaw`). The PR auto-deploys a preview so you can
inspect the rendered docs before merge.

The allowlist lives in `scripts/sync-from-nemoclaw.sh`. Hand-authored
pages (`intro.md`, `architecture.md`, `changelog.md`, …) are **not**
touched by sync — those stay under operator authorship to keep the public
voice consistent.

To run it manually: GitHub → Actions → `sync-from-nemoclaw` → Run workflow.

## One-time setup

### Cloudflare side

1. Cloudflare dashboard → Workers & Pages → Create project → connect to
   the GitHub repo. Two projects: `supachad-docs` and `supachad-landing`.
2. **Build command** for docs: `pip install mkdocs-material "pymdown-extensions>=10" && mkdocs build --site-dir site` ·
   **output dir**: `site`.
   **Build command** for landing: *(leave empty — pure static)* · **output
   dir**: `/`.
3. **Production branch**: `main` (default).
4. Custom domains:
   - `supachad-docs` → `docs.supachad.com`
   - `supachad-landing` → `supachad.com` (apex) + `www.supachad.com` redirect.
5. Note your Account ID and create an API token scoped to
   *Cloudflare Pages → Edit* (Workers & Pages account permission, all
   accounts / one account, all zones / your zone).

### GitHub secrets

In each repo's Settings → Secrets and variables → Actions, add:

| Secret | Value |
|---|---|
| `CLOUDFLARE_API_TOKEN` | the Pages-scoped token from step 5 above |
| `CLOUDFLARE_ACCOUNT_ID` | your Cloudflare account ID (32-char hex) |

If a secret is missing, the workflow still runs and uploads the built
site as a GitHub Actions artifact (7-day retention) — useful for local
verification before the secrets are in place.

## Daily operation

```bash
# Edit
git checkout -b my-changes
$EDITOR docs/...

# Push — preview deploy fires automatically
git push -u origin my-changes
# (PR comment lands within ~60s with the *.pages.dev URL)

# Open PR via gh
gh pr create --base main

# Click the preview URL, eyeball the change
# Merge → main deploy → docs.supachad.com
gh pr merge --squash --delete-branch
```

## What lives where

```
supachad-docs/
├── docs/                      ← hand-authored pages (this site's content)
├── docs/_source/              ← auto-synced from NemoClaw (banner says so)
├── mkdocs.yml                 ← nav + theme config
├── scripts/sync-from-nemoclaw.sh   ← the allowlist + sync logic
└── .github/workflows/
    ├── deploy.yml                  ← push/PR → CF Pages
    └── sync-from-nemoclaw.yml      ← daily 06:17 UTC sync → PR

supachad-landing/
├── index.html                 ← single-page site, embedded CSS
├── assets/                    ← logo, fonts
└── .github/workflows/deploy.yml    ← push/PR → CF Pages
```

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| CF Pages "deployment failed" with no detail | API token doesn't have Pages: Edit | Re-create the token with the right scope |
| `mkdocs build --strict` fails on PR | Broken internal link or undeclared image | Fix locally with `mkdocs serve --strict` |
| Preview URL 404 right after deploy completes | CF Pages propagation lag (rare, ~30s) | Wait + refresh; or trigger `workflow_dispatch` |
| `docs.supachad.com` resolves but shows old content | Cloudflare cache on the CDN | Purge cache from CF dashboard; default TTL is 1h for HTML |
| Auto-sync PR opened with empty diff | `sync-from-nemoclaw.sh` modified file mtimes only | The "Check for changes" step gates on `git diff` content, so this shouldn't happen — file a bug if it does |
| Preview URL stops working after a few weeks | CF Pages auto-retires deployments older than the latest 5 per branch | Re-trigger the workflow or push another commit |

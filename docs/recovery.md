# Health & recovery

Chad's whole stack — the K3s cluster, the sandbox pod, the gateway, the shim —
runs on one Mac. When that Mac reboots, Chad has to be brought back, and some of
what lives in the sandbox does not survive. `scripts/chad-ops.sh` is the tool for
both questions: *is Chad healthy?* and *how do I bring Chad back?*

The full operator runbook is
[`docs/operations/chad-ops.md`](https://github.com/tantodefi/supachad/blob/main/docs/operations/chad-ops.md)
in the repo. This page is the overview.

## Is Chad healthy?

```bash
bash scripts/chad-ops.sh doctor
```

`doctor` is read-only. It checks the shim and gateway, gbrain (page count and
embedding coverage, not just a health score), binary drift, the operator
allowlist gate, the 10 crons, the Proton wrapper, GitHub CLI auth, skill
registration, the gbrain embed config, inbox noise, and how old the last
`chad-state` backup is.

If the sandbox is unreachable, `doctor` says so once and stops, naming the three
usual causes, instead of printing a column of false passes.

## What survives a restart

| Survives | Lost |
|---|---|
| gbrain brain (usually), identity, workspace | `/usr/local/bin` tools, the cron store, credentials, the gate policy, `gh` auth, the Proton wrapper |

Everything in the "lost" column is either deployed from the repo or restored from
the private `chad-state` backup repo, which the 6-hourly `workspace-backup` cron
keeps current.

## Bringing Chad back

```bash
bash scripts/chad-ops.sh recover
```

`recover` is idempotent; re-run it to finish an interrupted recovery. It syncs
credentials, re-authenticates `gh`, reinstalls the credential wrappers, restores
any missing runtime files (such as the action-gate policy), redeploys every tool
and skill, re-registers the crons, and restarts the gateway and shim.

!!! warning "It will not overwrite a surviving brain"
    The full `chad-state` restore only runs when the brain has zero pages or
    identity is missing. A brain that survived is never replaced by an older
    snapshot. An empty brain is still about 39 MB on disk, so the check counts
    pages, not bytes.

### After a host reboot

Three problems can stop `recover` from reaching the sandbox at all:

1. **Another gateway owns port 8080.** A gateway promoted during a cutover
   attempt can relaunch at login and shadow the cluster's gateway. Unload and
   disable it with `launchctl`.
2. **The CLI certificates no longer match** (`invalid peer certificate:
   BadSignature`): `chad-ops cli-mtls` restores the cluster's own client bundle
   after verifying it.
3. **The SSH handshake secret rotated** with the cluster restart:
   `chad-ops handshake-sync` points the gateway back at the pod's value.

### If the brain came back empty

Every gbrain page is exported to `brain/` in `chad-state`. Import it, run
`chad-ops gbrain-dims` (a fresh brain is created at 1536 dimensions; Chad's
embedder produces 2048), then backfill embeddings. The October 14 recovery
restored 4,076 pages to 100% coverage this way.

## A binary that won't update

OpenShell records the hash of every allowed binary the first time it runs and
denies a changed one. That is a tamper guard, so a rebuilt binary (for example,
`proton-tool`) only takes effect in a freshly started sandbox.

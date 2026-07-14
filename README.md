# xp-tooling — xpprovider fork automation

## Overview

Upjet's no-fork runtime needs the Temporal Cloud provider's Go constructor
in-process, but that constructor lives under `internal/`, which Go forbids other
modules from importing. So this fork adds one tiny exported package,
`xpprovider`, that re-exports the constructor from *inside* the module (where
importing `internal/` is legal) — the same convention Upbound uses for its AWS
provider ([reference](https://github.com/upbound/terraform-provider-aws/blob/e25b40151251/xpprovider/xpprovider.go)).
Our Crossplane provider then consumes it via a one-line `go.mod` `replace`
pointing at a fork tag (`v1.6.0-xp.1`). Nothing else in the upstream provider
changes.

It's low-maintenance by design because the shim is **purely additive** — it adds
one new file and edits zero upstream files, so it can never merge-conflict with a
new release. All the automation lives on this isolated orphan branch
(`xp-tooling`), where a daily GitHub Action watches upstream for new releases
and, for each one, overlays that single file onto the untagged release, runs
`go build` as a drift detector, and publishes a matching `vX.Y.Z-xp.N` tag. In
practice a new upstream release auto-produces a ready-to-consume fork tag with no
human involvement; the only time anyone steps in is the rare case where upstream
changes the constructor's signature, which the build catches loudly.

## How it works

- **`hack/fork-overlay/xpprovider/xpprovider.go`** — the single source of truth
  for the shim. It is *additive*: it adds one package and edits no upstream
  file, so it can never merge-conflict with an upstream release.
- **`hack/sync-xp-fork.sh`** — takes an upstream tag (e.g. `v1.6.0`), fetches it
  into an isolated worktree, drops the overlay on top, runs `go build ./...`
  (the drift detector), then tags `v1.6.0-xp.1` and pushes it.
- **`.github/workflows/sync-xp-fork.yml`** — runs the script daily and on
  demand. This branch is the repo's default branch so the schedule can fire.

This branch deliberately contains **no upstream code**. Upstream releases live
on their tags (`v1.6.0`, …); the produced artifacts live on `*-xp.*` tags.

## Run it locally

```bash
# Validate the build path without touching the remote:
hack/sync-xp-fork.sh v1.6.0 --no-push

# Produce and push the real tag:
hack/sync-xp-fork.sh v1.6.0
```

## Consuming the fork

In the Upjet Crossplane provider's `go.mod`:

```
replace github.com/temporalio/terraform-provider-temporalcloud => \
    github.com/<owner>/terraform-provider-temporalcloud v1.6.0-xp.1
```

The `-xp` base version **must** match the consumer's `TERRAFORM_PROVIDER_VERSION`
so the generated schema and the imported runtime provider agree.

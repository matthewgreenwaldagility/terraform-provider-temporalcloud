# xp-tooling — xpprovider fork automation

This orphan branch is the home of the **automation** that maintains this fork of
[`temporalio/terraform-provider-temporalcloud`](https://github.com/temporalio/terraform-provider-temporalcloud).

The fork exists for exactly one reason: to expose the provider's Terraform
Plugin Framework constructor to Upjet's no-fork runtime via an exported
`xpprovider` package. Upstream keeps that constructor under `internal/`, which
only code in the same module may import — hence a fork that adds one file.

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

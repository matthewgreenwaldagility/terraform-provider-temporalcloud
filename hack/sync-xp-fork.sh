#!/usr/bin/env bash
#
# sync-xp-fork.sh — produce a "-xp" tag that is an unmodified upstream
# terraform-provider-temporalcloud release plus the additive xpprovider overlay.
#
# The overlay (hack/fork-overlay/) never edits an upstream file, so this can
# never merge-conflict. `go build ./...` after applying the overlay is the drift
# detector: it fails iff upstream changed provider.New's signature or moved the
# package — the only things that can break the shim.
#
# Usage:
#   hack/sync-xp-fork.sh [<version>|latest] [--no-push]
#
#   <version>    Upstream tag to base on (e.g. v1.6.0). Default: latest.
#   --no-push    Fetch, overlay and build only; skip commit/tag/push. Use this
#                to validate the path locally without touching the remote.
#
# Environment overrides:
#   UPSTREAM_URL     git URL of the upstream provider (default: temporalio repo)
#   ORIGIN_REMOTE    remote to push the -xp tag to (default: origin)
#   OVERLAY_DIR      overlay source dir (default: <script dir>/fork-overlay)
#   XP_SUFFIX        suffix appended to the version (default: -xp.1)
#
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/temporalio/terraform-provider-temporalcloud.git}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
XP_SUFFIX="${XP_SUFFIX:--xp.1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${OVERLAY_DIR:-$SCRIPT_DIR/fork-overlay}"

VERSION="latest"
PUSH=1
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    -*)        echo "unknown flag: $arg" >&2; exit 2 ;;
    *)         VERSION="$arg" ;;
  esac
done

log() { printf '>> %s\n' "$*"; }

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "overlay dir not found: $OVERLAY_DIR" >&2
  exit 1
fi

# 1. Resolve the target upstream version.
if [[ "$VERSION" == "latest" ]]; then
  # Clean vX.Y.Z tags only: sort -V would otherwise rank v1.7.0-rc1 above v1.7.0.
  VERSION="$(git ls-remote --tags --refs "$UPSTREAM_URL" 'v*' \
    | awk -F/ '{print $NF}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
  [[ -n "$VERSION" ]] || { echo "could not resolve latest upstream tag" >&2; exit 1; }
fi
XP_TAG="${VERSION}${XP_SUFFIX}"
log "upstream version : $VERSION"
log "xp tag           : $XP_TAG"

# 2. Idempotency: nothing to do if the -xp tag already exists on origin.
if git ls-remote --tags --refs "$ORIGIN_REMOTE" "refs/tags/${XP_TAG}" | grep -q .; then
  log "tag ${XP_TAG} already present on ${ORIGIN_REMOTE}; up to date."
  exit 0
fi

# 3. Fetch the upstream tag into a private ref (never clobbers user's tags).
UPSTREAM_REF="refs/xp-upstream/${VERSION}"
log "fetching ${VERSION} from ${UPSTREAM_URL}"
git fetch --no-tags "$UPSTREAM_URL" "+refs/tags/${VERSION}:${UPSTREAM_REF}"
UPSTREAM_SHA="$(git rev-parse "${UPSTREAM_REF}^{commit}")"
log "upstream ${VERSION} = ${UPSTREAM_SHA}"

# 4. Build the tag in an isolated worktree so the caller's checkout is untouched.
WORKTREE="$(mktemp -d)/xp-${VERSION}"
cleanup() { git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git worktree add --detach "$WORKTREE" "$UPSTREAM_SHA" >/dev/null

# 5. Apply the additive overlay.
log "applying overlay from ${OVERLAY_DIR}"
cp -R "$OVERLAY_DIR/." "$WORKTREE/"

# 6. Drift detector: this must compile against the real upstream tree.
log "go build ./... (drift detector)"
( cd "$WORKTREE" && go build ./... )
log "build OK"

if [[ "$PUSH" -eq 0 ]]; then
  log "[--no-push] validated ${XP_TAG}; skipping commit/tag/push."
  exit 0
fi

# 7. Commit the overlay, tag, and push the tag to origin.
( cd "$WORKTREE"
  git checkout -b "xp/${VERSION}" >/dev/null
  git add -A
  git -c user.name="${GIT_AUTHOR_NAME:-xp-fork-bot}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-xp-fork-bot@users.noreply.github.com}" \
      commit -m "Add xpprovider overlay for ${VERSION}" >/dev/null
  git tag -a "${XP_TAG}" -m "xpprovider shim over upstream ${VERSION}"
  git push "$ORIGIN_REMOTE" "refs/tags/${XP_TAG}"
)
log "pushed ${XP_TAG} to ${ORIGIN_REMOTE}"

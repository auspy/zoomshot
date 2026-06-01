#!/bin/bash
# Release ZoomShot: preflight → build → notarize → tag → upload to GitHub.
#
# Usage:
#   ./release.sh v0.2.0
#   ./release.sh v0.2.0 --notes-file CHANGELOG.md
#   ./release.sh v0.2.0 --notes "What's new in this release"
#
# Idempotent-ish: if the tag already exists it'll skip tag/push and just
# upload (or replace) the asset on the existing GitHub release.

set -euo pipefail

cd "$(dirname "$0")"

# --- Args -------------------------------------------------------------------

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version-tag> [--notes \"...\"] [--notes-file PATH]" >&2
    echo "Example: $0 v0.2.0" >&2
    exit 2
fi

TAG="$1"; shift
NOTES=""
NOTES_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --notes)       NOTES="$2"; shift 2 ;;
        --notes-file)  NOTES_FILE="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "Tag '$TAG' doesn't look like vMAJOR.MINOR.PATCH (e.g. v0.2.0)." >&2
    exit 2
fi

# --- Config -----------------------------------------------------------------

TEAM_ID="ZH7HN3N93K"
NOTARY_PROFILE="${ZOOMSHOT_NOTARY_PROFILE:-ZoomShot}"
APP_BUNDLE="ZoomShot.app"
ZIP_PATH="ZoomShot.zip"

fail()  { echo "✗ $*" >&2; exit 1; }
ok()    { echo "✓ $*"; }
step()  { echo; echo "==> $*"; }

# --- Preflight --------------------------------------------------------------

step "Preflight"

command -v swift     >/dev/null || fail "swift not in PATH"
command -v codesign  >/dev/null || fail "codesign not in PATH"
command -v xcrun     >/dev/null || fail "xcrun not in PATH"
command -v gh        >/dev/null || fail "gh (GitHub CLI) not in PATH"
command -v git       >/dev/null || fail "git not in PATH"
ok "All required tools present"

# Inside a git repo?
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "Not inside a git repository"

# build.sh / notarize.sh present and executable?
[ -x ./build.sh ]    || fail "./build.sh missing or not executable"
[ -x ./notarize.sh ] || fail "./notarize.sh missing or not executable"
ok "build.sh and notarize.sh present"

# Developer ID cert installed?
if ! security find-identity -v -p codesigning 2>/dev/null \
        | grep -q "Developer ID Application: .*($TEAM_ID)"; then
    fail "No 'Developer ID Application' cert for team $TEAM_ID found in login keychain"
fi
ok "Developer ID cert for team $TEAM_ID installed"

# Notarytool keychain profile exists?
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "Notarytool profile '$NOTARY_PROFILE' missing. Create with: \
xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <email> --team-id $TEAM_ID --password <app-specific>"
fi
ok "Notarytool profile '$NOTARY_PROFILE' is usable"

# gh authenticated?
gh auth status >/dev/null 2>&1 || fail "gh not authenticated. Run: gh auth login"
ok "GitHub CLI authenticated"

# Clean working tree?
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree has uncommitted changes:"
    git status --short
    echo
    fail "Commit or stash before releasing."
fi
ok "Working tree is clean"

# Current branch tracking a remote?
BRANCH="$(git symbolic-ref --short HEAD)"
git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1 \
    || fail "Current branch '$BRANCH' has no upstream"

# In sync with remote?
git fetch --quiet origin "$BRANCH"
LOCAL="$(git rev-parse @)"
REMOTE="$(git rev-parse "@{u}")"
[ "$LOCAL" = "$REMOTE" ] || fail "Local '$BRANCH' is not in sync with origin. Pull/push first."
ok "Local '$BRANCH' is in sync with origin"

# Tag handling
TAG_EXISTS_LOCAL=false
TAG_EXISTS_REMOTE=false
if git rev-parse "$TAG" >/dev/null 2>&1; then TAG_EXISTS_LOCAL=true; fi
if git ls-remote --tags --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
    TAG_EXISTS_REMOTE=true
fi
if $TAG_EXISTS_LOCAL || $TAG_EXISTS_REMOTE; then
    echo "ℹ Tag $TAG already exists (local=$TAG_EXISTS_LOCAL, remote=$TAG_EXISTS_REMOTE) — will reuse"
else
    ok "Tag $TAG is fresh"
fi

# --- Build ------------------------------------------------------------------

step "Build (Developer ID signed)"
./build.sh release

# --- Notarize ---------------------------------------------------------------

step "Notarize + staple"
ZOOMSHOT_NOTARY_PROFILE="$NOTARY_PROFILE" ./notarize.sh

# Final stapled validation
xcrun stapler validate "$APP_BUNDLE" >/dev/null \
    || fail "Stapled ticket failed to validate"
spctl --assess --type execute "$APP_BUNDLE" >/dev/null \
    || fail "spctl rejected the bundle after notarization"
ok "Stapled and Gatekeeper-accepted"

# --- Tag + push -------------------------------------------------------------

step "Git tag $TAG"
if ! $TAG_EXISTS_LOCAL; then
    git tag -a "$TAG" -m "ZoomShot $TAG"
    ok "Created local tag $TAG"
fi
if ! $TAG_EXISTS_REMOTE; then
    git push origin "$TAG"
    ok "Pushed tag $TAG to origin"
fi

# --- GitHub release ---------------------------------------------------------

step "GitHub release"
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "ℹ Release $TAG exists — uploading asset with --clobber"
    gh release upload "$TAG" "$ZIP_PATH" --clobber
else
    CREATE_ARGS=(--title "ZoomShot $TAG")
    if [ -n "$NOTES_FILE" ]; then
        [ -f "$NOTES_FILE" ] || fail "Notes file '$NOTES_FILE' not found"
        CREATE_ARGS+=(--notes-file "$NOTES_FILE")
    elif [ -n "$NOTES" ]; then
        CREATE_ARGS+=(--notes "$NOTES")
    else
        CREATE_ARGS+=(--generate-notes)
    fi
    gh release create "$TAG" "$ZIP_PATH" "${CREATE_ARGS[@]}"
fi

URL="$(gh release view "$TAG" --json url --jq .url)"
ok "Release ready: $URL"

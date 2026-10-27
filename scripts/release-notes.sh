#!/usr/bin/env bash
# Prints the notes for a GitHub release: how to install, then every user-facing change since the
# previous release, under New (feat:), Fixes (fix:) and Improvements (anything else, e.g. perf:).
# Housekeeping commits (chore/ci/docs/test, version bumps) are left out; empty sections aren't shown.
# Usage: scripts/release-notes.sh [REV]   (default HEAD; the previous release is the tag before it)
set -euo pipefail
cd "$(dirname "$0")/.."
rev="${1:-HEAD}"
previous=$(git describe --tags --abbrev=0 "$rev^" 2>/dev/null || true)

cat <<'NOTES'
## Install
Get ByteCache for iPhone, iPad and Mac from the **[TestFlight beta](https://testflight.apple.com/join/rpmeVJW6)**: open the link on your device and follow the steps.

Requires iOS / iPadOS 18 or macOS 15 or later, and a [ByteStash](https://github.com/jordan-dalby/ByteStash) server (or the public demo).
NOTES

# Features land on develop, so pull-request-based notes would miss them: read the commit log.
changes=$(git log --no-merges --format='%s' ${previous:+$previous..}"$rev" \
  | grep -vE '^(chore|ci|docs|test)(\(|!|:)' \
  | grep -vE '^Release [0-9]' || true)

# "fix(mac): Select mode…" → "- Select mode…"; capitalise only an all-lowercase first word (keeps iPhone, macOS).
tidy() { perl -pe 's/^[a-z]+(\([^)]*\))?!?: //; s/^([a-z])(?=[a-z]*(?:[^A-Za-z]|$))/\u$1/; s/^/- /'; }

section() {
  local title=$1 lines=$2
  [ -n "$lines" ] || return 0
  printf '\n## %s\n%s\n' "$title" "$(printf '%s\n' "$lines" | tidy)"
}

kind() { printf '%s\n' "$changes" | grep -E "^$1(\(|!|:)" || true; }
section "New" "$(kind feat)"
section "Fixes" "$(kind fix)"
section "Improvements" "$(printf '%s\n' "$changes" | grep -vE '^(feat|fix)(\(|!|:)' | grep -v '^$' || true)"

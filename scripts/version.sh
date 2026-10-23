#!/usr/bin/env bash
# Prints the app version from project.yml (the single source of truth); with --build, the build number.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--build" ]; then
    sed -n -E 's/^ *CURRENT_PROJECT_VERSION: "([^"]+)".*/\1/p' project.yml | head -1
else
    sed -n -E 's/^ *MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml | head -1
fi

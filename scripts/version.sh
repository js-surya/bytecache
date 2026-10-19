#!/usr/bin/env bash
# Prints the app version from project.yml (the single source of truth).
set -euo pipefail
cd "$(dirname "$0")/.."
sed -n -E 's/^ *MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml | head -1

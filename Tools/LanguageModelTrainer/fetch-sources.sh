#!/usr/bin/env bash
# Shallow-clones every repo in sources.json (plus Linguist samples) into .data/, then writes
# sources.lock.json with the exact commit used for each. Re-running skips repos already cloned.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .data/repos

if [ ! -d .data/linguist ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/github-linguist/linguist .data/linguist
  git -C .data/linguist sparse-checkout set samples
fi

/usr/bin/python3 -I - <<'PY'
import json, subprocess, pathlib
root = pathlib.Path(".data/repos")
sources = json.load(open("sources.json"))["repos"]
lock = []
def head(path): return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
for s in sources:
    dest = root / s["repo"].replace("/", "__")
    if not dest.exists():
        print("clone", s["repo"], flush=True)
        r = subprocess.run(["git", "clone", "-q", "--depth", "1", f"https://github.com/{s['repo']}", str(dest)])
        if r.returncode != 0:
            print("  FAILED", s["repo"]); continue
    lock.append({**s, "commit": head(dest)})
lock.append({"repo": "github-linguist/linguist (samples/)", "license": "MIT", "commit": head(".data/linguist")})
json.dump(lock, open("sources.lock.json", "w"), indent=1)
print("locked", len(lock))
PY

#!/usr/bin/env bash
# Run once on your machine (requires git): creates repo and initial commit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if ! command -v git >/dev/null 2>&1; then
    echo "Install git first, e.g.: sudo apt install -y git" >&2
    exit 1
fi
if [[ -d .git ]]; then
    echo "Already a git repo (.git exists). Abort." >&2
    exit 1
fi
git init -b main
git add -A
git status
git commit -m "Initial public release: nvidia-340 on Ubuntu 24.04"
echo "OK. Public push: see POST_PUBLISH.md (requires explicit consent)."

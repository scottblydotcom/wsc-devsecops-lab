#!/usr/bin/env bash
# LAB STEP 3, backup plan: turns on the security gates for you and saves the
# change. Use it if editing the workflow file by hand gave you trouble.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(git rev-parse --show-toplevel)"

workflow=".github/workflows/security-gates.yml"
[ "$(git branch --show-current)" != "main" ] ||
  die "You are on main. Do LAB STEP 2 first, so you have a branch with a pull request."

git fetch --quiet origin main
git show "origin/main:$workflow" > "$workflow"   # start again from the original file
sed -i.bak 's/^  # pull_request:/  pull_request:/' "$workflow" && rm -f "$workflow.bak"
grep -q '^  pull_request:' "$workflow" || die "Could not turn on the gates. Ask a facilitator."

exec bash "$(dirname "$0")/save-my-change.sh"

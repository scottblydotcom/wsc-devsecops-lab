#!/usr/bin/env bash
# LAB STEP 3, backup plan: turns on the security gates for you and saves the
# change. Use it if editing the workflow file by hand gave you trouble.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$here/lib.sh"
cd "$(git rev-parse --show-toplevel)"
fetch_origin

workflow=".github/workflows/security-gates.yml"
git checkout --quiet -- "$workflow" 2>/dev/null || true   # drop any half-done edit; we rewrite it below
if [ "$(git branch --show-current)" = "main" ]; then
  pr_branch="$(existing_pr_branch)"
  [ -n "$pr_branch" ] || die "Do LAB step 2 first, so you have a pull request for the gates to check."
  git switch --quiet "$pr_branch" || die "Could not switch to your '$pr_branch' branch. Raise your hand."
  say "Switched to your '$pr_branch' branch, where your pull request is."
fi
[ -n "$(git branch --show-current)" ] || die "You're not on a branch. Run: bash scripts/use-example-change.sh"
catch_up   # so "already on" below reflects what GitHub has

git show "origin/main:$workflow" > "$workflow"   # start again from the original file
sed -i.bak 's/^  # pull_request:/  pull_request:/' "$workflow" && rm -f "$workflow.bak"
grep -q '^  pull_request:' "$workflow" || die "Could not turn on the gates. Raise your hand."

if [ -z "$(git status --porcelain -- "$workflow")" ]; then
  say "The gates were already on in your branch."
  push_if_needed
  print_pr_link "$(git branch --show-current)"
  exit 0
fi
exec bash "$here/save-my-change.sh"

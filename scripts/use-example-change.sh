#!/usr/bin/env bash
# LAB STEP 2, option B: use the pre-recorded AI agent change.
#
# AI output is different every time, and not everyone has an agent, so this
# applies a recorded example of an agent's change for the request in LAB.md.
# It puts the change on a new branch and pushes it, ready for a pull request.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$here/lib.sh"
cd "$(git rev-parse --show-toplevel)"

branch="agent-change"
example_branch="agent-output-example"
# Pinned like the actions in our workflows: the Git blob id of each file the
# example may change. Anything else that arrives is refused.
pinned_files="app.py:e2ba78b14e7a2d78c3a64be1929287c9f251dd7e
db.py:62d3df4a1452cb3adb03eeb0f37fa84adb8b5449
tests/test_profile.py:387014e4b3ea7d2437bf0cc35e461963365fe1fe"

fetch_origin
ref=""
if git show-ref --verify --quiet "refs/heads/$branch"; then
  ref="refs/heads/$branch"
elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  ref="refs/remotes/origin/$branch"
fi
# Already done (maybe in an earlier codespace)? Go back to that branch.
if [ -n "$ref" ] && [ -n "$(git rev-list "origin/main..$ref")" ]; then
  if [ "$(git branch --show-current)" != "$branch" ]; then
    [ -z "$(git status --porcelain)" ] || set_aside "set aside by use-example-change.sh"
    git switch --quiet "$branch" ||
      die "You already did this step, but could not switch to '$branch'. Raise your hand."
  fi
  say "You already did this step. You're on your '$branch' branch."
  push_if_needed
  print_pr_link "$branch"
  exit 0
fi

# Switching from your own agent (Option A)? Set its unsaved work aside.
[ -z "$(git status --porcelain)" ] || set_aside "my agent attempt (set aside by use-example-change.sh)"

say "Downloading the example agent change..."
# GIT_TERMINAL_PROMPT=0: fail fast instead of waiting for a password prompt.
if GIT_TERMINAL_PROMPT=0 git fetch --quiet "$TEMPLATE_REPO" "$example_branch" 2>/dev/null ||
   git fetch --quiet origin "$example_branch" 2>/dev/null; then
  example="$(git rev-parse FETCH_HEAD)"
else
  die "Could not download the example. Check your internet connection and run this again."
fi
for pin in $pinned_files; do
  [ "$(git rev-parse --quiet --verify "$example:${pin%%:*}" || true)" = "${pin#*:}" ] ||
    die "The example download doesn't match the tested version of ${pin%%:*}. Raise your hand."
done

# A branch left by an earlier run that stopped early (or one already merged):
# start it again from main.
if [ -n "$ref" ]; then
  git switch --quiet --detach origin/main
  git branch --quiet -D "$branch" 2>/dev/null || true
fi
git switch --quiet --no-track --create "$branch" origin/main
for pin in $pinned_files; do
  git checkout "$example" -- "${pin%%:*}"
done

if git diff --cached --quiet; then
  say "The example change is already on main (someone merged it). You're on '$branch': go on to step 3. After you turn on the gates, the script prints your pull request link."
  push_if_needed
  exit 0
fi
git commit --quiet \
  -m "Add endpoint to get a user's profile by ID" \
  -m "Example AI agent change for the WSC DevSecOps lab (request in LAB.md, step 2)."

say "The agent changed these files:"
git show --stat --format= HEAD
push_if_needed
print_pr_link "$branch"

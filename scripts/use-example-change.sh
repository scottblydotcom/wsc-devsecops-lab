#!/usr/bin/env bash
# LAB STEP 2, option B: use the pre-recorded AI agent change.
#
# AI output is different every time, and not everyone has an agent, so this
# applies a recorded example of an agent's change for the request in LAB.md.
# It puts the change on a new branch and pushes it, ready for a pull request.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
cd "$(git rev-parse --show-toplevel)"

branch="agent-change"
example_branch="agent-output-example"

git fetch --quiet origin
# Already done (maybe in an earlier codespace)? Go back to that branch.
if git show-ref --verify --quiet "refs/heads/$branch" ||
   git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  if [ "$(git branch --show-current)" != "$branch" ]; then
    git switch --quiet "$branch" ||
      die "You already did this step, but could not switch to '$branch'. Ask a facilitator for help."
  fi
  say "You already did this step. You're on your '$branch' branch."
  print_pr_link "$branch"
  exit 0
fi
[ -z "$(git status --porcelain)" ] ||
  die "Some files have changes that are not saved to git yet. Ask a facilitator for help."

say "Downloading the example agent change..."
if git fetch --quiet "$TEMPLATE_REPO" "$example_branch" 2>/dev/null ||
   git fetch --quiet origin "$example_branch" 2>/dev/null; then
  example="$(git rev-parse FETCH_HEAD)"
else
  die "Could not download the example. Check your internet connection and run this again."
fi

# Which files did the agent touch? Compare the example with the commit it was
# built on when we have it; otherwise compare it with your main branch.
if git rev-parse --quiet --verify "$example~1" >/dev/null; then
  before="$example~1"
else
  before="origin/main"
fi

git switch --quiet --create "$branch" origin/main
git diff --name-only --diff-filter=AM "$before" "$example" | while IFS= read -r file; do
  git checkout "$example" -- "$file"
done
git diff --name-only --diff-filter=D "$before" "$example" | while IFS= read -r file; do
  git rm --quiet -- "$file"
done
git commit --quiet \
  -m "Add endpoint to get a user's profile by ID" \
  -m "Example AI agent change for the WSC DevSecOps lab (request in LAB.md, step 2)."

say "The agent changed these files:"
git show --stat --format= HEAD

say "Sending your branch to GitHub..."
git push --quiet --set-upstream origin "$branch"
print_pr_link "$branch"

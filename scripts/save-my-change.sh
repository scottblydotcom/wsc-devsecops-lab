#!/usr/bin/env bash
# Saves every file you (or your AI agent) changed and sends it to GitHub.
#   LAB STEP 2, option A: after your agent finishes its change.
#   LAB STEP 3: after you turn on the security gates.
# Changes never go straight to main; they go on a branch, for a pull request.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
cd "$(git rev-parse --show-toplevel)"

[ -n "$(git status --porcelain)" ] ||
  die "Nothing to save: no files have changed. Did your agent finish? Is the file saved?"

branch="$(git branch --show-current)"
if [ "$branch" = "main" ] || [ -z "$branch" ]; then
  branch="my-agent-change"
  git fetch --quiet origin
  if git show-ref --verify --quiet "refs/heads/$branch" ||
     git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    die "You already have a '$branch' branch. Ask a facilitator for help."
  fi
  git switch --quiet --create "$branch"
fi

changes="$(git status --porcelain)"
if grep -q 'security-gates.yml' <<<"$changes"; then
  message="Turn on the security gates"
else
  message="Add endpoint to get a user's profile by ID (written by my AI agent)"
fi

git add --all
git commit --quiet -m "$message"
say "Saved on branch '$branch':"
git show --stat --format='  %s' HEAD

say "Sending your branch to GitHub..."
git push --quiet --set-upstream origin "$branch"
print_pr_link "$branch"

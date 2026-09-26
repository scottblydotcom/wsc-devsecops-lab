#!/usr/bin/env bash
# Saves every file you (or your AI agent) changed and sends it to GitHub.
#   LAB STEP 2, option A: after your agent finishes its change.
#   LAB STEP 3: after you turn on the security gates.
# Changes never go straight to main; they go on a branch, for a pull request.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$here/lib.sh"
cd "$(git rev-parse --show-toplevel)"
fetch_origin

changes="$(git status --porcelain)"
branch="$(git branch --show-current)"

if [ "$branch" = "main" ] || [ -z "$branch" ]; then
  # Everything that differs from GitHub's main, saved to git or not.
  touched="$(git diff --name-only origin/main --)"
  pr_branch="$(existing_pr_branch)"
  if grep -q 'security-gates.yml' <<<"$changes$touched"; then
    # Step 3 in a fresh codespace: the gates belong on your step 2 branch.
    [ -n "$pr_branch" ] ||
      die "Do LAB step 2 first, so you have a pull request for the gates to check."
    # Anything committed on main by mistake becomes unsaved edits again, so it
    # moves to your branch with you. Nothing is lost.
    before="$(git rev-parse HEAD)"
    [ -z "$(git rev-list origin/main..HEAD)" ] || git reset --quiet origin/main
    if ! git switch --quiet "$pr_branch"; then
      git reset --quiet "$before"   # put main back exactly as it was
      die "Could not switch to your '$pr_branch' branch. Raise your hand."
    fi
    branch="$pr_branch"
    changes="$(git status --porcelain)"
    say "Switched to your '$branch' branch, where your pull request is."
  elif [ -n "$changes" ] || [ -n "$(git rev-list origin/main..HEAD)" ]; then
    # Step 2, option A: your agent's work goes on its own branch. If you already
    # have a lab branch, this codespace is on main by mistake: don't guess.
    [ -z "$pr_branch" ] ||
      die "You already have your '$pr_branch' branch from step 2, and this codespace is on main. Turning on the gates? Edit security-gates.yml first, then run this again. Want to try your own agent as well? Raise your hand."
    branch="my-agent-change"
    git switch --quiet --create "$branch"
    # If anything was committed on main by mistake, it moved to the branch; reset main.
    git branch --quiet --force main origin/main
  fi
fi
[ -n "$branch" ] || die "You're not on a branch. Run: bash scripts/use-example-change.sh"
if [ "$branch" != "main" ]; then
  catch_up
  changes="$(git status --porcelain)"
  if [ -z "$changes" ] && [ "$CAUGHT_UP" = 1 ] &&
     [ -z "$(git rev-list "origin/$branch..HEAD")" ]; then
    say "Your branch now matches GitHub. Nothing else to save."
    print_pr_link "$branch"
    exit 0
  fi
fi

if [ -n "$changes" ]; then
  if grep -q 'security-gates.yml' <<<"$changes"; then
    message="Turn on the security gates"
  else
    message="Add endpoint to get a user's profile by ID (written by my AI agent)"
  fi
  git add --all
  count="$(git diff --cached --name-only | wc -l | tr -d ' ')"
  if [ "$count" -gt 50 ]; then
    git reset --quiet
    die "That's $count files, which is too many. Your agent probably created a folder of tools (like venv/). Raise your hand."
  fi
  git commit --quiet -m "$message"
  say "Saved on branch '$branch':"
  git show --stat --format='  %s' HEAD
elif [ "$branch" = "main" ] || {
       git show-ref --verify --quiet "refs/remotes/origin/$branch" &&
       [ -z "$(git rev-list "origin/$branch..HEAD")" ]
     }; then
  die "Nothing new to save: no files changed since your last save. (Turning on the gates? Make the one-line edit first, or run: bash scripts/turn-on-gates.sh)"
fi

push_if_needed
print_pr_link "$branch"

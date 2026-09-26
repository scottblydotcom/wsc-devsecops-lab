# shellcheck shell=bash disable=SC2034
# Shared helpers for the lab scripts. Not meant to be run on its own.

# Where the pre-recorded agent change lives: the public template repository.
TEMPLATE_REPO="${LAB_TEMPLATE_REPO:-https://github.com/scottblydotcom/wsc-devsecops-lab.git}"
# The branch names the lab uses for pull requests (Option B, then Option A).
PR_BRANCHES="agent-change my-agent-change"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mStopped: %s\033[0m\n\n' "$*" >&2; exit 1; }

# Refresh what we know about GitHub, forgetting branches deleted there.
fetch_origin() {
  git fetch --prune --quiet origin ||
    die "Could not reach GitHub. Check your internet connection and run this again."
}

# owner/repo of *your* copy, for building links.
my_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
  else
    git remote get-url origin | sed -E 's#^.*github\.com[^:/]*[:/]##; s#\.git$##'
  fi
}

# The lab branch you made in step 2. If you made both (switched from Option A
# to B), the one you worked on most recently.
existing_pr_branch() {
  local b ref
  for b in $PR_BRANCHES; do
    for ref in "refs/heads/$b" "refs/remotes/origin/$b"; do
      if git show-ref --verify --quiet "$ref"; then git log -1 --format="%ct $b" "$ref"; fi
    done
  done | sort -rn | head -1 | cut -d' ' -f2
}

# Set unsaved work aside (git stash) and say how to get it back.
set_aside() {
  local from
  from="$(git branch --show-current)"
  git stash push --quiet --include-untracked -m "$1"
  say "Your unsaved changes were set aside, not deleted. (To get them back: git switch ${from:-main}, then git stash pop)"
}

# If GitHub's copy of this branch moved on (another codespace, or an edit on
# github.com), catch up when that's safe. Never leaves a half-finished merge.
# Sets CAUGHT_UP=1 when it moved the branch forward.
CAUGHT_UP=0
catch_up() {
  local branch stash_before stash_after
  branch="$(git branch --show-current)"
  [ -n "$branch" ] || return 0
  git show-ref --verify --quiet "refs/remotes/origin/$branch" || return 0
  if git merge-base --is-ancestor "origin/$branch" HEAD; then
    return 0   # up to date, or only ahead
  fi
  if git merge-base --is-ancestor HEAD "origin/$branch"; then
    if ! git merge --quiet --ff-only "origin/$branch" >/dev/null 2>&1; then
      # Unsaved edits are in the way. Set them aside, catch up, put them back.
      # An edit identical to GitHub's (the same gate line) simply disappears.
      [ -n "$(git status --porcelain)" ] || die "Could not catch up with GitHub on '$branch'. Raise your hand."
      stash_before="$(git rev-parse --quiet --verify refs/stash || true)"
      git stash push --quiet --include-untracked -m "catch-up (set aside by the lab scripts)"
      stash_after="$(git rev-parse --quiet --verify refs/stash || true)"
      [ "$stash_after" != "$stash_before" ] || die "Could not catch up with GitHub on '$branch'. Raise your hand."
      git merge --quiet --ff-only "origin/$branch" >/dev/null 2>&1 ||
        die "Could not catch up with GitHub on '$branch'. Your changes are saved (git stash list). Raise your hand."
      if ! git stash pop --quiet >/dev/null 2>&1; then
        git reset --quiet --hard
        die "GitHub has newer changes on '$branch' that clash with your changes here. Your changes are saved (git stash list). Raise your hand."
      fi
    fi
    CAUGHT_UP=1
    say "Caught up with GitHub (a change made on github.com or in another codespace)."
    return 0
  fi
  die "Your branch on GitHub has a change this codespace doesn't have (an edit on github.com, or another codespace). Check your pull request; if you need more, raise your hand."
}

# Push the current branch if GitHub doesn't have all of it yet.
push_if_needed() {
  local branch
  branch="$(git branch --show-current)"
  [ -n "$branch" ] || die "You're not on a branch. Run: bash scripts/use-example-change.sh"
  catch_up
  if git show-ref --verify --quiet "refs/remotes/origin/$branch" &&
     [ -z "$(git rev-list "origin/$branch..HEAD")" ]; then
    return 0
  fi
  say "Sending your branch to GitHub..."
  git push --quiet --set-upstream origin "$branch" ||
    die "GitHub didn't accept the push. Run this same command again. If it fails twice, raise your hand."
}

print_pr_link() {
  local branch="$1"
  say "Next: open your pull request here (Ctrl+click, or Cmd+click on a Mac):"
  printf '\n    https://github.com/%s/compare/main...%s?expand=1\n\n' "$(my_repo)" "$branch"
  printf 'Already have a pull request open for this branch? Then you are done: it updates by itself.\n'
  printf "(Don't merge it. The lab keeps using it.)\n\n"
}

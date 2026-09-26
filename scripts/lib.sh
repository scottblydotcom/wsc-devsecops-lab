# shellcheck shell=bash disable=SC2034
# Shared helpers for the lab scripts. Not meant to be run on its own.

# Where the pre-recorded agent change lives: the public template repository.
TEMPLATE_REPO="${LAB_TEMPLATE_REPO:-https://github.com/scottblydotcom/wsc-devsecops-lab.git}"
# The branch names the lab uses for pull requests (Option B, then Option A).
PR_BRANCHES="agent-change my-agent-change"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mStopped: %s\033[0m\n\n' "$*" >&2; exit 1; }

# owner/repo of *your* copy, for building links.
my_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
  else
    git remote get-url origin | sed -E 's#^.*github\.com[^:/]*[:/]##; s#\.git$##'
  fi
}

branch_exists() {  # locally, or on GitHub
  git show-ref --verify --quiet "refs/heads/$1" ||
    git show-ref --verify --quiet "refs/remotes/origin/$1"
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

# Push the current branch if GitHub doesn't have all of it yet.
push_if_needed() {
  local branch
  branch="$(git branch --show-current)"
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

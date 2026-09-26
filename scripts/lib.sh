# Shared helpers for the lab scripts. Not meant to be run on its own.

# Where the pre-recorded agent change lives: the public template repository.
TEMPLATE_REPO="${LAB_TEMPLATE_REPO:-https://github.com/scottblydotcom/wsc-devsecops-lab.git}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mStopped: %s\033[0m\n\n' "$*" >&2; exit 1; }

# owner/repo of *your* copy, for building links.
my_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
  else
    git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##'
  fi
}

print_pr_link() {
  local branch="$1"
  say "Next: open your pull request here (Ctrl+click or Cmd+click the link):"
  printf '\n    https://github.com/%s/compare/main...%s?expand=1\n\n' "$(my_repo)" "$branch"
  printf 'Already opened one for this branch? Then you are done: it updates by itself.\n\n'
}

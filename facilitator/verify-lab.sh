#!/usr/bin/env bash
# "check && pass || fail" is safe here: pass() cannot fail.
# shellcheck disable=SC2015
# Self-check for the lab. Run it from the repository before publishing, and
# again the day before the workshop:
#
#     bash facilitator/verify-lab.sh
#
# Without touching GitHub, it checks that every branch behaves the way the lab
# needs: lint and tests pass, each security gate finds exactly what it should
# (using the same scanner versions and the same report script as the
# workflow), the planted bugs really are exploitable (or fixed), and the
# attendee helper scripts work in a copy that has no shared history with this
# repository, as a "Use this template" copy doesn't, including the ways
# attendees go off script (fresh codespaces, failed pushes, merging early).
#
# Needs: git, docker, gitleaks (the version pinned in security-gates.yml), and
# uv or python3. Semgrep runs in Docker, from the image pinned in the workflow.
set -uo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo" || exit 1
# Keep scratch files inside the repo: Docker on macOS (Colima) only sees $HOME.
work="$repo/.git/lab-verify"
rm -rf "$work" && mkdir -p "$work"

failures=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; failures=$((failures + 1)); }
# expect NAME WANT GOT: pass when GOT equals WANT.
expect() {
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1 (wanted: $2, got: $3)"; fi
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

workflow=".github/workflows/security-gates.yml"
gitleaks_version="$(sed -n 's/.*GITLEAKS_VERSION: "\(.*\)".*/\1/p' "$workflow")"
semgrep_image="$(sed -n 's/.*SEMGREP_IMAGE: "\(.*\)".*/\1/p' "$workflow")"
branches="main agent-output-example agent-output-after-gates reference-solution"

section "Tools"
command -v gitleaks >/dev/null || { echo "Install gitleaks $gitleaks_version first."; exit 1; }
expect "gitleaks version matches the workflow" "$gitleaks_version" "$(gitleaks version)"
docker info >/dev/null 2>&1 || { echo "Start Docker first."; exit 1; }
pass "docker is running"
if command -v uv >/dev/null; then
  uv venv -q --python 3.12 "$work/venv" &&
    VIRTUAL_ENV="$work/venv" uv pip install -q -r requirements-dev.txt pyyaml
else
  python3 -m venv "$work/venv" &&
    "$work/venv/bin/pip" install -q -r requirements-dev.txt pyyaml
fi
py="$work/venv/bin/python"
[ -x "$py" ] && pass "python venv: $("$py" --version)" || { fail "python venv"; exit 1; }
grep -q -- '--disable-nosem' "$workflow" && pass "workflow ignores # nosemgrep" || fail "workflow ignores # nosemgrep"
grep -q -- '--ignore-gitleaks-allow' "$workflow" && pass "workflow ignores gitleaks:allow comments" ||
  fail "workflow ignores gitleaks:allow comments"
grep -q -- 'rm -f .gitleaksignore' "$workflow" && pass "workflow deletes .gitleaksignore before scanning" ||
  fail "workflow deletes .gitleaksignore before scanning"

# gate TOOL DIR [LOG_OPTS]: run one security gate the way the workflow does and
# print "EXIT RULES" (report_findings.py exit status, sorted unique rule ids).
gate() {
  local tool="$1" dir="$2" log_opts="${3:-HEAD}" status=0
  rm -f "$work/gl.json" "$work/gl.log" "$work/sg.json" "$work/sg.log"
  (
    cd "$dir" || exit 2
    GITHUB_STEP_SUMMARY="$work/summary-$tool-$(basename "$dir").md"
    export GITHUB_STEP_SUMMARY
    if [ "$tool" = gitleaks ]; then
      rm -f .gitleaksignore
      gitleaks git . --config .gitleaks.toml --redact --no-banner --ignore-gitleaks-allow --log-opts="$log_opts" \
        --report-format json --report-path "$work/gl.json" 2>"$work/gl.log" || status=$?
      "$py" .github/scripts/report_findings.py gitleaks "$work/gl.json" "$status" \
        --gitleaks-log "$work/gl.log" --log-opts HEAD >"$work/report.log" 2>&1
      code=$?
      rules="$("$py" -c 'import json,sys; print(",".join(sorted({f["RuleID"] for f in json.load(open(sys.argv[1]))})))' "$work/gl.json" 2>/dev/null)"
    else
      docker run --rm --volume "$PWD:/src" --workdir /src "$semgrep_image" \
        semgrep scan --config p/default --metrics=off --disable-nosem --error --json --quiet \
        >"$work/sg.json" 2>"$work/sg.log" || status=$?
      "$py" .github/scripts/report_findings.py semgrep "$work/sg.json" "$status" >"$work/report.log" 2>&1
      code=$?
      rules="$("$py" -c 'import json,sys; print(",".join(sorted({r["check_id"].rsplit(".",1)[-1] for r in json.load(open(sys.argv[1]))["results"]})))' "$work/sg.json" 2>/dev/null)"
    fi
    echo "$code ${rules:--}"
  )
}

# probe DIR PATH: log in as alice, fetch PATH, print "STATUS USERNAME".
probe() {
  (cd "$1" && "$py" - "$2" <<'EOF'
import sys, tempfile
sys.path.insert(0, ".")
import db
from app import app
app.config.update(TESTING=True, DATABASE=tempfile.mkdtemp() + "/probe.db")
db.init_db(app.config["DATABASE"])
client = app.test_client()
client.get("/login/alice")
response = client.get(sys.argv[1])
body = response.get_json(silent=True) or {}
print(response.status_code, body.get("username", "-"))
EOF
  )
}

for branch in $branches; do
  section "Branch: $branch"
  dir="$work/$branch"
  git clone -q --branch "$branch" "$repo" "$dir" || { fail "clone $branch"; continue; }
  ( cd "$dir" && "$work/venv/bin/ruff" check . >/dev/null ) && pass "lint (ruff)" || fail "lint (ruff)"
  ( cd "$dir" && "$py" -m pytest -q >"$work/pytest.log" 2>&1 ) &&
    pass "unit tests ($(tail -1 "$work/pytest.log"))" || { fail "unit tests"; tail -5 "$work/pytest.log"; }

  gl="$(gate gitleaks "$dir")"
  sg="$(gate semgrep "$dir")"
  idor="$(probe "$dir" /api/users/2/profile)"
  sqli="$(probe "$dir" "/api/users/0%20OR%20username%3D'carol'/profile")"
  union="$(probe "$dir" "/api/users/0%20UNION%20SELECT%201,group_concat(home_address,'%20;%20'),3,4,5,6%20FROM%20users/profile")"

  case "$branch" in
    main)
      expect "secret scan (whole history): clean" "0 -" "$gl"
      expect "code scan: clean" "0 -" "$sg"
      expect "no profile endpoint yet" "404 -" "$idor"
      ;;
    agent-output-example)
      expect "secret scan: finds the planted key" "1 wsclab-session-key" "$gl"
      expect "code scan: finds debug mode + SQL injection" \
        "1 debug-enabled,formatted-sql-query,sqlalchemy-execute-raw-query" "$sg"
      expect "IDOR: Alice can read Bob's profile" "200 bob" "$idor"
      expect "SQL injection: crafted ID returns Carol" "200 carol" "$sqli"
      expect "SQL injection: UNION returns every home address" \
        "200 101 Maple Ave, Springfield ; 202 Oak St, Riverton ; 303 Pine Rd, Lakeview" "$union"
      expect "agent commit touches only the expected files" "app.py db.py tests/test_profile.py" \
        "$(git diff --name-only main agent-output-example | tr '\n' ' ' | sed 's/ $//')"
      grep -q "debug=True" "$dir/app.py" && pass "debug=True present" || fail "debug=True present"
      pinned="$(grep -oE '(app\.py|db\.py|tests/test_profile\.py):[0-9a-f]{40}' scripts/use-example-change.sh | tr ':\n' '  ')"
      actual="$(for f in app.py db.py tests/test_profile.py; do printf '%s %s ' "$f" "$(git rev-parse "agent-output-example:$f")"; done)"
      expect "example hashes pinned in use-example-change.sh match this branch" "$actual" "$pinned"
      # A pull request can't silence its own findings with "# nosemgrep".
      sed -i.bak 's/debug=True)/debug=True)  # nosemgrep/' "$dir/app.py"
      sed -i.bak 's/^\(    row = get_db().execute(query).fetchone()\)$/\1  # nosemgrep/' "$dir/db.py"
      [ "$(cat "$dir/app.py" "$dir/db.py" | grep -c nosemgrep)" = 2 ] && pass "planted two '# nosemgrep' comments" ||
        fail "planted two '# nosemgrep' comments"
      expect "code scan ignores '# nosemgrep' comments" \
        "1 debug-enabled,formatted-sql-query,sqlalchemy-execute-raw-query" "$(gate semgrep "$dir")"
      (cd "$dir" && git checkout -q -- app.py db.py && rm -f app.py.bak db.py.bak)
      ;;
    agent-output-after-gates)
      expect "secret scan: clean" "0 -" "$gl"
      expect "code scan: clean" "0 -" "$sg"
      expect "IDOR still there: Alice can read Bob's profile" "200 bob" "$idor"
      expect "SQL injection fixed" "404 -" "$sqli"
      ;;
    reference-solution)
      expect "secret scan: clean" "0 -" "$gl"
      expect "code scan: clean" "0 -" "$sg"
      expect "IDOR fixed: Alice is refused Bob's profile" "403 -" "$idor"
      expect "Alice can still read her own profile" "200 alice" "$(probe "$dir" /api/users/1/profile)"
      ;;
  esac
done

section "Trust guards (a scanner that didn't look must not pass)"
dir="$work/agent-output-example"
expect "gitleaks that scanned 0 commits is reported as not finished" "2 -" \
  "$(gate gitleaks "$dir" "0000000000000000000000000000000000000000..HEAD")"
expect "gitleaks that scanned only some commits is reported as not finished" "2 wsclab-session-key" \
  "$(gate gitleaks "$dir" "HEAD~1..HEAD")"
# The exact-count guard must agree with gitleaks on unusual but normal commits,
# or it would cry "did not finish" on a healthy scan.
git clone -q "$work/main" "$work/oddcommits" && (
  cd "$work/oddcommits" && git config user.email t@example.com && git config user.name t &&
    sed -i.bak '/^import os$/d' app.py && rm -f app.py.bak && git commit -qam "delete a line only" &&
    git rm -q LICENSE && git commit -qm "delete a whole file" &&
    git mv AGENTS.md AGENTS-renamed.md && git commit -qm "rename only" &&
    chmod +x db.py && git commit -qam "mode change only" &&
    printf '\000\001' >blob.bin && git add blob.bin && git commit -qm "binary only" &&
    git commit -q --allow-empty -m "empty" &&
    git switch -qc side HEAD~2 && printf 'x = 1\n' >side.py && git add side.py && git commit -qm side &&
    git switch -q - && git merge -q --no-edit side
)
expect "gitleaks guard agrees with gitleaks on deletions, renames, binaries, merges" "0 -" \
  "$(gate gitleaks "$work/oddcommits")"
echo '{"results": [], "errors": [], "paths": {"scanned": []}}' >"$work/empty.json"
(cd "$dir" && "$py" .github/scripts/report_findings.py semgrep "$work/empty.json" 0 >/dev/null 2>&1)
expect "semgrep that scanned no files is reported as not finished" 2 $?
git clone -q "$work/main" "$work/unicode" && (
  cd "$work/unicode" && git config user.email t@example.com && git config user.name t &&
    printf 'x = 1\n' >"perfil_usuário.py" && git add -A && git commit -qm unicode
)
expect "semgrep coverage check handles non-ASCII file names" "0 -" "$(gate semgrep "$work/unicode")"
# Code can't switch off its own secret finding.
git clone -q "$work/main" "$work/allowcomment" && (
  cd "$work/allowcomment" && git config user.email t@example.com && git config user.name t &&
    git -C "$repo" show agent-output-example:app.py >app.py &&
    sed -i.bak 's/\(wsclab_sk_[0-9a-f]*"\))/\1)  # gitleaks:allow/' app.py && rm -f app.py.bak &&
    git commit -qam "key with an allow comment"
)
expect "planted one gitleaks:allow comment" 1 "$(grep -c 'gitleaks:allow' "$work/allowcomment/app.py")"
expect "secret scan ignores gitleaks:allow comments" "1 wsclab-session-key" "$(gate gitleaks "$work/allowcomment")"
git clone -q "$work/agent-output-example" "$work/ignorefile" && (
  cd "$work/ignorefile" && git config user.email t@example.com && git config user.name t &&
    gitleaks git . --config .gitleaks.toml --no-banner --report-format json --report-path "$work/fp.json" 2>/dev/null
  "$py" -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["Fingerprint"])' "$work/fp.json" >.gitleaksignore &&
    git add .gitleaksignore && git commit -qm "ignore the finding"
)
(cd "$work/ignorefile" && gitleaks git . --config .gitleaks.toml --no-banner >/dev/null 2>&1)
expect "a .gitleaksignore would hide the key if left in place (so the next check means something)" 0 $?
expect "secret scan deletes .gitleaksignore and still finds the key" "1 wsclab-session-key" "$(gate gitleaks "$work/ignorefile")"

section "Attendee helper scripts, in a template-style copy (no shared history)"
# A "Use this template" copy is one fresh commit with no history in common with
# this repository. Build one, then play the attendee in clones of it.
clone_copy() {  # clone_copy COPY DIR: a new "codespace" on COPY
  rm -rf "${work:?}/$2"
  git clone -q "$work/$1.git" "$work/$2"
  git -C "$work/$2" config user.name "Lab Attendee"
  git -C "$work/$2" config user.email "attendee@example.com"
}
make_copy() {
  local name="$1"
  git init -q --bare --initial-branch=main "$work/$name.git"
  git clone -q "$repo" "$work/$name-seed" && (
    cd "$work/$name-seed" &&
      git checkout -q --orphan fresh main && git commit -q -m "Initial commit" &&
      git push -q "$work/$name.git" fresh:main
  )
  clone_copy "$name" "$name"
}
run_script() {  # run_script DIR SCRIPT: run a helper script as the attendee would
  (cd "$work/$1" && LAB_TEMPLATE_REPO="$repo" GITHUB_REPOSITORY="attendee/$1" \
    bash "scripts/$2" >"$work/script.log" 2>&1)
}
gates_on() {  # does the workflow at REF trigger on pull_request?
  git -C "$work/$1" show "$2:$workflow" | "$py" -c \
    'import sys,yaml; on = yaml.safe_load(sys.stdin)[True]; print("on" if "pull_request" in on else "off")'
}
edit_gate_line() { sed -i.bak 's/^  # pull_request:/  pull_request:/' "$work/$1/$workflow" && rm -f "$work/$1/$workflow.bak"; }
remote_has() { git -C "$work/$1" ls-remote --exit-code --heads origin "$2" >/dev/null && echo yes || echo no; }
refuse_pushes() {
  printf '#!/bin/sh\necho "refused for the test" >&2\nexit 1\n' >"$work/$1.git/hooks/pre-receive"
  chmod +x "$work/$1.git/hooks/pre-receive"
}
accept_pushes() { rm -f "$work/$1.git/hooks/pre-receive"; }

make_copy optionb
run_script optionb use-example-change.sh
expect "Option B: use-example-change.sh succeeds" 0 $?
expect "Option B: branch pushed with exactly the agent's files" "app.py db.py tests/test_profile.py" \
  "$(git -C "$work/optionb" diff --name-only origin/main origin/agent-change | tr '\n' ' ' | sed 's/ $//')"
expect "Option B: files match the example branch" "" \
  "$(git -C "$work/optionb" diff origin/agent-change "$(git rev-parse agent-output-example)" -- app.py db.py tests 2>&1 | head -1)"
grep -q "compare/main...agent-change" "$work/script.log" && pass "Option B: prints the pull request link" ||
  fail "Option B: prints the pull request link"
run_script optionb use-example-change.sh
expect "Option B: running it again just returns to the branch" 0 $?

# Step 3 from a brand-new codespace, which starts on main: the gate edit must
# land on the step 2 branch, not on a new branch with clean code.
clone_copy optionb optionb-fresh
edit_gate_line optionb-fresh
run_script optionb-fresh save-my-change.sh
expect "Step 3 in a fresh codespace: save-my-change.sh succeeds" 0 $?
expect "Step 3 in a fresh codespace: edit lands on agent-change" agent-change \
  "$(git -C "$work/optionb-fresh" branch --show-current)"
expect "Step 3: gates are on at the pushed branch" on "$(gates_on optionb-fresh origin/agent-change)"
expect "Step 3: gates are still off on main" off "$(gates_on optionb-fresh origin/main)"
expect "Step 3: commit message" "Turn on the security gates" \
  "$(git -C "$work/optionb-fresh" log -1 --format=%s origin/agent-change)"
expect "Step 3: no stray my-agent-change branch" no "$(remote_has optionb-fresh my-agent-change)"
expect "Step 3: secret scan over the attendee's branch finds the key" "1 wsclab-session-key" \
  "$(gate gitleaks "$work/optionb-fresh")"
run_script optionb-fresh turn-on-gates.sh
expect "turn-on-gates.sh when the gates are already on: succeeds" 0 $?
grep -q "already on" "$work/script.log" && pass "turn-on-gates.sh says the gates are already on" ||
  fail "turn-on-gates.sh says the gates are already on"
run_script optionb-fresh save-my-change.sh
expect "save-my-change.sh with nothing new stops" 1 $?
# Back in the first codespace, which is now behind GitHub.
run_script optionb turn-on-gates.sh
expect "Codespace behind GitHub: turn-on-gates.sh catches up" 0 $?
grep -q "already on" "$work/script.log" && pass "Codespace behind GitHub: says the gates are already on" ||
  fail "Codespace behind GitHub: says the gates are already on"

# Same, but the attendee clicked Commit on main in VS Code before running it.
make_copy committedgate
run_script committedgate use-example-change.sh
clone_copy committedgate optionb-committed
edit_gate_line optionb-committed
(cd "$work/optionb-committed" && git commit -qam "enable gates (committed on main)")
run_script optionb-committed save-my-change.sh
expect "Step 3, edit committed on main: lands on agent-change" "0 agent-change on" \
  "$? $(git -C "$work/optionb-committed" branch --show-current) $(gates_on optionb-committed origin/agent-change)"
expect "Step 3, edit committed on main: no stray my-agent-change branch" no \
  "$(remote_has optionb-committed my-agent-change)"
expect "Step 3, edit committed on main: agent code still on the branch" 1 \
  "$(git -C "$work/optionb-committed" show origin/agent-change:app.py | grep -c wsclab_sk_)"

section "Attendees going off script"
# A run that stopped after making the branch but before saving the example.
make_copy interrupted
(cd "$work/interrupted" && git switch -q --no-track -c agent-change origin/main && git push -q -u origin agent-change)
run_script interrupted use-example-change.sh
expect "Interrupted earlier run: re-running fills the empty branch" "0 app.py db.py tests/test_profile.py" \
  "$? $(git -C "$work/interrupted" diff --name-only origin/main origin/agent-change | tr '\n' ' ' | sed 's/ $//')"

# Pushes that fail (Wi-Fi, a GitHub error) must be retried by re-running, never
# reported as done.
make_copy flaky
refuse_pushes flaky
run_script flaky use-example-change.sh
expect "Failed push in step 2: the script reports failure" 1 $?
accept_pushes flaky
run_script flaky use-example-change.sh
expect "Failed push in step 2: re-running pushes the branch" "0 yes" "$? $(remote_has flaky agent-change)"
edit_gate_line flaky
refuse_pushes flaky
run_script flaky save-my-change.sh
expect "Failed push in step 3: the script reports failure" 1 $?
accept_pushes flaky
run_script flaky save-my-change.sh
expect "Failed push in step 3: re-running pushes the commit" "0 on" "$? $(gates_on flaky origin/agent-change)"

# Someone clicks Merge at step 2. The secret scan must still go red in step 3.
make_copy merged
run_script merged use-example-change.sh
(cd "$work/merged" && git switch -q main && git merge -q --no-ff --no-edit agent-change &&
  git push -q origin main && git switch -q agent-change)
run_script merged use-example-change.sh
expect "Merged at step 2: re-running step 2 succeeds" 0 $?
grep -q "already on main" "$work/script.log" && pass "Merged at step 2: says the change is already on main" ||
  fail "Merged at step 2: says the change is already on main"
run_script merged turn-on-gates.sh
expect "Merged at step 2: turn-on-gates.sh still works" 0 $?
(cd "$work/merged" && git fetch -q origin && git switch -q --detach origin/main &&
  git merge -q --no-edit origin/agent-change)   # what GitHub checks out for the new PR
expect "Merged at step 2: secret scan still finds the key" "1 wsclab-session-key" "$(gate gitleaks "$work/merged")"

# The agent "fixes" the key in a later commit. It is still in history.
(cd "$work/merged" && git switch -q agent-change && git fetch -q "$repo" agent-output-after-gates &&
  git checkout -q FETCH_HEAD -- app.py db.py && git commit -qam "Fix what the gates found")
expect "Key deleted in a later commit: it's gone from the current code" 0 \
  "$(grep -c wsclab_sk_ "$work/merged/app.py")"
expect "Key deleted in a later commit: secret scan still finds it" "1 wsclab-session-key" "$(gate gitleaks "$work/merged")"
expect "Key deleted in a later commit: code scan is clean" "0 -" "$(gate semgrep "$work/merged")"

# Option A: the agent's work, saved from main.
make_copy optiona
echo "# a change from my own agent" >>"$work/optiona/app.py"
run_script optiona save-my-change.sh
expect "Option A: save-my-change.sh from main makes a branch and pushes" "0 yes" \
  "$? $(remote_has optiona my-agent-change)"
run_script optiona save-my-change.sh
expect "Option A: nothing new to save stops" 1 $?
(cd "$work/optiona/scripts" && LAB_TEMPLATE_REPO="$repo" GITHUB_REPOSITORY=attendee/optiona \
  bash turn-on-gates.sh >"$work/script.log" 2>&1)
expect "turn-on-gates.sh works when run from inside scripts/" 0 $?
expect "Option A: gates are on at the pushed branch" on "$(gates_on optiona origin/my-agent-change)"

# Option A where the attendee clicked Commit on main in VS Code.
make_copy committed
(cd "$work/committed" && echo "# committed on main" >>app.py && git commit -qam "agent work")
run_script committed save-my-change.sh
expect "Commit made on main: moved to my-agent-change and pushed" "0 yes" \
  "$? $(remote_has committed my-agent-change)"
expect "Commit made on main: local main is back to GitHub's main" "" \
  "$(git -C "$work/committed" rev-list origin/main..main)"

# The Option A agent made a mess; switch to Option B without losing anything.
make_copy switched
echo "# half-done agent edit" >>"$work/switched/db.py"
run_script switched use-example-change.sh
expect "Switching from Option A to B: succeeds" "0 yes" "$? $(remote_has switched agent-change)"
expect "Switching from Option A to B: the agent's work was set aside, not lost" 1 \
  "$(git -C "$work/switched" stash list | wc -l | tr -d ' ')"

# Option A first, then switched to Option B: two lab branches. Step 3 from a
# fresh codespace must pick the one worked on last, not stop.
make_copy both
echo "# my agent's attempt" >>"$work/both/app.py"
run_script both save-my-change.sh
sleep 1   # commit times have one-second resolution
run_script both use-example-change.sh
clone_copy both both-fresh
edit_gate_line both-fresh
run_script both-fresh save-my-change.sh
expect "Both options used: step 3 lands on the latest branch (agent-change)" "0 agent-change" \
  "$? $(git -C "$work/both-fresh" branch --show-current)"

# Step 3 before step 2: a clear stop, not a silent exit.
make_copy early
edit_gate_line early
run_script early save-my-change.sh
expect "Step 3 before step 2: stops" 1 $?
grep -q "Do LAB step 2 first" "$work/script.log" && pass "Step 3 before step 2: says to do step 2 first" ||
  fail "Step 3 before step 2: says to do step 2 first"

# The branch changed both on GitHub (an edit on github.com) and in the codespace.
make_copy diverged
run_script diverged use-example-change.sh
clone_copy diverged diverged-web
(cd "$work/diverged-web" && git switch -q agent-change &&
  sed -i.bak 's/^  # pull_request:/  pull_request:/' "$workflow" && rm -f "$workflow.bak" &&
  git commit -qam "edit made on github.com" && git push -q)
(cd "$work/diverged" && echo "# note" >>README.md && git commit -qam "a local commit")
run_script diverged save-my-change.sh
expect "Branch changed on GitHub and here: stops" 1 $?
grep -q "has a change this codespace doesn't have" "$work/script.log" &&
  pass "Branch changed on GitHub and here: says so" || fail "Branch changed on GitHub and here: says so"

# A stray edit on main in a fresh codespace, with a step 2 branch already made.
make_copy stray
run_script stray use-example-change.sh
clone_copy stray stray-fresh
echo "# stray" >>"$work/stray-fresh/README.md"
run_script stray-fresh save-my-change.sh
expect "Stray edit on main with a step 2 branch: stops, no new branch" "1 no" \
  "$? $(remote_has stray-fresh my-agent-change)"

# The branch was deleted on GitHub ("Delete branch" button); the codespace still
# remembers it.
make_copy pruned
run_script pruned use-example-change.sh
clone_copy pruned pruned-other
git -C "$work/pruned-other" push -q origin --delete agent-change
run_script pruned use-example-change.sh
expect "Branch deleted on GitHub: re-running pushes it again" "0 yes" "$? $(remote_has pruned agent-change)"

# Detached HEAD with nothing to save.
make_copy detached
git -C "$work/detached" switch -q --detach origin/main
run_script detached save-my-change.sh
expect "Detached, nothing to save: stops" 1 $?
grep -q "not on a branch" "$work/script.log" && pass "Detached, nothing to save: says so" ||
  fail "Detached, nothing to save: says so"

# The gate edit was made on github.com, and this codespace has the same edit unsaved.
make_copy sameedit
run_script sameedit use-example-change.sh
clone_copy sameedit sameedit-web
(cd "$work/sameedit-web" && git switch -q agent-change &&
  sed -i.bak 's/^  # pull_request:/  pull_request:/' "$workflow" && rm -f "$workflow.bak" &&
  git commit -qam "edit made on github.com" && git push -q)
edit_gate_line sameedit
run_script sameedit save-my-change.sh
expect "Same edit here and on github.com: catches up and succeeds" 0 $?
grep -q "now matches GitHub" "$work/script.log" && pass "Same edit here and on github.com: says the branch matches" ||
  fail "Same edit here and on github.com: says the branch matches"

# No connection to GitHub: a plain message, not git's raw error.
make_copy offline
git -C "$work/offline" remote set-url origin "$work/no-such-remote.git"
run_script offline save-my-change.sh
expect "No connection: stops" 1 $?
grep -q "Could not reach GitHub" "$work/script.log" && pass "No connection: says so" || fail "No connection: says so"

# The workflow file was deleted and the deletion saved; the backup still works.
make_copy nogate
run_script nogate use-example-change.sh
(cd "$work/nogate" && git rm -q "$workflow" && git commit -qm "deleted the gate file")
run_script nogate turn-on-gates.sh
expect "Gate file deleted: turn-on-gates.sh restores it and turns the gates on" "0 on" \
  "$? $(gates_on nogate origin/agent-change)"

# An agent created a folder of tools (like a virtualenv) that isn't ignored.
make_copy bulky
mkdir -p "$work/bulky/tools" && for i in $(seq 1 60); do echo "x$i" >"$work/bulky/tools/f$i.py"; done
run_script bulky save-my-change.sh
expect "60 new files: save-my-change.sh stops before committing" "1 no" "$? $(remote_has bulky my-agent-change)"

section "Result"
if [ "$failures" -eq 0 ]; then
  printf '\033[1;32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[1;31m%s CHECK(S) FAILED\033[0m\n' "$failures"
  exit 1
fi

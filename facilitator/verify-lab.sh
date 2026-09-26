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
# repository, as a "Use this template" copy doesn't.
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

# gate TOOL DIR RANGE: run one security gate the way the workflow does and
# print "EXIT RULES" (report_findings.py exit status, sorted unique rule ids).
gate() {
  local tool="$1" dir="$2" range="$3" status=0 expected
  rm -f "$work/gl.json" "$work/gl.log" "$work/sg.json" "$work/sg.log"
  (
    cd "$dir" || exit 2
    GITHUB_STEP_SUMMARY="$work/summary-$tool-$(basename "$dir").md"
    export GITHUB_STEP_SUMMARY
    if [ "$tool" = gitleaks ]; then
      expected="$(git rev-list --count "$range" 2>/dev/null || echo 1)"
      gitleaks git . --config .gitleaks.toml --redact --no-banner --log-opts="$range" \
        --report-format json --report-path "$work/gl.json" 2>"$work/gl.log" || status=$?
      "$py" .github/scripts/report_findings.py gitleaks "$work/gl.json" "$status" \
        --gitleaks-log "$work/gl.log" --expected-commits "$expected" >"$work/report.log" 2>&1
      code=$?
      rules="$("$py" -c 'import json,sys; print(",".join(sorted({f["RuleID"] for f in json.load(open(sys.argv[1]))})))' "$work/gl.json" 2>/dev/null)"
    else
      docker run --rm --volume "$PWD:/src" --workdir /src "$semgrep_image" \
        semgrep scan --config p/default --metrics=off --error --json --quiet \
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
  git -C "$dir" fetch -q origin main:refs/remotes/origin/main 2>/dev/null
  ( cd "$dir" && "$work/venv/bin/ruff" check . >/dev/null ) && pass "lint (ruff)" || fail "lint (ruff)"
  ( cd "$dir" && "$py" -m pytest -q >"$work/pytest.log" 2>&1 ) &&
    pass "unit tests ($(tail -1 "$work/pytest.log"))" || { fail "unit tests"; tail -5 "$work/pytest.log"; }

  if [ "$branch" = main ]; then range="HEAD"; else range="origin/main..HEAD"; fi
  gl="$(gate gitleaks "$dir" "$range")"
  sg="$(gate semgrep "$dir" -)"
  idor="$(probe "$dir" /api/users/2/profile)"
  sqli="$(probe "$dir" "/api/users/0%20OR%20username%3D'carol'/profile")"

  case "$branch" in
    main)
      expect "secret scan: clean (whole history)" "0 -" "$gl"
      expect "code scan: clean" "0 -" "$sg"
      expect "no profile endpoint yet" "404 -" "$idor"
      ;;
    agent-output-example)
      expect "secret scan: finds the planted key" "1 wsclab-session-key" "$gl"
      expect "code scan: finds debug mode + SQL injection" \
        "1 debug-enabled,formatted-sql-query,sqlalchemy-execute-raw-query" "$sg"
      expect "IDOR: Alice can read Bob's profile" "200 bob" "$idor"
      expect "SQL injection: crafted ID returns Carol" "200 carol" "$sqli"
      expect "agent commit touches only the expected files" "app.py db.py tests/test_profile.py" \
        "$(git diff --name-only main agent-output-example | tr '\n' ' ' | sed 's/ $//')"
      grep -q "debug=True" "$dir/app.py" && pass "debug=True present" || fail "debug=True present"
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
gitleaks git "$dir" --config "$dir/.gitleaks.toml" --no-banner --log-opts="0000000000000000000000000000000000000000..HEAD" \
  --report-format json --report-path "$work/bogus.json" 2>"$work/bogus.log"
(cd "$dir" && "$py" .github/scripts/report_findings.py gitleaks "$work/bogus.json" 0 \
  --gitleaks-log "$work/bogus.log" --expected-commits 1 >/dev/null 2>&1)
expect "gitleaks that scanned 0 commits is reported as not finished" 2 $?
echo '{"results": [], "errors": [], "paths": {"scanned": []}}' >"$work/empty.json"
(cd "$dir" && "$py" .github/scripts/report_findings.py semgrep "$work/empty.json" 0 >/dev/null 2>&1)
expect "semgrep that scanned no files is reported as not finished" 2 $?

section "Attendee helper scripts, in a template-style copy (no shared history)"
# A "Use this template" copy is one fresh commit with no history in common with
# this repository. Build one, then play the attendee in a clone of it.
make_copy() {
  local name="$1"
  git init -q --bare --initial-branch=main "$work/$name.git"
  git clone -q "$repo" "$work/$name-seed" && (
    cd "$work/$name-seed" &&
      git checkout -q --orphan fresh main && git commit -q -m "Initial commit" &&
      git push -q "$work/$name.git" fresh:main
  )
  git clone -q "$work/$name.git" "$work/$name"
  git -C "$work/$name" config user.name "Lab Attendee"
  git -C "$work/$name" config user.email "attendee@example.com"
}
run_script() {  # run_script COPY SCRIPT: run a helper script as the attendee would
  (cd "$work/$1" && LAB_TEMPLATE_REPO="$repo" GITHUB_REPOSITORY="attendee/$1" \
    bash "scripts/$2" >"$work/script.log" 2>&1)
}
gates_on() {  # does the workflow on this ref trigger on pull_request?
  git -C "$work/$1" show "$2:$workflow" | "$py" -c \
    'import sys,yaml; on = yaml.safe_load(sys.stdin)[True]; print("on" if "pull_request" in on else "off")'
}

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
grep -q "already did this step" "$work/script.log" && pass "Option B: says the step is already done" ||
  fail "Option B: says the step is already done"

# A fresh codespace starts on main without the local branch: re-running must
# recover it rather than fail on push.
git -C "$work/optionb" switch -q main && git -C "$work/optionb" branch -q -D agent-change
run_script optionb use-example-change.sh
expect "Option B: in a fresh codespace, re-running recovers the branch" \
  "0 agent-change" "$? $(git -C "$work/optionb" branch --show-current)"

sed -i.bak 's/^  # pull_request:/  pull_request:/' "$work/optionb/$workflow" && rm -f "$work/optionb/$workflow.bak"
run_script optionb save-my-change.sh
expect "Step 3: save-my-change.sh pushes the edited workflow" 0 $?
expect "Step 3: gates are on at the pushed branch" on "$(gates_on optionb origin/agent-change)"
expect "Step 3: gates are still off on main" off "$(gates_on optionb origin/main)"
expect "Step 3: commit message" "Turn on the security gates" "$(git -C "$work/optionb" log -1 --format=%s origin/agent-change)"
base="$(git -C "$work/optionb" rev-parse origin/main)"
head="$(git -C "$work/optionb" rev-parse origin/agent-change)"
expect "Step 3: secret scan over the attendee's pull request range" "1 wsclab-session-key" \
  "$(gate gitleaks "$work/optionb" "$base..$head")"

make_copy optiona
echo "# a change from my own agent" >>"$work/optiona/app.py"
run_script optiona save-my-change.sh
expect "Option A: save-my-change.sh from main makes a branch and pushes" 0 $?
expect "Option A: branch name" "my-agent-change" "$(git -C "$work/optiona" branch --show-current)"
run_script optiona save-my-change.sh
expect "Option A: nothing to save stops politely" 1 $?
run_script optiona turn-on-gates.sh
expect "Backup: turn-on-gates.sh succeeds" 0 $?
expect "Backup: gates are on at the pushed branch" on "$(gates_on optiona origin/my-agent-change)"

section "Result"
if [ "$failures" -eq 0 ]; then
  printf '\033[1;32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[1;31m%s CHECK(S) FAILED\033[0m\n' "$failures"
  exit 1
fi

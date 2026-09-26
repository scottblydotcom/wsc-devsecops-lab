"""Turn a scanner's JSON report into GitHub annotations and a readable summary.

    report_findings.py gitleaks REPORT.json EXIT_STATUS --gitleaks-log LOG --log-opts HEAD
    report_findings.py semgrep  REPORT.json EXIT_STATUS

Exit status: 0 = no findings, 1 = findings, 2 = the scanner did not do its job.
A scanner that crashed, or quietly scanned nothing, must never look like a
scanner that found nothing. So before trusting "no findings" we check that it
really looked: gitleaks must have scanned exactly the commits it should have,
and Semgrep must have scanned every Python file it doesn't skip by default.
"""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

TITLES = {"gitleaks": "Secret scan (gitleaks)", "semgrep": "Code scan (Semgrep)"}

# Plain-language notes for the findings this lab expects. Anything else falls
# back to the scanner's own message.
SQL_INJECTION = (
    "A database query is built by pasting text together. Crafted input can "
    "change what the query does (SQL injection)."
)
PLAIN_ENGLISH = {
    "wsclab-session-key": (
        "A secret key is written into the code. Anyone who can read this "
        "repository, now or later, can use it to forge a login. Deleting it in a "
        "later commit doesn't remove it from history: the fix is a new key."
    ),
    "debug-enabled": (
        "Debug mode is on. Anyone who triggers an error sees your source code, and "
        "the built-in debugger can run code on the server if someone gets past its PIN."
    ),
    "formatted-sql-query": SQL_INJECTION,
    "sqlalchemy-execute-raw-query": SQL_INJECTION,
}

# Folders Semgrep 1.178.0 skips by default (measured, not from its docs).
SEMGREP_SKIPS = {"tests", "test", "build", "_build", "dist", "vendor", "node_modules", ".venv", ".env", ".tox"}


class ScannerDidNotRun(Exception):
    """The scanner's result cannot be trusted as a pass."""


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotePath=false", *args],
        capture_output=True, text=True, check=True,
    ).stdout


def commits_gitleaks_should_scan(log_opts):
    """Count the commits gitleaks 8.30.1 reports as scanned: non-merge commits
    that change at least one line of text in a file they don't delete outright
    (measured: whole-file deletions, pure renames, mode changes and binary
    files don't count; a commit that only deletes lines inside a file does)."""
    count, changed = 0, False
    log = git("log", "--no-merges", "--diff-filter=d", "--format=@%H", "--numstat", log_opts)
    for line in log.splitlines():
        if line.startswith("@"):
            count, changed = count + changed, False
        else:
            numbers = re.match(r"(\d+)\t(\d+)\t", line)
            if numbers and int(numbers[1]) + int(numbers[2]) > 0:
                changed = True
    return count + changed


def gitleaks_findings(report, args):
    log = Path(args.gitleaks_log).read_text(encoding="utf-8")
    log = re.sub(r"\x1b\[[0-9;]*m", "", log)  # drop terminal colors
    scanned = re.findall(r"(\d+) commits scanned", log)
    expected = commits_gitleaks_should_scan(args.log_opts)
    if not scanned or int(scanned[-1]) != expected:
        got = scanned[-1] if scanned else "an unknown number of"
        raise ScannerDidNotRun(
            f"gitleaks scanned {got} commit(s), but {expected} should have been "
            "scanned, so its result can't be trusted."
        )
    for leak in report:
        yield {
            "rule": leak["RuleID"],
            "file": leak["File"],
            "line": leak["StartLine"],
            "where": f"commit {leak['Commit'][:7]}",
            "message": leak["Description"],
        }


def semgrep_findings(report, _args):
    tracked = [
        path
        for path in git("ls-files", "-z", "--", "*.py").split("\0")
        if path and not SEMGREP_SKIPS.intersection(path.split("/")[:-1])
    ]
    missed = sorted(set(tracked) - set(report["paths"]["scanned"]))
    if not tracked or missed:
        raise ScannerDidNotRun(f"Semgrep did not scan these files: {missed or 'any'}")
    for result in report["results"]:
        yield {
            "rule": result["check_id"].rsplit(".", 1)[-1],
            "file": result["path"],
            "line": result["start"]["line"],
            "where": "",
            "message": result["extra"]["message"],
        }


def escape_data(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text):
    return escape_data(text).replace(":", "%3A").replace(",", "%2C")


def table_cell(text):
    return " ".join(text.split()).replace("|", "/")


def write_summary(markdown):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as summary:
            summary.write(markdown + "\n")
    print(markdown)


def did_not_finish(title, problem):
    print(f"::error title={escape_property(title)} did not finish::{escape_data(str(problem))}")
    write_summary(f"## ⚠️ {title} did not finish\n\n{problem}\n\n**This is not a pass.**")
    return 2


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tool", choices=TITLES)
    parser.add_argument("report")
    parser.add_argument("status", type=int)
    parser.add_argument("--gitleaks-log")
    parser.add_argument("--log-opts", default="HEAD")
    args = parser.parse_args()
    title = TITLES[args.tool]

    try:
        if args.status not in (0, 1):  # both tools: 0 = clean, 1 = findings
            raise ScannerDidNotRun(f"The scanner exited with status {args.status}.")
        with open(args.report, encoding="utf-8") as handle:
            report = json.load(handle)
        reader = gitleaks_findings if args.tool == "gitleaks" else semgrep_findings
        findings = list(reader(report, args))
        if (args.status == 1) != bool(findings):
            raise ScannerDidNotRun(
                f"Exit status {args.status} does not match the "
                f"{len(findings)} finding(s) in the report."
            )
    except (ScannerDidNotRun, OSError, ValueError, KeyError, TypeError,
            subprocess.CalledProcessError) as problem:
        return did_not_finish(title, problem)

    # Semgrep can finish with findings AND report errors (a file it couldn't
    # parse). Show the findings either way, but never call it clean.
    errors = report.get("errors", []) if args.tool == "semgrep" else []
    if not findings:
        if errors:
            return did_not_finish(title, f"Semgrep reported errors: {errors[:3]}")
        write_summary(
            f"## ✅ {title}: no findings\n\n"
            "Remember: a scanner only finds the patterns it was taught."
        )
        return 0

    # Two rules can flag the same problem on the same line; show it once.
    problems = {}
    for f in findings:
        meaning = PLAIN_ENGLISH.get(f["rule"], f["message"])
        key = (f["file"], f["line"], f["where"], meaning)
        problems.setdefault(key, []).append(f["rule"])

    rows = [
        f"## ❌ {title}: {len(problems)} problem(s) found",
        "",
        "| Where | Rule | What it means |",
        "|---|---|---|",
    ]
    for (file, line, where, meaning), rules in problems.items():
        rule_names = ", ".join(rules)
        props = ",".join([
            f"file={escape_property(file)}",
            f"line={line}",
            f"title={escape_property(title + ': ' + rule_names)}",
        ])
        print(f"::error {props}::{escape_data(meaning)}")
        place = f"`{table_cell(file)}` line {line}" + (f", {where}" if where else "")
        rule_cell = ", ".join(f"`{rule}`" for rule in rules)
        rows.append(f"| {place} | {rule_cell} | {table_cell(meaning)} |")
    if errors:
        rows += ["", f"Semgrep also reported {len(errors)} error(s), so it may have missed more."]
    write_summary("\n".join(rows))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

"""Turn a scanner's JSON report into GitHub annotations and a readable summary.

    report_findings.py gitleaks REPORT.json EXIT_STATUS --gitleaks-log LOG --expected-commits N
    report_findings.py semgrep  REPORT.json EXIT_STATUS

Exit status: 0 = no findings, 1 = findings, 2 = the scanner did not do its job.
A scanner that crashed, or quietly scanned nothing, must never look like a
scanner that found nothing. So before trusting "no findings" we check that it
really looked: gitleaks must have scanned the pull request's commits, and
Semgrep must have scanned every Python file outside tests/.
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
        "repository, now or later, can use it to forge a login."
    ),
    "debug-enabled": (
        "Debug mode is on. Flask's debugger lets anyone who can reach the app "
        "run their own code on the server."
    ),
    "formatted-sql-query": SQL_INJECTION,
    "sqlalchemy-execute-raw-query": SQL_INJECTION,
}


class ScannerDidNotRun(Exception):
    """The scanner's result cannot be trusted as a pass."""


def gitleaks_findings(report, args):
    log = Path(args.gitleaks_log).read_text(encoding="utf-8")
    log = re.sub(r"\x1b\[[0-9;]*m", "", log)  # drop terminal colors
    scanned = re.findall(r"(\d+) commits scanned", log)
    if args.expected_commits > 0 and (not scanned or int(scanned[-1]) == 0):
        raise ScannerDidNotRun(
            f"gitleaks scanned 0 of the {args.expected_commits} commit(s) in this "
            "pull request, so it never looked at them."
        )
    for leak in report:
        yield {
            "rule": leak["RuleID"],
            "file": leak["File"],
            "line": leak["StartLine"],
            "message": f"{leak['Description']} (commit {leak['Commit'][:7]})",
        }


def semgrep_findings(report, _args):
    tracked = subprocess.run(
        ["git", "ls-files", "--", "*.py", ":!:tests/*"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    missed = sorted(set(tracked) - set(report["paths"]["scanned"]))
    if not tracked or missed:
        raise ScannerDidNotRun(f"Semgrep did not scan these files: {missed or 'any'}")
    if report.get("errors"):
        raise ScannerDidNotRun(f"Semgrep reported errors: {report['errors'][:3]}")
    for result in report["results"]:
        yield {
            "rule": result["check_id"].rsplit(".", 1)[-1],
            "file": result["path"],
            "line": result["start"]["line"],
            "message": result["extra"]["message"],
        }


def escape_data(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text):
    return escape_data(text).replace(":", "%3A").replace(",", "%2C")


def write_summary(markdown):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as summary:
            summary.write(markdown + "\n")
    print(markdown)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tool", choices=TITLES)
    parser.add_argument("report")
    parser.add_argument("status", type=int)
    parser.add_argument("--gitleaks-log")
    parser.add_argument("--expected-commits", type=int, default=0)
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
        print(f"::error title={escape_property(title)} did not finish::{escape_data(str(problem))}")
        write_summary(f"## ⚠️ {title} did not finish\n\n{problem}\n\n**This is not a pass.**")
        return 2

    if not findings:
        write_summary(
            f"## ✅ {title}: no findings\n\n"
            "Remember: a scanner only finds the patterns it was taught."
        )
        return 0

    # Two rules can flag the same problem on the same line; show it once.
    problems = {}
    for f in findings:
        meaning = PLAIN_ENGLISH.get(f["rule"], f["message"])
        problems.setdefault((f["file"], f["line"], meaning), []).append(f["rule"])

    rows = [
        f"## ❌ {title}: {len(problems)} problem(s) found",
        "",
        "| Where | Rule | What it means |",
        "|---|---|---|",
    ]
    for (file, line, meaning), rules in problems.items():
        rule_names = ", ".join(rules)
        props = ",".join([
            f"file={escape_property(file)}",
            f"line={line}",
            f"title={escape_property(title + ': ' + rule_names)}",
        ])
        print(f"::error {props}::{escape_data(meaning)}")
        rule_cell = ", ".join(f"`{rule}`" for rule in rules)
        rows.append(f"| `{file}` line {line} | {rule_cell} | {meaning.replace('|', '/')} |")
    write_summary("\n".join(rows))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

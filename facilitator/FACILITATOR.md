# Facilitator Guide: Green Pipeline, Insecure Code

45-minute hands-on lab, 11:00–11:45, right after the break that follows the
tabletop "Who Should Have Caught This?". Attendees follow [LAB.md](../LAB.md).
This page is the answer key, so attendees can read it too. Nothing here depends
on it staying secret.

**Learning goal:** an AI agent writes code, the pipeline goes green, and it's still
insecure. Then the group adds a security gate that catches it, and sees what the
gate *still* misses.

## What's planted

All of it is on the `agent-output-example` branch, one commit on top of `main`.

| Issue | Where | Caught by | Why it matters |
|---|---|---|---|
| Hardcoded session-signing key (`wsclab_sk_…`, fake) | `app.py`, the `app.secret_key` line | gitleaks, custom rule `wsclab-session-key` | Anyone who reads the repo can forge a login cookie for any user |
| `debug=True` | `app.py`, `app.run(...)` | Semgrep `debug-enabled` | The Flask debugger runs arbitrary code for whoever can reach it |
| SQL built with an f-string | `db.py`, `get_profile()` | Semgrep `formatted-sql-query` + `sqlalchemy-execute-raw-query` (two rules, same line) | SQL injection: `/api/users/1 OR 1=1/profile` works |
| **Missing authorization (IDOR)** | `app.py`, `user_profile()` | **Nothing.** Tests pass, gates pass | Logged in as Alice, `/api/users/2/profile` returns Bob's home address |

The agent change is realistic, not cartoonish. It uses the existing
`@login_required` decorator (so it *looks* secure: authentication, but no
authorization). Its three new tests all pass, including a 401 test that looks
security-minded. Every test logs in as Alice and asks for Alice. The key is
hardcoded "so logins survive the debug reloader", a plausible agent fix for a
real annoyance that `debug=True` itself causes.

Two more branches for the projector (attendees never need them):

| Branch | State | Use it for |
|---|---|---|
| `agent-output-after-gates` | The same feature with the three gate findings fixed. Tests ✅, gates ✅ | Step 4: "Everything is green. Ship it?" Then show the IDOR still works |
| `reference-solution` | Ownership check (403) plus the test the agent didn't write | Debrief: the fix is two lines; the missing test is five |

## Timing and what to say

| Time | Step | Say / do |
|---|---|---|
| 0–8 | **1. Copy, Codespace, run** | Mirror LAB.md on the projector. While codespaces build (~2 min): "This is a full Linux machine in your browser. Nothing is installed on your laptop." Pairs are fine. |
| 8–18 | **2. Agent writes the feature, PR, green** | Read the request aloud. Most people run Option B. Have one volunteer with Copilot do Option A live on the projector if possible. When checks go green: **"Lint passed. Tests passed, including the agent's own tests. Would you merge it?"** Take a show of hands. |
| 18–30 | **3. Turn on the gates, red** | Do the one-line edit on the projector first, then let the room do it. While gates run (~1–2 min), explain the workflow file (callouts below). Walk the Summary table: secret, debug, SQL injection. Point out that each red mark sits on a line the agent wrote. |
| 30–38 | **4. What the gates missed** | Switch the projector to `agent-output-after-gates`: "Suppose the agent fixed all three. Everything is green. Ship it?" Then do the IDOR live: log in as Alice, open profile 1, change it to 2. **"Which check caught this? None of them. Who *should* have?"** |
| 38–45 | **Debrief + buffer** | See the debrief section. Remind people to delete their codespace (LAB step 5). |

If you're running behind, cut Option A demos first, then compress step 3's
walkthrough. Never cut step 4: it's the point of the lab.

## Teaching callouts in the pipeline (step 3, while gates run)

Open `.github/workflows/security-gates.yml` on the projector:

- **`permissions: contents: read`**: the pipeline's token can read code and do
  nothing else. *Agents are identities, and so is your CI.* Least privilege
  applies to both. (Tabletop Scenario C.)
- **Actions pinned to a full commit SHA, images pinned by digest.** A tag like
  `@v7` can be moved to point at different code; a SHA can't. This is the
  supply-chain point from the deck.
- **`pull_request`, never `pull_request_target`.** The second one runs with
  write access on code from strangers. GitHub is disabling it by default on
  public repos from Nov 2, 2026.
- **`persist-credentials: false`**: the checkout doesn't leave the token lying
  around for later steps (or tools) to pick up.
- **The trust guard.** gitleaks reports "no leaks found" even when it scanned
  nothing (a git error). We found this while building the lab. The workflow
  counts the PR's commits itself and fails if gitleaks didn't look. *A gate
  that can't prove it looked isn't a gate.*
- **Scanners only know what they were taught.** The secret is caught by a
  custom rule for our key format (`.gitleaks.toml`). A key in some other
  format could sail through. Semgrep's defaults also skip `tests/`.
- **`AGENTS.md` / `CLAUDE.md`**: instructions every agent reads before touching
  this repo. Ask: *"Who reviews this file? What does it say about security?"*
  (Nothing. That's deliberate, and it's a Plan-stage gap.)
- **Red doesn't block anything yet.** Anyone can still click Merge. A gate only
  gates when it's a *required* status check (branch protection or a ruleset).
  Until then it's a suggestion.

## Debrief (tie back to the tabletop)

1. **"Who should have caught the IDOR?"** → **Plan / Threat Model**: nobody wrote
   down "people may only see their own profile", so the agent couldn't know.
   And **Test / DAST + pen test**: tabletop **Scenario B**, almost word for
   word. The agent wrote tests that match its own assumptions.
2. **What did the gates buy us?** Three real bugs, caught automatically on
   every PR, in about a minute, for free. Worth it, and not sufficient.
3. **The hardcoded key**: if it had merged, deleting it later wouldn't be enough.
   It lives in git history forever. Rotate it. (That's why the secret scan
   reads every commit in the PR, not just the final files.)
4. Close with the tabletop line: ***"The lifecycle doesn't need reinventing. It
   needs to stop assuming only humans are inside it."*** Every control today
   (gates, least privilege, threat model, adversarial tests) already existed.
   What changed is who's writing the code.

## Recovery moves

| Problem | Move |
|---|---|
| Someone checked **Include all branches** | Harmless. The helper scripts don't use those branches. Tell them not to open PRs from copied branches: GitHub treats template branches as unrelated histories. |
| Codespace won't create ("billing issue", "maximum codespaces") | Pair them with a neighbor. Known GitHub-side issues; not fixable in the room. |
| Codespace is slow or stuck on "Setting up" | Reload the browser tab once. Still stuck after 5 min: pair up. |
| A workflow run is **waiting for approval** | Since July 2026 GitHub may hold runs it judges suspicious, even in your own repo. Attendee clicks the run → **Approve and run workflow**. |
| Push rejected when turning on gates (workflow-file permission) | Edit on github.com instead: on the repo page, switch the branch menu to their PR branch, open `.github/workflows/security-gates.yml`, click the pencil icon, delete the `# ` before `pull_request:`, and **Commit changes** directly to that branch. |
| YAML broken after the edit (workflow error banner) | `bash scripts/turn-on-gates.sh`. It restores the file and makes the edit correctly. |
| Gates don't appear on the PR | Check the attendee is on their PR branch (`git branch`), not `main`. Then re-run `bash scripts/save-my-change.sh`. |
| `use-example-change.sh` can't download the example | Wi-Fi. It needs to reach github.com. Hotspot, or pair up. |
| Actions queued for minutes (GitHub incident) | Check <https://www.githubstatus.com>. Switch to your projector demo copy, which has each state already run. |
| Venue Wi-Fi fails | Phone hotspot for the projector machine; play the recorded walkthrough; keep the discussion going. |

## Before the workshop

**By Mon Sep 28**
- [ ] Publish the template repo: public, **Settings → Template repository** ✅.
- [ ] Run `bash facilitator/verify-lab.sh`. It must end with `ALL CHECKS PASSED`.
- [ ] Dry run from a **fresh GitHub account** (not yours), using only LAB.md, timed.
      Record the time, where they got stuck, and screenshots. Include one Copilot
      Free agent-mode run inside the Codespace (the $0 path is documented, but
      Free-in-Codespaces hasn't been tested end to end).
- [ ] Confirm the step-3 push of a workflow-file change works from a Codespace
      on that fresh account.

**By Tue Sep 29**
- [ ] Send [SETUP-EMAIL.md](SETUP-EMAIL.md). After this, **freeze `main`**. Attendees
      make their copy in advance, and a copy doesn't pick up later changes.

**Oct 2 (day before)**
- [ ] Re-run `verify-lab.sh`. Semgrep downloads its `p/default` rules at run time,
      so a rule change on semgrep.dev could change what's caught.
- [ ] In a demo copy of your own, run the whole lab and leave it in its final
      state: PR red, `agent-output-after-gates` green. That's your projector fallback.
- [ ] Record a short screen capture of the full lab (last-resort fallback).
- [ ] Charge the phone hotspot.

**Maintenance.** The example branches are single commits on top of `main`.
If `main` changes, rebase them, re-run the check, and push:
```bash
for b in agent-output-example agent-output-after-gates reference-solution; do
  git rebase main "$b" || break
done
git switch main && bash facilitator/verify-lab.sh
git push --force-with-lease origin agent-output-example agent-output-after-gates reference-solution
```

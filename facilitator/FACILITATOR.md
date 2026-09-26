# Facilitator Guide: Green Pipeline, Insecure Code

45-minute hands-on lab, 11:00–11:45, right after the break that follows the
tabletop "Who Should Have Caught This?". Attendees follow [LAB.md](../LAB.md).
This page is the answer key, and attendees can read it too. The reveal still
works if someone has.

**Learning goal:** an AI agent writes code, the pipeline goes green, and it's still
insecure. Then the group adds a security gate that catches it, and sees what the
gate *still* misses.

## What's planted

All of it is on the `agent-output-example` branch, one commit on top of `main`.

| Issue | Where | Caught by | Why it matters |
|---|---|---|---|
| Hardcoded session-signing key (`wsclab_sk_…`, fake) | `app.py`, the `app.secret_key` line | gitleaks, custom rule `wsclab-session-key` | Anyone who reads the repo can forge a login cookie for any user |
| `debug=True` | `app.py`, `app.run(...)` | Semgrep `debug-enabled` | Any error shows the source code to whoever triggers it, and the debugger can run code on the server if someone gets past its PIN |
| SQL built with an f-string | `db.py`, `get_profile()` | Semgrep `formatted-sql-query` + `sqlalchemy-execute-raw-query` (two rules, same line) | SQL injection. `/api/users/0 OR username='carol'/profile` looks Carol up by a field the API never lets you search. `/api/users/0 UNION SELECT 1,group_concat(home_address,' ; '),3,4,5,6 FROM users/profile` returns every home address in one request |
| **Missing authorization (IDOR)** | `app.py`, `user_profile()` | **Nothing.** Tests pass, gates pass | Logged in as Alice, `/api/users/2/profile` returns Bob's home address |

The agent change is realistic, not cartoonish. It uses the existing
`@login_required` decorator, so it *looks* secure: authentication, but no
authorization. Its three new tests all pass, including a 401 test that looks
security-minded. No test ever asks for another real person's profile; the only
logged-in user is Alice. The key is hardcoded "so logins survive the debug
reloader", a plausible agent fix for a real annoyance that `debug=True` itself
causes.

Honest caveat if someone asks: current agents usually copy the parameterized query
sitting a few lines above in `db.py`. The f-string is there so the gate has
something real to catch.

**"Can't Alice just open `/login/bob`?"** Yes: the demo login has no password, only
to keep the lab short. Ask the room to pretend it checks one. In a real app Alice
can't become Bob, so the IDOR is how she'd read his address.

Two more branches for the projector:

| Branch | State | Use it for |
|---|---|---|
| `agent-output-after-gates` | The same feature written without the three gate findings in the first place. Tests ✅, gates ✅, IDOR still there | Step 4: "Everything is green. Ship it?" |
| `reference-solution` | The authorization fix plus the test the agent didn't write | Debrief, and LAB's take-home |

The reference fix is three lines: the ownership check (`abort(403)` unless it's
your own ID), plus `<int:user_id>` in the route, because the URL gives the text
`'1'` while the session holds the number `1`. One of the agent's own tests also had
to change: it expected 404 for someone else's ID, which locked the insecure
behavior in. The missing test is four lines.

## Timing and what to say

| Time | Step | Say / do |
|---|---|---|
| 0–8 | **1. Copy, Codespace, run** | Mirror LAB.md on the projector. While codespaces build (~2 min): "This is a full Linux machine in your browser. Nothing is installed on your laptop." Pairs are fine. |
| 8–18 | **2. Agent writes the feature, PR, green** | Read the request aloud. Most people run Option B. If possible, have one volunteer with Copilot do Option A live on the projector. When checks go green: **"Lint passed. Tests passed, including the agent's own tests. Would you merge it?"** Show of hands only: nobody clicks Merge. |
| 18–30 | **3. Turn on the gates, red** | Switch the projector to **your own Option B demo pull request** (Option A gates may well stay green). Do the one-line edit there first, then let the room do it. While the gates run (~1–2 min), walk the callouts below. Then walk the Summary table: secret, debug, SQL injection. Each red mark sits on a line the agent wrote. |
| 30–38 | **4. What the gates missed** | Show the green `agent-output-after-gates` runs (recipe below): "Suppose the agent had avoided all three from the start. Everything is green. Ship it?" (If it had fixed them in a new commit instead, the secret scan would stay red: the key is still in history.) Then do the IDOR live: log in as Alice, open profile 1, change it to 2. **"Which check caught this? None of them. Who *should* have?"** Bring the Option A volunteer back for "whose agent did better?" |
| 38–45 | **Debrief + buffer** | See the debrief section. Remind people to delete their codespace (LAB step 5). |

If you're running behind, cut Option A demos first, then compress step 3's
walkthrough. Never cut step 4: it's the point of the lab.

**Step-4 projector recipe (set up by Oct 2).** In the template repo itself (its
branches share history, unlike a copy): **Actions → Build and test → Run
workflow → branch `agent-output-after-gates`**, then the same for **Security
gates**. Both go green; keep those two runs open in tabs. For the live IDOR on that
code, in your demo codespace:
```bash
git fetch https://github.com/scottblydotcom/wsc-devsecops-lab agent-output-after-gates
git switch --detach FETCH_HEAD && python app.py
```

## Teaching callouts in the pipeline (step 3, while gates run)

Open `.github/workflows/security-gates.yml` on the projector:

- **`permissions: contents: read`**: the pipeline's token can read code and do
  nothing else. *Agents are identities, and so is your CI.* Least privilege
  applies to both. (Tabletop Scenario C.)
- **Actions pinned to a full commit SHA, images pinned by digest.** A tag like
  `@v7` can be moved to point at different code; a SHA can't. This is the
  supply-chain point from the deck. The lab's own example download is pinned
  the same way (`scripts/use-example-change.sh`).
- **`pull_request`, never `pull_request_target`.** The second one runs with your
  repo's write token and secrets whenever a stranger opens a PR. If it ever runs
  their code, their code gets those powers. GitHub turns it off by default on
  public repos from Nov 2, 2026.
- **`persist-credentials: false`**: the checkout doesn't leave the token lying
  around for later steps (or tools) to pick up.
- **The trust guard.** gitleaks reports "no leaks found" even when it scanned
  nothing (a git error). We found this while building the lab. The report script
  counts the commits gitleaks should have read and fails unless it read exactly
  those. *A gate that can't prove it looked isn't a gate.*
- **Scanners only know what they were taught.** The secret is caught by a
  custom rule for our key format (`.gitleaks.toml`). A key in some other
  format could sail through. Semgrep's defaults also skip `tests/`. And gitleaks
  can't see a secret that first appears inside a merge commit.
- **A pull request can edit its own gates.** Code can carry `# nosemgrep` or a
  `gitleaks:allow` comment, or a PR can add a `.gitleaksignore` file. This
  workflow ignores all three (`--disable-nosem`, `--ignore-gitleaks-allow`, and
  deleting `.gitleaksignore` before the scan). But a PR can still loosen
  `.gitleaks.toml` or the workflow itself. That's why real teams add CODEOWNERS
  review on `.github/` and scanner config.
- **`AGENTS.md` / `CLAUDE.md`**: instructions every agent reads before touching
  this repo. Ask: *"Who reviews this file? What does it say about security?"*
  (Nothing. That's deliberate, and it's a Plan-stage gap.)
- **Red doesn't block anything yet.** Anyone can still click Merge. A gate only
  gates when it's a *required* status check (branch protection or a ruleset).
  Until then it's a suggestion.

## Debrief (tie back to the tabletop)

1. **"Who should have caught the IDOR?"** → **Plan / Threat Model** (tabletop
   **Scenario A**): nobody wrote down "people may only see their own profile", so
   the agent couldn't know. And **Test / DAST + pen test** (tabletop
   **Scenario B**, almost word for word): the agent wrote tests that match its own
   assumptions.
2. **What did the gates buy us?** Three real bugs, caught automatically on
   every PR, in about a minute, for free. Worth it, and not sufficient.
3. **The hardcoded key**: deleting it later isn't enough. It lives in git history,
   which is why the secret scan reads the whole history, not just the final
   files. Rotate the key.
4. Not covered today: tabletop **Scenario D**, watching what an agent does after it
   ships. The pipeline only sees code before it merges.
5. Close with the tabletop line: ***"The lifecycle doesn't need reinventing. It
   needs to stop assuming only humans are inside it."*** Every control today
   (gates, least privilege, threat model, adversarial tests) already existed.
   What changed is who's writing the code.

## Recovery moves

| Problem | Move |
|---|---|
| Someone clicked **Merge** in step 2 | No harm to the lesson: the secret scan reads the whole history, so it still goes red. Have them open a new pull request from the link the step-3 script prints. |
| Someone checked **Include all branches** | Mostly harmless: the scripts download the example from the template repo, and use the copied branch only if the template can't be reached (checked against the same pinned file hashes). Don't open PRs from copied branches: GitHub treats template branches as unrelated histories. |
| "Maximum codespaces" error | Delete or stop an old codespace at <https://github.com/codespaces> (**⋯ → Delete**), then retry. |
| "Billing issue" error creating a codespace | A known GitHub-side issue; not fixable in the room. Pair them with a neighbor. |
| Codespace is slow or stuck on "Setting up" | Reload the browser tab once. Still stuck after 5 min: pair up. |
| A workflow run is **waiting for approval** | Since July 2026 GitHub may hold runs it judges suspicious, even in your own repo. Attendee clicks the run → **Approve and run workflow**. |
| Push rejected when turning on gates (workflow-file permission) | Use the github.com edit in LAB's troubleshooting table: branch menu → their PR branch → `.github/workflows/security-gates.yml` → pencil → delete the `# ` before `pull_request:` → **Commit changes** to that branch. |
| No Security gates checks, or a workflow-error banner | `bash scripts/turn-on-gates.sh`. It restores the file, makes the edit correctly, and pushes. If the bad edit was made on github.com, fix it there instead (pencil icon on the file). |
| Option A agent stalled or made a mess | `bash scripts/use-example-change.sh`. It sets the agent's unsaved work aside and continues with Option B. To get the work back later, switch to the branch the script names, then `git stash pop`. |
| Option A **Build and test** is red | Their agent's code. Ask the agent to fix it, or switch to Option B. |
| A script says a push was refused | Run the same command again: the scripts push anything that didn't make it. |
| A script says the branch on GitHub has a change the codespace doesn't have | The github.com edit (or another codespace) already got there: check the PR. To make the codespace match GitHub, the facilitator runs `git fetch && git reset --hard origin/<branch>` there, which throws away that codespace's unpushed commits. |
| `use-example-change.sh` can't download the example | Wi-Fi. It needs to reach github.com. Hotspot, or pair up. |
| Actions queued for minutes (GitHub incident) | Check <https://www.githubstatus.com>. Switch to your projector demo copy, which has each state already run. |
| Venue Wi-Fi fails | Phone hotspot for the projector machine; play the recorded walkthrough; keep the discussion going. |

## Before the workshop

**By Mon Sep 28**
- [ ] Publish the template repo: public, **Settings → Template repository** ✅.
- [ ] Run `bash facilitator/verify-lab.sh`. It must end with `ALL CHECKS PASSED`.
- [ ] **Dry run by someone other than Scott**, on a fresh GitHub account, using only
      LAB.md. **Pass bar: under 40 minutes.** Record the time, where they got stuck,
      and screenshots. Also record:
  - where the first terminal appears, and whether it's ready to type in;
  - whether pushing the step-3 workflow edit from the Codespace works;
  - one Copilot Free agent-mode run inside the Codespace (the $0 path is
    documented, but Free-in-Codespaces hasn't been tested end to end). Note
    whether the agent read LAB.md or `facilitator/` and added an ownership check
    on its own (which would blunt step 4), and whether Build and test came up green.

**By Tue Sep 29**
- [ ] Send [SETUP-EMAIL.md](SETUP-EMAIL.md) (after the dry run passes). After this,
      **freeze `main` and the three example branches**: add a ruleset on all four
      with **Restrict updates**, **Restrict deletions** and **Block force pushes**,
      and no bypass list. Attendees make their copy in advance, a copy doesn't pick
      up later changes, and the step-2 script checks the example against hashes
      pinned in that copy, so even an ordinary push to `agent-output-example` would
      break step 2. Unfreezing means deliberately disabling the ruleset, and it
      triggers the second-copy plan in the setup email notes.

**Oct 2 (day before)**
- [ ] Re-run `verify-lab.sh`. Semgrep downloads its `p/default` rules at run time,
      so a rule change on semgrep.dev could change what's caught.
- [ ] Check the published branches are the tested ones (no output means they match):
      ```bash
      git fetch origin && for b in main agent-output-example agent-output-after-gates reference-solution; do
        [ "$(git rev-parse --verify --quiet "refs/heads/$b")" = "$(git rev-parse --verify --quiet "origin/$b")" ] ||
          echo "$b DIFFERS (or is missing here or on GitHub)"
      done
      ```
- [ ] In a demo copy of your own, run the whole lab as Option B and leave the PR
      red. Set up the step-4 projector recipe above. Those are your fallbacks.
- [ ] Record a short screen capture of the full lab (last-resort fallback).
- [ ] Charge the phone hotspot.

**Maintenance (before the email only; after it, disable the freeze ruleset first
and treat any change as the second-copy plan).** The example branches are single commits
on top of `main`. If `main` changes, rebase them, re-check, and only then push. If
`app.py`, `db.py` or `tests/test_profile.py` change on the example branch, update
the pinned hashes in `scripts/use-example-change.sh` first (`git rev-parse
agent-output-example:app.py`, and so on); verify-lab fails until you do.
```bash
for b in agent-output-example agent-output-after-gates reference-solution; do
  git rebase main "$b" || break
done
git switch main && bash facilitator/verify-lab.sh &&
  git push --force-with-lease origin main agent-output-example agent-output-after-gates reference-solution
```

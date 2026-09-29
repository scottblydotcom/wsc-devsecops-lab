# Lab: Green Pipeline, Insecure Code

**45 minutes · 5 steps · nothing to install**

An AI agent adds a feature to a small app. The pipeline says ✅. Then you add
security gates and see what they catch, and what they still miss.

You need: a laptop, Chrome or Edge (Firefox and Safari mostly work), and your
GitHub account (email verified). Stuck at any point? Raise your hand.

---

## Step 1 · Get your own copy running (8 min)

Made your copy before the workshop (setup email)? Open it at
`github.com/YOUR-USERNAME/wsc-devsecops-lab` and start at item 2.

1. Open this link while signed in to GitHub:
   **[Create my copy of the lab](https://github.com/new?template_owner=scottblydotcom&template_name=wsc-devsecops-lab&name=wsc-devsecops-lab&visibility=public)**
   - Leave **Include all branches** unchecked.
   - Keep it **Public** (public repositories get free pipeline minutes).
   - Click **Create repository**.
2. On your new repository's page, click the green **Code** button, then the
   **Codespaces** tab, then **Create codespace on main**.
3. Wait about 2 minutes while a code editor opens in your browser. The panel at
   the bottom is the **terminal**. (No terminal? Press **Ctrl+`**, the key left of 1.)
   - If it asks whether you trust the authors of these files, click
     **Yes, I trust the authors**. The code has security bugs on purpose, but
     they're the kind attackers use against the running app, not against you.
     It all runs on a throwaway GitHub machine, not your laptop, and trusting
     it lets the editor's Python and Copilot tools work. Outside this lab, stop
     and think at that question: trusting a folder lets its files run code.
4. Click in the terminal, type this, and press Enter:
   ```bash
   python app.py
   ```
5. A pop-up says your application on port 5000 is available. Click
   **Open in Browser**. (Missed it? Click the **Ports** tab next to the terminal,
   then the globe icon on port 5000.)
6. You should see a line of text starting with `{"app":"Team Directory API`. It works!
   Leave that browser tab open.
7. Back in the Codespace, click in the terminal and press **Ctrl+C** to stop the
   app. (On a Mac this is **Ctrl** too, not Cmd.)

## Step 2 · Let an AI agent write a feature (10 min)

Your team asked for this:

> *Add an endpoint that returns a user's profile by ID, and connect it to our database.*

**Option A: you have an AI agent (for example GitHub Copilot).** Open its chat
(Copilot: **Ctrl+Alt+I**, or **Ctrl+Cmd+I** on a Mac), switch it to
**Agent** mode, paste the request above, and click **Keep** on the changes it
makes. (Copilot Free is enough: no trial or card needed.) Then run this in the
terminal:
```bash
bash scripts/save-my-change.sh
```

*Option A with Claude Code.* This is only for people who already pay for Claude
or have Claude API credits: Claude Code has no free version. Everyone else, use
Copilot Free or Option B.
1. Install it in the terminal:
   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   ```
   This is Anthropic's own installer. Piping a download straight into `bash`
   runs it unread: fine on this throwaway machine, but on your own computer,
   read the script first.
2. Type `claude` and press Enter. Log in when it shows a link.
3. Paste the request above, then add: *Don't commit or push. I'll do that.*
   (The lab's script puts your change on its own branch for a pull request.)
4. When it's done, type `/exit`, then run `bash scripts/save-my-change.sh`.

**Option B: everyone else, or if you'd rather follow along exactly.** This
applies a recorded example of what an AI agent might write for this request:
```bash
bash scripts/use-example-change.sh
```

**Then everyone:**

1. The script prints a link. Hold **Ctrl** (**Cmd** on a Mac) and click it. If
   the browser asks, allow it to open the site.
2. Click **Create pull request**.
3. Scroll down to the checks. Within a couple of minutes **Build and test** turns ✅ green:
   lint passed, and every test in the `tests` folder passed, including the agent's.

🤔 **Would you merge this?** Answer with a show of hands, but **don't click Merge**:
the lab keeps using this pull request.

(Option A: if **Build and test** is ❌ red for you, that's your agent's code. Ask
your agent to fix it, run `bash scripts/save-my-change.sh` again, or switch to
Option B.)

## Step 3 · Turn on the security gates (12 min)

1. In the Codespace, press **Ctrl+P** (**Cmd+P** on a Mac), type
   `security-gates`, and press Enter to open the file.
2. Find the line that starts with `# pull_request:`. Click anywhere on it and press
   **Ctrl+/** (**Cmd+/** on a Mac). The `#` at the start disappears, so the line
   now starts with `pull_request:`. (The note later on that line keeps its `#`.
   That's fine.) That one line turns the gates on.
3. Save it to GitHub:
   ```bash
   bash scripts/save-my-change.sh
   ```
4. Go back to your pull request tab. New checks appear under **Security gates**.
   Option B: in a couple of minutes they turn ❌ red. (Option A: see the note below.)
5. Click **Details** next to a red check, then **Summary** at the top left, to see
   what each gate found and what it means. The **Files changed** tab of the pull
   request marks the exact lines too.

Trouble with the edit, or no **Security gates** checks after 3 minutes? Run
`bash scripts/turn-on-gates.sh`. It does steps 1 to 3 for you.

If you used your own agent (Option A), your gates may catch different things, or
nothing at all. Compare with a neighbor who used Option B.

## Step 4 · What did the gates miss? (8 min)

(Option A: your agent may have picked a different address for the profile page.
Before you start the app, run `grep -n "@app" app.py` in the terminal. Your
agent's address is the one that isn't `/`, `/login/...` or `/api/me`, for
example `/api/users/<int:user_id>`. In items 3 and 4, use that address, with
the `1` or `2` in place of the part in `< >`.)

1. In the terminal, start the app again. This time it's the agent's version:
   ```bash
   python app.py
   ```
2. In the app's browser tab, go to the address bar. Replace everything after
   `.app.github.dev` with `/login/alice` and press Enter. You're logged in as Alice.
   (Pretend this login checks a password. It doesn't, only to keep the lab short.)
3. Now go to `/api/users/1/profile`. That's Alice's own profile: fine.
4. Change the `1` to a `2`.

🤔 **Whose home address is that? Which check caught it? Who *should* have caught it?**

## Step 5 · Wrap up (2 min)

1. Stop the app: click in the terminal and press **Ctrl+C**.
2. Save your free Codespaces hours: go to <https://github.com/codespaces>, click
   **⋯** next to your codespace, and choose **Delete**. Your repository stays.

**Take-home challenges**
- Ask your agent to fix what the gates found. Does the code scan go green? The
  secret scan should stay red, because the key is still in the git history. In
  real life, the fix for a leaked key is a new key. If your agent got the secret
  scan to go green, look at what it changed: an agent editing its own gate is a
  finding too.
- Write the test the agent didn't write, for what you saw in step 4.
- Compare with the `reference-solution` branch of the
  [template repository](https://github.com/scottblydotcom/wsc-devsecops-lab/tree/reference-solution).

---

### If something goes wrong

| What you see | What to do |
|---|---|
| You typed a command and nothing happened | The app is still running in that terminal. Press **Ctrl+C**, then type the command again. |
| `Address already in use` | An older copy of the app is still running, with the old code. Close every terminal with its 🗑 trash-can icon, open a new one (**Ctrl+`**), and run `python app.py` again. |
| The pop-up for port 5000 never appeared | **Ports** tab next to the terminal → globe icon on port 5000 |
| A workflow says it's waiting for approval | Click it, then **Approve and run workflow**. It's your repository. |
| A script says your branch on GitHub has a change this codespace doesn't have | Your edit on github.com (or in another codespace) already reached GitHub. Check your pull request. |
| The push to GitHub was refused | Run the same command again. Still refused in step 3? Make the edit on github.com instead: on your repository page, pick your branch in the branch menu, open `.github/workflows/security-gates.yml`, click the ✏️ pencil, delete the `# ` before `pull_request:`, and click **Commit changes**. |
| You're in a brand-new codespace | The step 2 and step 3 scripts find your branch by themselves. Before step 4, run `bash scripts/use-example-change.sh` again (Option A: `git switch my-agent-change`). |
| The codespace stopped | It stops after 30 idle minutes. Click **Restart codespace**. |
| Anything else | Raise your hand, or pair up with a neighbor |

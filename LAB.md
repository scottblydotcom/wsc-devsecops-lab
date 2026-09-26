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
   **[Create my copy of the lab](https://github.com/new?template_owner=scottblydotcom&template_name=wsc-devsecops-lab&owner=@me&name=wsc-devsecops-lab&visibility=public)**
   - Leave **Include all branches** unchecked.
   - Keep it **Public** (public repositories get free pipeline minutes).
   - Click **Create repository**.
2. On your new repository's page, click the green **Code** button, then the
   **Codespaces** tab, then **Create codespace on main**.
3. Wait about 2 minutes. A code editor opens in your browser. The panel at the
   bottom is the **terminal**. Wait until it says `Lab ready`.
4. Click in the terminal, type this, and press Enter:
   ```bash
   python app.py
   ```
5. A pop-up says your application on port 5000 is available. Click
   **Open in Browser**. (Missed it? Click the **Ports** tab next to the terminal,
   then the globe icon on port 5000.)
6. You should see a line of text starting with `{"app":"Team Directory API`. It works!
   Leave that browser tab open.
7. Back in the Codespace, click in the terminal and press **Ctrl+C** to stop the app.

## Step 2 · Let an AI agent write a feature (10 min)

Your team asked for this:

> *Add an endpoint that returns a user's profile by ID, and connect it to our database.*

**Option A: you have an AI agent (for example GitHub Copilot).** Open its chat
(Copilot: **Ctrl+Alt+I**, or **Ctrl+Cmd+I** on a Mac), switch it to
**Agent** mode, paste the request above, and accept the changes it makes. Then
run this in the terminal:
```bash
bash scripts/save-my-change.sh
```

**Option B: everyone else, or if you'd rather follow along exactly.** This
applies a recorded example of what an AI agent might write for this request:
```bash
bash scripts/use-example-change.sh
```

**Then everyone:**

1. The script prints a link. Hold **Ctrl** (**Cmd** on a Mac) and click it. If
   the browser asks, allow it to open the site.
2. Click **Create pull request**.
3. Scroll down to the checks. Within a couple of minutes **Build and test** turns ✅ green.
   Lint passed. Every unit test passed, including the ones the agent wrote.

🤔 **Would you merge this?**

## Step 3 · Turn on the security gates (12 min)

1. In the Codespace, press **Ctrl+P** (**Cmd+P** on a Mac), type
   `security-gates`, and press Enter to open the file.
2. Find the line that starts with `# pull_request:`. Click anywhere on it and press
   **Ctrl+/** (**Cmd+/** on a Mac). The `#` disappears. That one line turns the gates on.
3. Save it to GitHub:
   ```bash
   bash scripts/save-my-change.sh
   ```
4. Go back to your pull request tab. New checks appear under **Security gates**.
   In a couple of minutes they turn ❌ red.
5. Click **Details** next to a red check, then **Summary** at the top left, to see
   what each gate found and what it means. The **Files changed** tab of the pull
   request marks the exact lines too.

Trouble with the edit? Run `bash scripts/turn-on-gates.sh` instead. It does
steps 1 to 3 for you.

If you used your own agent (Option A), your gates may catch different things, or
nothing at all. Compare with a neighbor who used Option B.

## Step 4 · What did the gates miss? (8 min)

1. In the terminal, start the app again. This time it's the agent's version:
   ```bash
   python app.py
   ```
2. In the app's browser tab, go to the address bar. Replace everything after
   `.app.github.dev` with `/login/alice` and press Enter. You're logged in as Alice.
3. Now go to `/api/users/1/profile`. That's Alice's own profile: fine.
4. Change the `1` to a `2`.

🤔 **Whose home address is that? Which check caught it? Who *should* have caught it?**

(Option A: your agent may have picked a different address for the profile page.
Look in `app.py` for the route it added.)

## Step 5 · Wrap up (2 min)

1. Stop the app: click in the terminal and press **Ctrl+C**.
2. Save your free Codespaces hours: go to <https://github.com/codespaces>, click
   **⋯** next to your codespace, and choose **Delete**. Your repository stays.

**Take-home challenges**
- Ask your agent to fix what the gates found. Do the gates go green? Is the app safe now?
- Write the test the agent didn't write: logged in as Alice, asking for Bob's
  profile should be refused (HTTP 403).
- Compare your fix with the `reference-solution` branch of the
  [template repository](https://github.com/scottblydotcom/wsc-devsecops-lab/tree/reference-solution).

---

### If something goes wrong

| What you see | What to do |
|---|---|
| A workflow says it's waiting for approval | Click it, then **Approve and run workflow**. It's your repository. |
| The pop-up for port 5000 never appeared | **Ports** tab next to the terminal → globe icon on port 5000 |
| `Address already in use` | The app is already running in another terminal. Use that one, or close it. |
| The codespace stopped | It stops after 30 idle minutes. Click **Restart codespace**. |
| You're in a brand-new codespace, after step 2 | Get back to your branch. Option B: run `bash scripts/use-example-change.sh` again. Option A: run `git switch my-agent-change` |
| Anything else | Raise your hand, or pair up with a neighbor |

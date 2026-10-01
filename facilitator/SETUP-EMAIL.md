# Setup email (for WSC to send attendees)

Send as soon as the fresh-account dry run passes (the workshop is Sat Oct 3). Facts below were
checked against GitHub, Anthropic, OpenAI and Google documentation on 2026-09-25.
Re-check the AI tool lines if the email goes out much later: free tiers changed
several times in 2026.

---

**Subject:** Saturday's DevSecOps workshop: 10 minutes of setup before you come

Hi everyone,

Saturday's workshop, "Intro to DevSecOps in an Agentic AI World" (Oct 3,
9am–12pm PT), ends with a 45-minute hands-on lab. You'll watch an AI agent add
a feature to a small app, then add security checks to its pipeline and see what
they catch. Everything runs in your web browser. **You don't need to install
anything or know how to code.**

Please do these three things before Saturday. They take about 10 minutes.

**1. Get a free GitHub account with a verified email.**
- New to GitHub: sign up at <https://github.com/signup>. GitHub emails you a
  code; type it on the sign-up page. Please use a real email address; disposable
  ones can't be verified.
- Already have an account: check that <https://github.com/settings/emails> shows
  your address as **Verified**.

Without a verified email, GitHub won't let you do the lab's first step.

**2. Make your copy of the lab, and check it opens.**
While signed in to GitHub, open this link:
<https://github.com/new?template_owner=scottblydotcom&template_name=wsc-devsecops-lab&name=wsc-devsecops-lab&visibility=public>
- Click **Create repository**.
- On the page that opens, click the green **Code** button → **Codespaces** tab →
  **Create codespace on main**.
- After about 2 minutes, a code editor opens in your browser. That means it works.
- If it asks whether you trust the authors of the files, click **Yes, I trust
  the authors**. The lab code has security bugs on purpose, but it runs on a
  throwaway GitHub machine, not your laptop. The lab guide explains why it's safe.
- Then clean up: go to <https://github.com/codespaces>, click **⋯** next to it,
  and choose **Delete**. Your copy of the lab stays; you'll open a fresh
  codespace on Saturday.

This uses GitHub Codespaces, which is free for personal accounts: 60 hours a
month on the standard machine. The lab uses about one. **Don't add a payment
method.** With no card on file, GitHub stops usage at the free limit rather
than charging you.

If anything in step 2 fails, reply to this email with a screenshot and we'll
sort it out before Saturday.

**3. Optional: an AI coding assistant.**
You'll get the most out of the lab with an AI agent, but you don't need one.
The lab includes a recorded example, and you can pair up with a neighbor.

- **Free option: GitHub Copilot Free.** Turn it on at
  <https://github.com/settings/copilot> ("Start using Copilot Free"). It
  includes agent mode, with a limited monthly allowance that resets on the 1st.
  If your GitHub account already has Copilot through an employer, you'll use
  that instead, under your employer's rules.
- **Claude Code**, if you already pay for Claude (a Pro, Max, Team or Enterprise
  plan, or API credits): the lab guide has steps to set it up. It has no free
  version, so there's no need to sign up for it. If it gives you trouble, the
  recorded example is the backup.
- **OpenAI Codex** isn't set up for the lab environment yet. If it's your tool,
  use the recorded example or pair up with a neighbor.
- **Gemini Code Assist's free tier ended in June 2026.** Older tutorials that
  call it free are out of date.

**On the day, bring:** a charged laptop with an up-to-date Chrome or Edge.
Firefox and Safari mostly work. A personal laptop is best: work laptops and
VPNs sometimes block the connection Codespaces needs.

See you Saturday!
Scott Bly

---

### Notes for the sender (not part of the email)

- Step 2 has attendees create their copy early. That surfaces account problems
  before the day, but a copy doesn't pick up later changes to the template.
  **Freeze `main` and the three example branches once this is sent.** If a fix is
  unavoidable, tell attendees to make a second copy with the same link, named
  `wsc-devsecops-lab-2`.
- If the dry run confirms Copilot Free agent mode inside a Codespace, you can
  strengthen "Free option" to "Free, and tested in the lab environment".
- Claims and sources:
  - Codespaces: 120 core-hours/month on GitHub Free = 60 h on 2-core; resets on
    the 1st; with no payment method, usage is blocked at the quota. Source: GitHub
    Docs, "About billing for GitHub Codespaces".
  - Verified email needed to create repos, PRs and use Actions. Source: GitHub Docs,
    "Email addresses reference". New sign-ups verify with an emailed launch code.
  - Actions: free for public repositories on standard runners; 2,000 minutes/month
    for private repos on GitHub Free. Source: GitHub Docs, "GitHub Actions billing".
  - Copilot Free includes agent mode; the allowance isn't published as a number.
    Source: GitHub Docs, "Plans for GitHub Copilot". Copilot works in Codespaces
    per GitHub Docs; **Free-in-Codespaces is not yet tested end to end** (dry run item).
  - Claude Code: "requires a Pro, Max, Team, Enterprise, or Console account".
    Source: Claude Code setup docs. LAB.md step 2 has its Codespace steps (native
    installer); added 2026-09-29 at a dry-run tester's request, being tested in
    that tester's run.
  - Codex: the dry-run tester reported `npm install -g` failing in the Codespace
    (the image appears to have no Node.js; not independently checked), and no
    other install route has been tested. Hence "not set up yet".
  - Gemini Code Assist for individuals stopped serving June 18, 2026. Source: Google
    deprecation notice.

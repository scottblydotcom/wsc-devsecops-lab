# WSC DevSecOps Lab: Team Directory API

> [!WARNING]
> **Intentionally vulnerable training code. Do not deploy it.**
> It runs only inside your own GitHub Codespace. Nothing here deploys anywhere.

Hands-on lab for **"Intro to DevSecOps in an Agentic AI World"**, presented at the
Women's Society of Cyberjutsu (WSC) SoCal Chapter, October 3, 2026.

An AI agent writes code, the pipeline goes green, and the code is still insecure.
Then we add security gates that catch it, and look at what the gates *still* miss.

## Attendees: start here → [LAB.md](LAB.md)

You need a laptop, a web browser, and a free GitHub account. Nothing to install.

## What's inside

| Path | What it is |
|---|---|
| `app.py`, `db.py` | The Team Directory API: a tiny Flask app with a SQLite database of made-up people |
| `tests/` | Unit tests (pytest) |
| `.github/workflows/build-test.yml` | Pipeline stage 1: lint and unit tests. On from the start |
| `.github/workflows/security-gates.yml` | Pipeline stage 2: secret scan (gitleaks) and code scan (Semgrep). **Off** until lab step 3 |
| `.devcontainer/` | Makes the repo open ready to run in GitHub Codespaces |
| `scripts/` | One-command helpers for the lab steps |
| `AGENTS.md`, `CLAUDE.md` | Instructions that AI coding agents read before they change this code |
| `facilitator/` | Facilitator guide, setup email, and a self-check for the lab |

## How this repo practices what the lab teaches

- The pipeline's token is **least privilege** (`permissions: contents: read`). Your CI is an identity too.
- Third-party actions and container images are **pinned to exact commits and digests**, not tags that can move.
- Workflows run on `pull_request`, never `pull_request_target`, and need no repository secrets.
- There are no real secrets anywhere. The planted one on the example branch is a made-up lab value.

## License

MIT. See [LICENSE](LICENSE).

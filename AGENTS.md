# Notes for AI coding agents

This repository is the Team Directory API, a small Flask app used in a
DevSecOps training lab.

- `app.py` has the routes. `db.py` has the SQLite database code.
- Tests live in `tests/`. Run them with `python -m pytest`.
- Lint with `ruff check .`
- Start the app with `python app.py`. It serves on http://127.0.0.1:5000
- Keep changes small and follow the existing style.
- Add tests for any new endpoint.
- Before you finish, run `ruff check --fix .` and `python -m pytest`. Both must pass.

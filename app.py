"""Team Directory API: a tiny Flask app for the WSC DevSecOps lab.

TRAINING CODE. Run it inside your Codespace only. Never deploy it.
"""

import os
from functools import wraps
from pathlib import Path

from flask import Flask, abort, jsonify, session

import db

app = Flask(__name__)
# Use a fixed key so logins survive the debug reloader.
# In production, set SECRET_KEY in the environment.
app.secret_key = os.environ.get("SECRET_KEY", "wsclab_sk_3f9a1c7e5b2d4f6a8c0e1b3d5f7a9c2e")
app.config["DATABASE"] = os.environ.get(
    "DATABASE", str(Path(__file__).with_name("directory.db"))
)
app.teardown_appcontext(db.close_db)


def login_required(view):
    """Answer 401 Unauthorized unless someone is logged in."""

    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            abort(401)
        return view(*args, **kwargs)

    return wrapped


@app.get("/")
def index():
    return jsonify(
        app="Team Directory API (WSC DevSecOps lab)",
        logged_in_as=session.get("username"),
        try_these=["/login/alice", "/api/me", "/api/users/1/profile"],
    )


@app.get("/login/<username>")
def login(username):
    """Demo login with no password, so the lab can stay focused on the pipeline."""
    user = db.find_user(username)
    if user is None:
        abort(404)
    session["user_id"] = user["id"]
    session["username"] = user["username"]
    return jsonify(logged_in_as=user["username"], user_id=user["id"])


@app.get("/api/me")
@login_required
def me():
    return jsonify(user_id=session["user_id"], username=session["username"])


@app.get("/api/users/<user_id>/profile")
@login_required
def user_profile(user_id):
    """Return a user's profile by ID."""
    profile = db.get_profile(user_id)
    if profile is None:
        abort(404)
    return jsonify(profile)


if __name__ == "__main__":
    db.init_db(app.config["DATABASE"])
    app.run(host="127.0.0.1", port=5000, debug=True)

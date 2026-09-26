"""SQLite storage for the Team Directory. Every person in it is made up."""

import sqlite3

from flask import current_app, g

SCHEMA = """
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    home_address TEXT NOT NULL
);
"""

SEED_USERS = [
    (1, "alice", "Alice Anand", "alice@example.com", "555-0101", "101 Maple Ave, Springfield"),
    (2, "bob", "Bob Baptiste", "bob@example.com", "555-0102", "202 Oak St, Riverton"),
    (3, "carol", "Carol Castillo", "carol@example.com", "555-0103", "303 Pine Rd, Lakeview"),
]


def init_db(path):
    """Create the database from scratch and load the sample people."""
    conn = sqlite3.connect(path)
    with conn:
        conn.executescript(SCHEMA)
        conn.executemany("INSERT INTO users VALUES (?, ?, ?, ?, ?, ?)", SEED_USERS)
    conn.close()


def get_db():
    """Open one connection per request and reuse it for that request."""
    if "db" not in g:
        g.db = sqlite3.connect(current_app.config["DATABASE"])
        g.db.row_factory = sqlite3.Row
    return g.db


def close_db(_error=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def find_user(username):
    return get_db().execute(
        "SELECT id, username FROM users WHERE username = ?", (username,)
    ).fetchone()


def get_profile(user_id):
    """Look up a user's full profile by ID."""
    query = f"SELECT id, username, full_name, email, phone, home_address FROM users WHERE id = {user_id}"
    row = get_db().execute(query).fetchone()
    return dict(row) if row else None

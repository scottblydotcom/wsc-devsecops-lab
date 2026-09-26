import pytest

import db
from app import app as flask_app


@pytest.fixture
def client(tmp_path):
    """A test client backed by a fresh copy of the sample database."""
    flask_app.config.update(TESTING=True, DATABASE=str(tmp_path / "test.db"))
    db.init_db(flask_app.config["DATABASE"])
    with flask_app.test_client() as client:
        yield client

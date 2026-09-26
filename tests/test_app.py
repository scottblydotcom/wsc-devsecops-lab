def test_home_page_works(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["logged_in_as"] is None


def test_login_as_a_known_user(client):
    response = client.get("/login/alice")
    assert response.status_code == 200
    assert response.get_json() == {"logged_in_as": "alice", "user_id": 1}


def test_login_as_an_unknown_user_is_rejected(client):
    assert client.get("/login/mallory").status_code == 404


def test_me_requires_login(client):
    assert client.get("/api/me").status_code == 401


def test_me_shows_who_is_logged_in(client):
    client.get("/login/bob")
    response = client.get("/api/me")
    assert response.status_code == 200
    assert response.get_json() == {"user_id": 2, "username": "bob"}

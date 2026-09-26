"""Tests for the user profile endpoint."""


def login(client, username="alice"):
    return client.get(f"/login/{username}")


def test_profile_requires_login(client):
    response = client.get("/api/users/1/profile")
    assert response.status_code == 401


def test_get_profile_returns_user_details(client):
    login(client)
    response = client.get("/api/users/1/profile")
    assert response.status_code == 200
    data = response.get_json()
    assert data["username"] == "alice"
    assert data["email"] == "alice@example.com"
    assert data["home_address"] == "101 Maple Ave, Springfield"


def test_get_profile_not_found(client):
    login(client)
    response = client.get("/api/users/999/profile")
    assert response.status_code == 404

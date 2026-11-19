import pytest

from app.main import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_index_returns_message(client):
    res = client.get("/")
    assert res.status_code == 200
    assert "message" in res.get_json()


def test_health_is_ok(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok"}


def test_add_numbers(client):
    res = client.get("/add/2/3")
    assert res.status_code == 200
    assert res.get_json() == {"result": 5}


def test_unknown_route_is_404(client):
    assert client.get("/nope").status_code == 404

"""Unit tests for the contact-form app using an in-memory fake database.

These run without a real PostgreSQL instance so they are fast and CI-friendly.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import app as app_module  # noqa: E402


class FakeDB:
    def __init__(self, healthy=True):
        self.rows = []
        self.healthy = healthy
        self._id = 0

    def init_schema(self):
        pass

    def ensure_schema(self):
        if not self.healthy:
            raise RuntimeError("db down")

    def ping(self):
        if not self.healthy:
            raise RuntimeError("db down")

    def insert(self, name, email, message):
        self._id += 1
        self.rows.append(
            {"id": self._id, "name": name, "email": email, "message": message}
        )
        return self._id

    def recent(self, limit=25):
        return list(reversed(self.rows))[:limit]


@pytest.fixture
def client():
    db = FakeDB()
    app = app_module.create_app(db=db)
    app.config.update(TESTING=True, SECRET_KEY="test")
    with app.test_client() as c:
        c._db = db
        yield c


def test_index_renders(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"Contact Us" in r.data


def test_healthz_ok(client):
    assert client.get("/healthz").status_code == 200


def test_readyz_ok(client):
    assert client.get("/readyz").status_code == 200


def test_readyz_reports_db_failure():
    db = FakeDB(healthy=False)
    app = app_module.create_app(db=db)
    with app.test_client() as c:
        assert c.get("/readyz").status_code == 503


def test_valid_submission_is_stored(client):
    r = client.post(
        "/contact",
        data={"name": "Ada", "email": "ada@example.com", "message": "hello"},
        follow_redirects=True,
    )
    assert r.status_code == 200
    assert len(client._db.rows) == 1
    assert client._db.rows[0]["email"] == "ada@example.com"


def test_missing_fields_rejected(client):
    client.post("/contact", data={"name": "", "email": "", "message": ""})
    assert len(client._db.rows) == 0


def test_invalid_email_rejected(client):
    client.post(
        "/contact",
        data={"name": "Bob", "email": "not-an-email", "message": "hi"},
    )
    assert len(client._db.rows) == 0


def test_submissions_endpoint_returns_json(client):
    client.post(
        "/contact",
        data={"name": "Ada", "email": "ada@example.com", "message": "hello"},
    )
    r = client.get("/submissions")
    assert r.status_code == 200
    assert r.json["submissions"][0]["name"] == "Ada"

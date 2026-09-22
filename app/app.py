"""
Contact Form application (two-tier: Flask + PostgreSQL).

Twelve-factor: all configuration comes from the environment so the exact same
image runs unchanged on a local RKE2 cluster and on AWS EKS. Database
credentials are injected from a Kubernetes Secret, never baked into the image.
"""
import logging
import os
from contextlib import contextmanager

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("contact-app")


def _db_config():
    return {
        "host": os.getenv("DB_HOST", "postgres"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME", "contacts"),
        "user": os.getenv("DB_USER", "contact"),
        "password": os.getenv("DB_PASSWORD", ""),
        "connect_timeout": int(os.getenv("DB_CONNECT_TIMEOUT", "5")),
    }


class Database:
    """Lazily-initialised connection pool so the pod can start (and pass its
    liveness probe) even if the database is briefly unavailable."""

    def __init__(self):
        self._pool = None
        self._schema_ready = False

    def _ensure_pool(self):
        if self._pool is None:
            cfg = _db_config()
            self._pool = pool.SimpleConnectionPool(1, 5, **cfg)
            log.info("Initialised connection pool to %s:%s/%s",
                     cfg["host"], cfg["port"], cfg["dbname"])
        return self._pool

    @contextmanager
    def connection(self):
        pool_ = self._ensure_pool()
        conn = pool_.getconn()
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            pool_.putconn(conn)

    def init_schema(self):
        with self.connection() as conn, conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS submissions (
                    id         SERIAL PRIMARY KEY,
                    name       VARCHAR(120) NOT NULL,
                    email      VARCHAR(255) NOT NULL,
                    message    TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                );
                """
            )
        log.info("Schema ensured")

    def ensure_schema(self):
        """Create the schema once, retried until it succeeds. This makes the app
        self-healing: if the pod starts before PostgreSQL is reachable, the first
        few readiness probes fail, then the schema is created the moment the DB
        comes up -- no manual restart or migration job needed."""
        if self._schema_ready:
            return
        self.init_schema()
        self._schema_ready = True

    def ping(self):
        with self.connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()

    def insert(self, name, email, message):
        self.ensure_schema()
        with self.connection() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO submissions (name, email, message) "
                "VALUES (%s, %s, %s) RETURNING id;",
                (name, email, message),
            )
            return cur.fetchone()[0]

    def recent(self, limit=25):
        self.ensure_schema()
        with self.connection() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id, name, email, message, created_at "
                "FROM submissions ORDER BY created_at DESC LIMIT %s;",
                (limit,),
            )
            return cur.fetchall()


def create_app(db=None):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = os.getenv("FLASK_SECRET_KEY", os.urandom(32).hex())
    database = db or Database()

    # Best-effort schema init; don't crash the process if the DB isn't up yet.
    # The readiness probe (/readyz) will finish the job once the DB is reachable.
    try:
        database.ensure_schema()
    except Exception as exc:  # pragma: no cover - startup race
        log.warning("Deferred schema init (db not ready yet): %s", exc)

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.post("/contact")
    def contact():
        name = (request.form.get("name") or "").strip()
        email = (request.form.get("email") or "").strip()
        message = (request.form.get("message") or "").strip()

        if not name or not email or not message:
            flash("All fields are required.", "error")
            return redirect(url_for("index"))
        if "@" not in email or len(email) > 255:
            flash("Please provide a valid email address.", "error")
            return redirect(url_for("index"))
        if len(name) > 120 or len(message) > 5000:
            flash("Input too long.", "error")
            return redirect(url_for("index"))

        try:
            new_id = database.insert(name, email, message)
        except Exception as exc:
            log.exception("Failed to store submission")
            flash("Sorry, we could not save your message. Try again later.", "error")
            return redirect(url_for("index"))

        log.info("Stored submission id=%s", new_id)
        flash("Thanks! Your message has been received.", "success")
        return redirect(url_for("index"))

    @app.get("/submissions")
    def submissions():
        try:
            rows = database.recent()
        except Exception:
            log.exception("Failed to list submissions")
            return jsonify(error="database unavailable"), 503
        return jsonify(submissions=rows)

    # Liveness: process is up and serving.
    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok"), 200

    # Readiness: dependencies (DB) reachable.
    @app.get("/readyz")
    def readyz():
        try:
            database.ensure_schema()   # idempotent; creates table on first success
            database.ping()
        except Exception as exc:
            return jsonify(status="not-ready", error=str(exc)), 503
        return jsonify(status="ready"), 200

    return app


# WSGI entrypoint used by gunicorn (see Dockerfile CMD).
app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))

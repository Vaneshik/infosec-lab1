import os
import sqlite3
from datetime import datetime, timedelta, timezone
from functools import wraps
from html import escape

import click
import jwt
from flask import Flask, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash


def db():
    if "db" not in g:
        g.db = sqlite3.connect(os.environ.get("NOTES_DB", "notes.sqlite3"))
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


def json_text(key):
    body = request.get_json(silent=True)
    value = body.get(key) if isinstance(body, dict) else None
    return value if isinstance(value, str) else ""


def create_app():
    app = Flask(__name__)
    signing_key = os.environ["JWT_SECRET"]
    if len(signing_key.encode()) < 32:
        raise ValueError("JWT_SECRET must contain at least 32 bytes")

    @app.teardown_appcontext
    def close_db(error):
        connection = g.pop("db", None)
        if connection is not None:
            connection.close()

    @app.cli.command("create-user")
    @click.argument("login")
    @click.password_option()
    def create_user(login, password):
        connection = db()
        connection.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY, login TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY, owner INTEGER NOT NULL REFERENCES users(id), text TEXT NOT NULL
            );
        """)
        try:
            with connection:
                connection.execute(
                    "INSERT INTO users (login, password_hash) VALUES (?, ?)",
                    (login, generate_password_hash(password, method="scrypt")),
                )
        except sqlite3.IntegrityError as exc:
            raise click.ClickException("Login already exists") from exc
        click.echo("User created")

    @app.post("/auth/login")
    def login():
        username = json_text("login")
        password = json_text("password")
        if not username or not password:
            return {"error": "login and password required"}, 400
        user = db().execute(
            "SELECT id, password_hash FROM users WHERE login = ?", (username,)
        ).fetchone()
        if not user or not check_password_hash(user["password_hash"], password):
            return {"error": "invalid credentials"}, 401
        token = jwt.encode(
            {"sub": str(user["id"]), "exp": datetime.now(timezone.utc) + timedelta(minutes=30)},
            signing_key,
            algorithm="HS256",
        )
        return {"token": token}

    def authenticated(view):
        @wraps(view)
        def wrapped():
            scheme, _, token = request.headers.get("Authorization", "").partition(" ")
            if scheme.lower() != "bearer" or not token:
                return {"error": "bearer token required"}, 401
            try:
                claims = jwt.decode(
                    token, signing_key, algorithms=["HS256"], options={"require": ["sub", "exp"]}
                )
            except jwt.InvalidTokenError:
                return {"error": "invalid token"}, 401
            g.owner = claims["sub"]
            return view()

        return wrapped

    @app.get("/api/data")
    @authenticated
    def list_notes():
        rows = db().execute("SELECT id, text FROM notes WHERE owner = ? ORDER BY id", (g.owner,))
        return jsonify([{"id": row["id"], "text": escape(row["text"])} for row in rows])

    @app.post("/api/data")
    @authenticated
    def add_note():
        text = json_text("text")
        if not text.strip():
            return {"error": "text required"}, 400
        with db() as connection:
            note = connection.execute("INSERT INTO notes (owner, text) VALUES (?, ?)", (g.owner, text))
        return {"id": note.lastrowid}, 201

    return app

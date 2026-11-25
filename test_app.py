import os
import secrets
import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import jwt

from app import create_app


class NotesTest(unittest.TestCase):
    def setUp(self):
        directory = self.enterContext(tempfile.TemporaryDirectory())
        self.database = str(Path(directory) / "notes.sqlite3")
        self.key = secrets.token_hex(32)
        self.enterContext(patch.dict(os.environ, NOTES_DB=self.database, JWT_SECRET=self.key))
        app = create_app()
        self.client = app.test_client()
        self.password = secrets.token_urlsafe(16)
        for username in ("alice", "bob"):
            result = app.test_cli_runner().invoke(
                args=["create-user", username], input=f"{self.password}\n{self.password}\n"
            )
            self.assertEqual(result.exit_code, 0, result.output)

    def login(self, username):
        response = self.client.post("/auth/login", json={"login": username, "password": self.password})
        self.assertEqual(response.status_code, 200)
        return {"Authorization": "Bearer " + response.json["token"]}

    def test_notes_are_private_and_text_is_escaped_once(self):
        alice, bob = self.login("alice"), self.login("bob")
        response = self.client.post("/api/data", headers=alice, json={"text": "O'Brien <чай> & кофе"})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.client.get("/api/data", headers=bob).json, [])
        self.assertEqual(
            self.client.get("/api/data", headers=alice).json,
            [{"id": response.json["id"], "text": "O&#x27;Brien &lt;чай&gt; &amp; кофе"}],
        )

    def test_both_methods_reject_missing_expired_and_wrongly_signed_tokens(self):
        now = datetime.now(timezone.utc)
        expired = jwt.encode({"sub": "1", "exp": now - timedelta(minutes=1)}, self.key, algorithm="HS256")
        wrong_key = jwt.encode(
            {"sub": "1", "exp": now + timedelta(minutes=30)}, secrets.token_hex(32), algorithm="HS256"
        )
        for kind, token in (("missing", None), ("expired", expired), ("wrong key", wrong_key)):
            headers = {"Authorization": f"Bearer {token}"} if token else {}
            for method in ("GET", "POST"):
                with self.subTest(method=method, token_kind=kind):
                    response = self.client.open("/api/data", method=method, headers=headers, json={"text": "x"})
                    self.assertEqual(response.status_code, 401)
        self.assertEqual(self.client.get("/api/data", headers=self.login("alice")).json, [])

    def test_wrong_password_and_unknown_login(self):
        for username, password in (("alice", "wrong"), ("d'angelo", self.password)):
            response = self.client.post("/auth/login", json={"login": username, "password": password})
            self.assertEqual(response.status_code, 401)
        with closing(sqlite3.connect(self.database)) as connection:
            stored, = connection.execute("SELECT password_hash FROM users WHERE login = 'alice'").fetchone()
        self.assertTrue(stored.startswith("scrypt:"))
        self.assertNotIn(self.password, stored)

    def test_invalid_note_is_not_saved(self):
        headers = self.login("bob")
        for body in ({}, {"text": " "}, {"text": 5}, ["note"]):
            self.assertEqual(self.client.post("/api/data", headers=headers, json=body).status_code, 400)
        self.assertEqual(self.client.get("/api/data", headers=headers).json, [])

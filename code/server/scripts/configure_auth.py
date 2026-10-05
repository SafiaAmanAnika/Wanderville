"""Configure local auth without exposing secrets in shell history or output.

Run from code/server: python scripts/configure_auth.py --google-json PATH
Optional: --gmail, --brevo or --gmail-api. This never changes DATABASE_URL.

--gmail-api performs a one-time installed-app consent on a loopback port to
obtain a refresh token for https://www.googleapis.com/auth/gmail.send. That
grant belongs to the sender mailbox only and is unrelated to player sign-in.
"""
import argparse
import base64
import getpass
import hashlib
import json
import os
import secrets
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

import requests
from dotenv import set_key


def _exchange_gmail_code(values, code, verifier, redirect_uri):
    response = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": values["GMAIL_CLIENT_ID"],
            "client_secret": values["GMAIL_CLIENT_SECRET"],
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
        },
        timeout=15,
    )
    response.raise_for_status()
    payload = response.json()
    if not payload.get("refresh_token"):
        raise SystemExit(
            "Google returned no refresh token. Revoke the app's access at "
            "myaccount.google.com/permissions, delete .dev-mail grants if any, "
            "then rerun with --gmail-api."
        )
    values["GMAIL_REFRESH_TOKEN"] = payload["refresh_token"]


def _capture_loopback_code(values, state):
    """Serve one callback on 127.0.0.1 and return the authorization code."""
    received = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            query = parse_qs(urlparse(self.path).query)
            received["code"] = (query.get("code") or [""])[0]
            received["state"] = (query.get("state") or [""])[0]
            received["error"] = (query.get("error") or [""])[0]
            body = b"<p>WanderVille is done. You can close this tab.</p>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            return

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    redirect_uri = f"http://127.0.0.1:{port}/oauth/callback"
    scope = "https://www.googleapis.com/auth/gmail.send"
    verifier = (
        base64.urlsafe_b64encode(secrets.token_bytes(48)).decode().rstrip("=")
    )
    challenge = (
        base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode()).digest()
        )
        .decode()
        .rstrip("=")
    )
    query = urlencode(
        {
            "client_id": values["GMAIL_CLIENT_ID"],
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": scope,
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            # Without access_type=offline and a fresh consent, Google may answer
            # with an access token only and no refresh token.
            "access_type": "offline",
            "prompt": "consent",
        }
    )
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    authorize = f"https://accounts.google.com/o/oauth2/v2/auth?{query}"
    print(f"Approve mail sending in the browser that opens.\n{authorize}")
    webbrowser.open(authorize)
    thread.join(timeout=180)
    server.server_close()
    if not received.get("code"):
        raise SystemExit("No authorization code was returned; nothing was written.")
    if received.get("state") != state:
        raise SystemExit("Authorization state did not match; nothing was written.")
    return received["code"], verifier, redirect_uri


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--google-json", type=Path)
    email = parser.add_mutually_exclusive_group()
    email.add_argument("--gmail", action="store_true")
    email.add_argument("--brevo", action="store_true")
    email.add_argument("--gmail-api", action="store_true")
    args = parser.parse_args()
    values = {}
    if args.google_json:
        data = json.loads(args.google_json.read_text(encoding="utf-8"))
        client = data.get("installed", {})
        if not client.get("client_id", "").endswith(".apps.googleusercontent.com"):
            parser.error("Download a Desktop app OAuth client JSON (not a Web application client).")
        values["GOOGLE_CLIENT_ID"] = client["client_id"]
        values["GOOGLE_CLIENT_SECRET"] = client.get("client_secret", "")
    if args.gmail or args.brevo or args.gmail_api:
        sender = input("Verified sender email address: ").strip()
        if "@" not in sender or any(c in sender for c in "\r\n"):
            parser.error("Enter a valid sender email address.")
        values["EMAIL_FROM"] = sender
        if args.gmail:
            password = getpass.getpass("Google app password (hidden, not your normal password): ").replace(" ", "")
            if len(password) != 16:
                parser.error("Google app passwords contain 16 characters.")
            values.update(EMAIL_DELIVERY="smtp", SMTP_HOST="smtp.gmail.com", SMTP_PORT="587", SMTP_STARTTLS="true", SMTP_USER=sender, SMTP_PASSWORD=password)
        elif args.brevo:
            key = getpass.getpass("Brevo API key (hidden): ").strip()
            if not key:
                parser.error("API key cannot be empty.")
            values.update(EMAIL_DELIVERY="brevo", BREVO_API_KEY=key)
        else:
            values["GMAIL_SENDER_EMAIL"] = sender
            values["GMAIL_CLIENT_ID"] = os.getenv("GOOGLE_CLIENT_ID", "").strip() or input(
                "OAuth client ID (.apps.googleusercontent.com): "
            ).strip()
            values["GMAIL_CLIENT_SECRET"] = os.getenv(
                "GOOGLE_CLIENT_SECRET", ""
            ).strip() or getpass.getpass("OAuth client secret (hidden): ").strip()
            if not values["GMAIL_CLIENT_ID"].endswith(".apps.googleusercontent.com"):
                parser.error("Use the Desktop app OAuth client from section 1.")
            code, verifier, redirect_uri = _capture_loopback_code(
                values, secrets.token_urlsafe(32)
            )
            _exchange_gmail_code(values, code, verifier, redirect_uri)
            values["EMAIL_DELIVERY"] = "gmail_api"
    if not values:
        parser.error("Choose --google-json PATH, --gmail, --brevo or --gmail-api.")
    target = Path(__file__).resolve().parents[1] / ".env"
    for key, value in values.items():
        set_key(str(target), key, value, quote_mode="always")
    print("Updated local .env: " + ", ".join(values) + ". Restart the backend. No credentials were printed.")


if __name__ == "__main__":
    main()

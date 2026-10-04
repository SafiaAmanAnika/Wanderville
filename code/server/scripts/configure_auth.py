"""Configure local auth without exposing secrets in shell history or output.

Run from code/server: python scripts/configure_auth.py --google-json PATH
Optional: --gmail or --brevo. This deliberately never changes DATABASE_URL.
"""
import argparse
import getpass
import json
from pathlib import Path

from dotenv import set_key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--google-json", type=Path)
    email = parser.add_mutually_exclusive_group()
    email.add_argument("--gmail", action="store_true")
    email.add_argument("--brevo", action="store_true")
    args = parser.parse_args()
    values = {}
    if args.google_json:
        data = json.loads(args.google_json.read_text(encoding="utf-8"))
        client = data.get("installed", {})
        if not client.get("client_id", "").endswith(".apps.googleusercontent.com"):
            parser.error("Download a Desktop app OAuth client JSON (not a Web application client).")
        values["GOOGLE_CLIENT_ID"] = client["client_id"]
        values["GOOGLE_CLIENT_SECRET"] = client.get("client_secret", "")
    if args.gmail or args.brevo:
        sender = input("Verified sender email address: ").strip()
        if "@" not in sender or any(c in sender for c in "\r\n"):
            parser.error("Enter a valid sender email address.")
        values["EMAIL_FROM"] = sender
        if args.gmail:
            password = getpass.getpass("Google app password (hidden, not your normal password): ").replace(" ", "")
            if len(password) != 16:
                parser.error("Google app passwords contain 16 characters.")
            values.update(EMAIL_DELIVERY="smtp", SMTP_HOST="smtp.gmail.com", SMTP_PORT="587", SMTP_STARTTLS="true", SMTP_USER=sender, SMTP_PASSWORD=password)
        else:
            key = getpass.getpass("Brevo API key (hidden): ").strip()
            if not key:
                parser.error("API key cannot be empty.")
            values.update(EMAIL_DELIVERY="brevo", BREVO_API_KEY=key)
    if not values:
        parser.error("Choose --google-json PATH, --gmail, or --brevo.")
    target = Path(__file__).resolve().parents[1] / ".env"
    for key, value in values.items():
        set_key(str(target), key, value, quote_mode="always")
    print("Updated local .env: " + ", ".join(values) + ". Restart the backend. No credentials were printed.")


if __name__ == "__main__":
    main()

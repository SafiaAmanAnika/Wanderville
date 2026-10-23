import pytest
from app.core.config import settings
from app.core.exceptions import AppError
from app.modules.auth import oauth


def test_google_verification_has_bounded_clock_tolerance(monkeypatch):
    monkeypatch.setattr(settings, "google_client_id", "desktop-client")
    observed = {}
    def verify(raw, request, audience, **kwargs):
        observed.update(audience=audience, **kwargs)
        return {"sub": "google-user", "email": "user@gmail.com", "email_verified": True, "nonce": "expected"}
    monkeypatch.setattr(oauth.id_token, "verify_oauth2_token", verify)
    assert oauth.verify_google("signed-token", "expected").subject == "google-user"
    assert observed == {"audience": "desktop-client", "clock_skew_in_seconds": 30}
    with pytest.raises(AppError, match="session does not match"):
        oauth.verify_google("signed-token", "wrong-nonce")


@pytest.mark.parametrize("reason,expected", [
    ("Token used too early", "clock is behind"),
    ("Token expired", "expired"),
    ("Token has wrong audience", "client IDs do not match"),
    ("Could not verify token signature", "could not be verified"),
])
def test_google_failures_remain_rejected_with_actionable_messages(monkeypatch, caplog, reason, expected):
    monkeypatch.setattr(settings, "google_client_id", "desktop-client")
    def reject(*args, **kwargs):
        raise ValueError(reason + " signed-token")
    monkeypatch.setattr(oauth.id_token, "verify_oauth2_token", reject)
    with pytest.raises(AppError) as caught:
        oauth.verify_google("signed-token")
    assert caught.value.code == "INVALID_GOOGLE_TOKEN"
    assert caught.value.status == 401
    assert expected in caught.value.message
    assert "signed-token" not in caplog.text

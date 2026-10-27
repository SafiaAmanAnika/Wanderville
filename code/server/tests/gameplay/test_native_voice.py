"""Native Godot binary transport and shared authorization/mixing integration."""
import struct
import time
from contextlib import ExitStack

import pytest
from starlette.websockets import WebSocketDisconnect

from app.core.config import settings
from app.modules.realtime.runtime import runtime
from app.modules.realtime.native_voice import ingest
from app.modules.realtime.voice import MediaPeer


def command(ws, kind, data=None):
    request_id = "native_" + str(time.monotonic_ns())
    ws.send_json({"type": kind, "data": data or {}, "request_id": request_id})
    for _ in range(50):
        response = ws.receive_json()
        if response.get("request_id") == request_id:
            assert response["type"] != "error", response
            return response
    pytest.fail("No correlated acknowledgement")


def connect(stack, client, user, capabilities=None):
    ws = stack.enter_context(client.websocket_connect("/realtime/ws"))
    ws.send_json({"type": "auth", "protocol_version": 2, "token": user.tokens["access_token"]})
    initial = ws.receive_json()
    command(ws, "enter", {"location": "social_lobby"})
    joined = command(ws, "voice.join", {"transport": "pcm-websocket"})
    sid = joined["data"]["voice"]["session_id"]
    audio = stack.enter_context(client.websocket_connect("/realtime/voice/ws"))
    auth = {
        "type": "auth",
        "token": user.tokens["access_token"],
        "connection_id": initial["connection_id"],
        "session_id": sid,
    }
    if capabilities:
        auth["capabilities"] = list(capabilities)
    audio.send_json(auth)
    message = audio.receive_json()
    if message["type"] == "voice.format":
        # The server states the encoding it will use before any audio.
        message = audio.receive_json()
    assert message["type"] == "voice.connected"
    return ws, audio, sid


def receive_audio(ws, limit=20):
    """The next audio frame, stepping over keepalive messages."""
    for _ in range(limit):
        message = ws.receive()
        if message.get("bytes") is not None:
            return message["bytes"]
    pytest.fail("No audio frame arrived")


def test_native_audio_delivery_mute_block_and_no_control_takeover(client, account, monkeypatch):
    monkeypatch.setattr(settings, "voice_enabled", True)
    a, b = account("native_a"), account("native_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    tone = struct.pack("<960h", *([2000] * 960))
    with ExitStack() as stack:
        wa, aa, sa = connect(stack, client, a)
        wb, ab, _ = connect(stack, client, b)
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        audible = False
        for _ in range(12):
            aa.send_bytes(tone)
            raw = ab.receive_bytes()
            audible |= any(struct.unpack("<960h", raw))
            time.sleep(0.02)
        assert audible
        command(wa, "voice.state", {"session_id": sa, "muted": True})
        for _ in range(10):
            aa.send_bytes(tone)
            raw = ab.receive_bytes()
        assert not any(struct.unpack("<960h", raw))
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        assert client.post("/social/blocks", headers=b.headers, json={"target_id": a.id}).status_code == 200
        command(wa, "heartbeat")
        command(wb, "heartbeat")
        for _ in range(10):
            aa.send_bytes(tone)
            raw = ab.receive_bytes()
        assert not any(struct.unpack("<960h", raw))
        aa.close()
        assert command(wa, "heartbeat")["data"]["players"]


def test_native_silence_is_suppressed_for_capable_clients(client, account, monkeypatch):
    """A quiet room must cost nothing for a client that can live without it.

    The capable listener is told the room is quiet instead of being sent
    frames of silence, a client that did not declare the capability keeps
    receiving the frames it always received, and a speaker who is actually
    talking is still heard by both.
    """
    monkeypatch.setattr(settings, "voice_enabled", True)
    monkeypatch.setattr(settings, "voice_idle_keepalive_seconds", 0.2)
    a, b = account("native_quiet_a"), account("native_quiet_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    tone = struct.pack("<960h", *([2000] * 960))
    with ExitStack() as stack:
        wa, aa, sa = connect(stack, client, a)
        wb, ab, sb = connect(stack, client, b, capabilities=["silence_suppression"])
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        # The capable listener is told the room is quiet. It is not sent a
        # frame of silence: the keepalive is the only thing on the wire.
        keepalive = ab.receive_json()
        assert keepalive["type"] == "voice.idle"
        # A client that did not declare the capability keeps the frames it
        # always got, so a rollout cannot break a client that is installed.
        raw = receive_audio(aa)
        assert len(raw) == 1920
        assert not any(struct.unpack("<960h", raw))
        # A speaker who is talking is still heard by the capable listener.
        command(wb, "heartbeat")
        heard = False
        for _ in range(20):
            aa.send_bytes(tone)
            raw = receive_audio(ab)
            if any(struct.unpack("<960h", raw)):
                heard = True
                break
        assert heard


def test_native_requires_current_control_session_and_valid_origin(client, account, monkeypatch):
    monkeypatch.setattr(settings, "voice_enabled", True)
    user = account("native_denied")
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/realtime/voice/ws", headers={"origin": "https://evil.example"}):
            pass
    with client.websocket_connect("/realtime/voice/ws") as audio:
        audio.send_json({"type": "auth", "token": user.tokens["access_token"], "connection_id": "fake", "session_id": "fake"})
        with pytest.raises(WebSocketDisconnect):
            audio.receive_json()


def test_native_ingest_rejects_malformed_and_drops_muted_or_expired(monkeypatch):
    monkeypatch.setattr(settings, "voice_enabled", True)
    generation = runtime.attach(891)
    try:
        runtime.apply(891, generation, runtime.policy_revision(), {"room": "campus", "room_epoch": 1, "voice_privacy": "friends", "proximity_prompts": True, "nearby": []})
        sid = runtime.join(891, generation)
        peer = MediaPeer(891, generation, sid, None)
        with pytest.raises(ValueError):
            ingest(peer, b"bad")
        tone = struct.pack("<960h", *([2000] * 960))
        ingest(peer, tone)
        assert not peer.incoming
        runtime.state(891, generation, sid, False, False, [])
        ingest(peer, tone)
        assert len(peer.incoming) == 1
        runtime.invalidate({891})
        ingest(peer, tone)
        assert not peer.incoming
    finally:
        runtime.detach(891, generation)

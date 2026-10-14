"""Godot native PCM16 voice, separate from gameplay control traffic.

Wire format: little-endian signed PCM16, mono 48 kHz, exactly 960 samples
(20 ms / 1920 bytes) per binary message. WSS is required outside local dev.
No microphone is activated by this endpoint; clients explicitly join muted.
"""
import asyncio
import json
import sys
import time
from array import array

from fastapi import APIRouter, Depends, WebSocket
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from starlette.websockets import WebSocketDisconnect

from app.core.config import settings
from app.core.exceptions import AppError
from app.db.session import get_db
from app.modules.auth.service import AuthService
from app.modules.realtime.runtime import runtime
from app.modules.realtime.voice import MediaPeer, accept_incoming, voice_hub

router = APIRouter(prefix="/realtime/voice", tags=["realtime"])


class SocketMedia:
    def __init__(self, websocket):
        self.websocket = websocket
        self.closed = False

    async def close(self):
        if not self.closed:
            self.closed = True
            try:
                await self.websocket.close(code=1000)
            except (RuntimeError, WebSocketDisconnect):
                pass


def ingest(peer, raw):
    """Accept one native PCM frame from the Godot client.

    Wire format: little-endian signed PCM16, mono 48 kHz, exactly 960 samples
    (20 ms / 1920 bytes) per message. Byte order is normalized so the same
    server accepts a client on either host endianness.
    """
    if len(raw) != 1920:
        raise ValueError("Expected one 20ms PCM frame")
    if not accept_incoming(peer):
        return
    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if max(abs(x) for x in samples) > 500:
        peer.last_spoke = time.monotonic()
    peer.incoming.append((time.monotonic(), samples))


def authenticate(db, token):
    """Resolve an access token to a player id, leaving no transaction open.

    The socket's session is reused for its whole lifetime, so the speculative
    read this authentication begins is rolled back here rather than being left
    for the next frame to inherit.
    """
    try:
        return AuthService(db).authenticate(token).id
    finally:
        db.rollback()


@router.websocket("/ws")
async def native_voice(websocket: WebSocket, db: Session = Depends(get_db)):
    origin = websocket.headers.get("origin")
    if origin and origin not in settings.allowed_origins and "*" not in settings.allowed_origins:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    peer = None
    sender = None
    try:
        raw = await asyncio.wait_for(websocket.receive_text(), 5)
        if len(raw) > 8192 or not settings.voice_enabled:
            await websocket.close(code=1008)
            return
        auth = json.loads(raw)
        if not isinstance(auth, dict) or auth.get("type") != "auth" or not isinstance(auth.get("token"), str):
            raise ValueError("Invalid auth")
        pid = await run_in_threadpool(authenticate, db, auth["token"])
        generation, session_id = auth.get("connection_id"), auth.get("session_id")
        if not isinstance(session_id, str) or not isinstance(generation, str):
            raise ValueError("Invalid session")
        if not runtime.media_valid(pid, generation, session_id) or session_id in voice_hub.peers:
            raise ValueError("Join voice on the game connection first")
        peer = MediaPeer(pid, generation, session_id, SocketMedia(websocket), negotiated=True)
        voice_hub.peers[session_id] = peer
        if voice_hub.ticker is None or voice_hub.ticker.done():
            voice_hub.ticker = asyncio.create_task(voice_hub._tick())
        await websocket.send_json({"type": "voice.connected", "sample_rate": 48000, "frame_samples": 960})

        async def publish():
            while runtime.connection_valid(pid, generation, session_id):
                contributions = await peer.outgoing.get()
                samples = voice_hub.mix(peer, contributions)
                if sys.byteorder != "little":
                    samples.byteswap()
                await asyncio.wait_for(websocket.send_bytes(samples.tobytes()), 0.25)
        sender = asyncio.create_task(publish())
        window, count = time.monotonic(), 0
        while runtime.connection_valid(pid, generation, session_id) and not sender.done():
            try:
                message = await asyncio.wait_for(websocket.receive(), 0.25)
            except TimeoutError:
                continue
            if message["type"] == "websocket.disconnect":
                break
            raw = message.get("bytes")
            if raw is None:
                raise ValueError("Binary frames required")
            now = time.monotonic()
            if now - window >= 1:
                window, count = now, 0
            count += 1
            if count > 65:
                raise ValueError("Audio rate exceeded")
            ingest(peer, raw)
    except (ValueError, TypeError, KeyError, AppError, TimeoutError, WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if sender:
            sender.cancel()
            await asyncio.gather(sender, return_exceptions=True)
        if peer:
            await voice_hub.close(peer.session_id)
        else:
            try:
                await websocket.close(code=1008)
            except (RuntimeError, WebSocketDisconnect):
                pass

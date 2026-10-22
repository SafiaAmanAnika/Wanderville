"""Opus encoding for the native voice path.

The server mixes one 20 ms mono frame for every listener. Sent as raw PCM
that is 1,920 bytes per frame, so a listener costs 96 kB/s whether or not
anyone is speaking. Encoded with Opus at 24 kbit/s the same audio costs
60 bytes per frame: 3 kB/s, and the traffic stops being the largest thing the
server sends.

PyAV is already installed with the voice requirements, because aiortc needs
it, and its bundled libopus is the encoder used here. The server never
depends on it: a host without libopus keeps sending raw PCM, and the client
is told which encoding is in use, so the two ends never disagree about the
bytes on the wire.
"""

import av

SAMPLE_RATE = 48000
FRAME_SAMPLES = 960
FRAME_BYTES = FRAME_SAMPLES * 2

## The marker that opens a compressed audio packet. Raw PCM is sent as 1,920
## bytes with no header at all, so an older client ignores anything that is
## not exactly that size and never mistakes a compressed frame for PCM.
OPUS_MARKER = 1


class OpusUnavailable(RuntimeError):
    """Raised when this host cannot encode with libopus."""


class OpusEncoder:
    """Encodes 20 ms mono PCM frames into Opus frames.

    One encoder belongs to one listener. Opus encoders keep state, so they
    are not shared between listeners: each one is fed the mix that belongs to
    its own listener and never sees another listener's audio.
    """

    def __init__(self, bitrate=24000, application="voip"):
        try:
            context = av.CodecContext.create("libopus", "w")
            # Constant bitrate, so the cost of a listener is exactly the
            # configured budget: 60 bytes a frame at 24 kbit/s, whatever the
            # room sounds like. A variable bitrate spends more on a steady
            # tone than on speech, which makes the bill unpredictable.
            context.options = {"application": application, "vbr": "off"}
            context.sample_rate = SAMPLE_RATE
            context.format = "s16"
            context.layout = "mono"
            context.bit_rate = bitrate
            context.open()
        except Exception as exc:  # pragma: no cover - depends on the host
            raise OpusUnavailable(f"libopus is not usable here: {exc}") from exc
        self._context = context
        self._pts = 0
        self.bitrate = bitrate

    def encode(self, pcm):
        """Encode one frame of little-endian PCM16 mono into Opus frames.

        Returns a list because an encoder may hand back no frame at all, or
        more than one, for a given input. Each returned frame stands on its
        own and can be decoded on its own.
        """
        if len(pcm) != FRAME_BYTES:
            raise ValueError("Expected one 20ms PCM frame")
        frame = av.AudioFrame(format="s16", layout="mono", samples=FRAME_SAMPLES)
        frame.sample_rate = SAMPLE_RATE
        frame.pts = self._pts
        self._pts += FRAME_SAMPLES
        frame.planes[0].update(pcm.ljust(frame.planes[0].buffer_size, b"\x00"))
        return [bytes(packet) for packet in self._context.encode(frame)]


def available():
    """Whether this host can encode with libopus."""
    try:
        OpusEncoder()
    except OpusUnavailable:
        return False
    return True

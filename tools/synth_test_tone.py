"""Writes a 2 s Karplus-Strong pluck at C4 (261.63 Hz) as the prototype sample (ogg via ffmpeg)."""
import pathlib
import random
import struct
import subprocess
import tempfile
import wave

RATE = 44100
FREQ = 261.63
SECONDS = 2.0
OUT = pathlib.Path(__file__).resolve().parent.parent / "42/media/sound/PlayIt/test_pluck_C4.ogg"


def pluck():
    random.seed(1)
    period = int(RATE / FREQ)
    buf = [random.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(int(RATE * SECONDS)):
        j = i % period
        nxt = buf[(j + 1) % period]
        s = buf[j]
        buf[j] = 0.996 * 0.5 * (s + nxt)
        out.append(s)
    peak = max(abs(x) for x in out)
    return [x / peak * 0.7 for x in out]


def main():
    samples = pluck()
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "tone.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(x * 32767)) for x in samples))
        OUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", str(OUT)], check=True)
    print(OUT)


if __name__ == "__main__":
    main()

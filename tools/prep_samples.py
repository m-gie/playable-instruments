"""Builds the instrument samples from samples_raw/ (gitignored downloads, see CREDITS.md).

For every chosen note: decode with ffmpeg, cut the note out of the chromatic-scale file (notes are separated
by silence), measure its real pitch, trim to MAX_SECONDS with a fade-out, peak-normalise to -3 dB and write
mono ogg. Also writes the sound script and PlayIt/Samples.lua (midi, tuning offset in cents, sound name).

Usage: python -I tools/prep_samples.py
"""
import math
import pathlib
import subprocess
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "samples_raw"
SOUND_DIR = ROOT / "42/media/sound/PlayIt"
SCRIPT = ROOT / "42/media/scripts/PlayIt_sounds.txt"
SAMPLES_LUA = ROOT / "42/media/lua/shared/PlayIt/Samples.lua"

RATE = 44100
MAX_SECONDS = 3.0
FADE_SECONDS = 0.2
PEAK = 10 ** (-3 / 20)
NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

# instrument key -> (maxRadius for distanceMax, [(raw file, wanted midi)]); the note is found by its measured pitch
INSTRUMENTS = {
    "Guitar": (30, [
        ("guitar/Guitar.mf.sulE.E2B2.aif", 40),
        ("guitar/Guitar.mf.sulA.A2B2.aif", 45),
        ("guitar/Guitar.mf.sulD.D3B3.aif", 50),
        ("guitar/Guitar.mf.sulG.G3B3.aif", 55),
        ("guitar/Guitar.mf.sulB.B3.aif", 59),
        ("guitar/Guitar.mf.sul_E.E4B4.aif", 64),
        ("guitar/Guitar.mf.sul_E.E4B4.aif", 69),
        ("guitar/Guitar.mf.sul_E.E4B4.aif", 71),
    ]),
    "Trumpet": (45, [
        ("trumpet/Trumpet.novib.mf.E3B3.aiff", 55),
        ("trumpet/Trumpet.novib.mf.C4B4.aiff", 60),
        ("trumpet/Trumpet.novib.mf.C4B4.aiff", 65),
        ("trumpet/Trumpet.novib.mf.C4B4.aiff", 70),
        ("trumpet/Trumpet.novib.mf.C5B5.aiff", 76),
        ("trumpet/Trumpet.novib.mf.C5B5.aiff", 81),
    ]),
    "Violin": (25, [
        ("violin/Violin.arco.mf.sulG.G3B3.aif", 55),
        ("violin/Violin.arco.mf.sulD.D4B4.aif", 62),
        ("violin/Violin.arco.mf.sulA.A4B4.aif", 69),
        ("violin/Violin.arco.mf.sulE.E5B5.aif", 76),
        ("violin/Violin.arco.mf.sulE.C6B6.aif", 84),
        ("violin/Violin.arco.mf.sulE.C6B6.aif", 91),
    ]),
    "Flute": (25, [
        ("flute/Flute.vib.mf.B3B4.aiff", 62),
        ("flute/Flute.vib.mf.B3B4.aiff", 67),
        ("flute/Flute.vib.mf.B3B4.aiff", 71),
        ("flute/Flute.vib.mf.C5B5.aiff", 76),
        ("flute/Flute.vib.mf.C5B5.aiff", 81),
        ("flute/Flute.vib.mf.C6B6.aiff", 86),
        ("flute/Flute.vib.mf.C6B6.aiff", 91),
    ]),
    "Saxophone": (40, [
        ("sax/AltoSax.Vib.mf.Db3B3.aiff", 50),
        ("sax/AltoSax.Vib.mf.Db3B3.aiff", 55),
        ("sax/AltoSax.Vib.mf.C4B4.aiff", 60),
        ("sax/AltoSax.Vib.mf.C4B4.aiff", 65),
        ("sax/AltoSax.Vib.mf.C4B4.aiff", 70),
        ("sax/AltoSax.Vib.mf.C5Ab5.aiff", 75),
        ("sax/AltoSax.Vib.mf.C5Ab5.aiff", 80),
    ]),
    # VCSL Clavisynth file names are two octaves low (file "C1" sounds C3, measured); files above G#4 are left out
    "Keytar": (35, [
        (f"keytar/Clavisynth_{n}.wav", m)
        for n, m in [("C1", 48), ("E1", 52), ("G#1", 56), ("C2", 60), ("E2", 64), ("G#2", 68),
                     ("C3", 72), ("E3", 76), ("G#3", 80), ("C4", 84), ("E4", 88), ("G#4", 92)]
    ]),
    # VCSL file names are one octave low (file "C2" sounds C3, measured); the "C6" file is left out
    "Harmonica": (20, [
        (f"harmonica/Super64_{n}.wav", m)
        for n, m in [("C2", 48), ("E2", 52), ("G2", 55), ("C3", 60), ("E3", 64), ("G3", 67),
                     ("C4", 72), ("E4", 76), ("G4", 79), ("C5", 84)]
    ]),
}

# one recorded note per file: instrument key -> (maxRadius, seconds kept, [(raw file, sounding midi)]). The midi comes
# from the file name (the detector makes octave errors on organ pipes and extreme piano notes); the measured pitch,
# folded to the nearest octave, only gives the fine tuning
SINGLE = {
    # VCSL Yamaha upright file names are one octave low (file "C2" sounds C3); only C and G were recorded
    "Upright": (35, 4.0, [
        (f"upright/Upright1_Sus_{n}_vl2_rr1.wav", m)
        for n, m in [("C1", 36), ("G1", 43), ("C2", 48), ("G2", 55), ("C3", 60), ("G3", 67),
                     ("C4", 72), ("G4", 79), ("C5", 84), ("G5", 91)]
    ]),
    "Grand": (45, 4.0, [
        (f"grand/JHPiano_Sus_Close_{n}{o}_vl3_rr1.wav", 12 * (o + 1) + {"C": 0, "E": 4, "G#": 8}[n])
        for o in range(2, 7) for n in ("C", "E", "G#")
    ] + [("grand/JHPiano_Sus_Close_C7_vl3_rr1.wav", 96)]),
    "Organ": (60, 6.0, [
        (f"organ/Rode_Man3Open_{n}{o}.wav", 12 * (o + 1) + {"C": 0, "D#": 3, "F#": 6, "A": 9}[n])
        for o in range(2, 6) for n in ("C", "D#", "F#", "A")
    ] + [("organ/Rode_Man3Open_C6.wav", 84)]),
}

# unpitched drum hits from Virtuosity Drums ("mid" microphone, medium-loud velocity layer): piece -> raw file
DRUMS_RADIUS = 50
DRUMS = {"kick": "drums/kick.flac", "snare": "drums/snare.flac", "tomHigh": "drums/tomHigh.flac",
         "tomLow": "drums/tomLow.flac"}


def decode(path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def segments(audio, frame=0.02, floor_db=-40, min_gap=0.15, min_len=0.25):
    """Note regions: frames louder than floor_db below the file's loudest frame, joined across short gaps."""
    n = int(frame * RATE)
    frames = len(audio) // n
    rms = np.sqrt(np.mean(audio[:frames * n].reshape(frames, n) ** 2, axis=1) + 1e-12)
    loud = 20 * np.log10(rms / rms.max()) > floor_db
    regions, start, quiet = [], None, 0
    for i, on in enumerate(loud):
        if on:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet * frame >= min_gap:
                regions.append((start, i - quiet + 1))
                start, quiet = None, 0
    if start is not None:
        regions.append((start, frames))
    return [(a * n, b * n) for a, b in regions if (b - a) * frame >= min_len]


def pitch_midi(note):
    """Fundamental of the steady part (from 0.15 s), autocorrelation over 40-2000 Hz, as fractional midi."""
    seg = note[int(0.15 * RATE):int(0.65 * RATE)]
    seg = seg - seg.mean()
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo, hi = int(RATE / 2000), int(RATE / 40)
    lag = lo + int(np.argmax(corr[lo:hi]))
    # prefer the shortest lag with a comparable peak (avoids octave-down errors)
    for div in (4, 3, 2):
        cand = int(round(lag / div))
        if cand >= lo and corr[cand] > 0.85 * corr[lag]:
            lag = cand
            break
    if 0 < lag < len(corr) - 1:  # parabolic interpolation
        a, b, c = corr[lag - 1], corr[lag], corr[lag + 1]
        lag = lag + 0.5 * (a - c) / (a - 2 * b + c)
    return 69 + 12 * math.log2((RATE / lag) / 440)


def find_note(audio, wanted, raw):
    """The note region whose measured pitch rounds to `wanted`, trying looser splits until one matches."""
    for floor_db, gap in ((-40, 0.15), (-40, 0.08), (-40, 0.05), (-30, 0.15)):
        for a, b in segments(audio, floor_db=floor_db, min_gap=gap, min_len=0.6):
            note = audio[max(0, a - int(0.01 * RATE)):b]
            measured = pitch_midi(note)
            if round(measured) == wanted:
                return note, measured
    sys.exit(f"{raw}: no note with pitch {note_name(wanted)} found")


def finish(note, seconds=MAX_SECONDS):
    note = note[:int(seconds * RATE)].copy()
    fade = int(FADE_SECONDS * RATE)
    if len(note) > fade:
        note[-fade:] *= np.linspace(1, 0, fade)
    return note * (PEAK / max(np.abs(note).max(), 1e-9))


def write_ogg(audio, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", str(path)], input=audio.astype(np.float32).tobytes(), check=True)


def note_name(midi):
    return f"{NAMES[midi % 12]}{midi // 12 - 1}"


def single_note(audio, midi, raw):
    """The file's one note from its start, and its tuning (st) against `midi` with octave errors folded away."""
    regions = segments(audio, min_len=0.3)
    if not regions:
        sys.exit(f"{raw}: no note found")
    a = regions[0][0]
    note = audio[max(0, a - int(0.01 * RATE)):]
    off = pitch_midi(note) - midi
    off -= 12 * round(off / 12)
    if abs(off) > 0.5:
        sys.exit(f"{raw}: sounds {off:+.2f} st away from {note_name(midi)}")
    return note, off


def hit(audio):
    """A drum hit from its onset (first sample above -40 dB of the peak)."""
    start = int(np.argmax(np.abs(audio) > np.abs(audio).max() * 0.01))
    return audio[max(0, start - int(0.002 * RATE)):]


def sound_script(name, file, radius):
    return [f"    sound {name}", "    {", "        category = Item,", "        is3D = true,",
            "        clip", "        {", f"            file = media/sound/PlayIt/{file},",
            "            distanceMin = 1,", f"            distanceMax = {radius},", "        }", "    }"]


def main():
    script = ["module Base", "{"]
    lua = ["-- Generated by tools/prep_samples.py; do not edit.", "PlayIt = PlayIt or {}", "PlayIt.Samples = {"]
    worst = 0.0
    for key, (radius, notes) in INSTRUMENTS.items():
        lua.append(f"    {key} = {{")
        decoded = {}
        for raw, label in notes:
            if raw not in decoded:
                decoded[raw] = decode(RAW / raw)
            note, measured = find_note(decoded[raw], label, raw)
            midi = round(measured)
            off = measured - midi
            worst = max(worst, abs(off))
            print(f"{key:9} {raw:38} {note_name(midi):4} midi {midi} ({off:+.2f} st)")
            name = f"PlayIt_{key}_{note_name(midi)}"
            file = f"{key.lower()}_{note_name(midi).lower()}.ogg"
            write_ogg(finish(note), SOUND_DIR / file)
            script += sound_script(name, file, radius)
            lua.append(f"        {{ midi = {midi}, tune = {round(off * 100)}, sound = \"{name}\" }},")
        lua.append("    },")
    for key, (radius, seconds, notes) in SINGLE.items():
        lua.append(f"    {key} = {{")
        for raw, midi in notes:
            note, off = single_note(decode(RAW / raw), midi, raw)
            worst = max(worst, abs(off))
            print(f"{key:9} {raw:38} {note_name(midi):4} midi {midi} ({off:+.2f} st)")
            name = f"PlayIt_{key}_{note_name(midi)}"
            file = f"{key.lower()}_{note_name(midi).lower()}.ogg"
            write_ogg(finish(note, seconds), SOUND_DIR / file)
            script += sound_script(name, file, radius)
            lua.append(f"        {{ midi = {midi}, tune = {round(off * 100)}, sound = \"{name}\" }},")
        lua.append("    },")
    lua.append("    Drums = {")
    for piece, raw in DRUMS.items():
        name = f"PlayIt_Drums_{piece[0].upper()}{piece[1:]}"
        file = f"drums_{piece.lower()}.ogg"
        write_ogg(finish(hit(decode(RAW / raw))), SOUND_DIR / file)
        script += sound_script(name, file, DRUMS_RADIUS)
        lua.append(f"        {piece} = {{ sound = \"{name}\" }},")
        print(f"Drums     {raw:38} -> {name}")
    lua.append("    },")
    script.append("}")
    lua.append("}")
    SCRIPT.write_text("\n".join(script) + "\n", encoding="utf-8")
    SAMPLES_LUA.write_text("\n".join(lua) + "\n", encoding="utf-8")
    print(f"largest tuning offset: {worst:.2f} semitones (corrected at playback via tune)")


if __name__ == "__main__":
    main()

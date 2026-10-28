"""Builds the instrument samples from samples_raw/ (gitignored downloads, see CREDITS.md).

For every chosen note: decode with ffmpeg, cut the note out of the chromatic-scale file (notes are separated
by silence), measure its real pitch, trim to MAX_SECONDS with a fade-out, peak-normalise to -3 dB and write
mono ogg. Also writes the sound script and PlayIt/Samples.lua (midi, tuning offset in cents, sound name).

Usage: python -I tools/prep_samples.py
"""
import collections
import math
import pathlib
import re
import struct
import subprocess
import sys
import wave

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

# shortest note a chromatic-scale file holds (plucked strings die away fast)
MIN_NOTE_SECONDS = {"ViolinPizz": 0.2}
# instruments whose listed notes are a wish list: the pitch detector struggles with plucked notes, so notes it
# can't find cleanly are left out (the nearest found note is pitched to cover them)
OPTIONAL_NOTES = {"ViolinPizz"}

# Iowa MIS violin pizzicato (2012), mono, mf: chromatic-scale files like the bowed violin
INSTRUMENTS["ViolinPizz"] = (25, [
    (f"pizz/Violin.pizz.mf.{f}.mono.aif", m)
    for f, lo, hi in [("sulG.G3B3", 55, 59), ("sulG.C4C5", 60, 61), ("sulD.D4B4", 62, 71), ("sulA.B4Ab5", 72, 75),
                      ("sulE.E5B5", 76, 83), ("sulE.C6B6", 84, 95)]
    for m in range(lo, hi + 1)
])

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

# unpitched drum hits from Virtuosity Drums (medium-loud velocity layers): set key -> piece -> raw file. "Drums" is
# the "mid" microphone, "DrumsLofi" the lofi mix (same layers: kick snares-off 3, snare centre 25, toms 11, hh 3,
# crash 2)
DRUMS_RADIUS = 50
DRUM_SETS = {
    "Drums": {"kick": "drums/kick.flac", "snare": "drums/snare.flac", "tomHigh": "drums/tomHigh.flac",
              "tomLow": "drums/tomLow.flac", "hihat": "drums/hihat.flac", "crash": "drums/crash.flac"},
    "DrumsLofi": {"kick": "drumslofi/kick.flac", "snare": "drumslofi/snare.flac",
                  "tomHigh": "drumslofi/tomHigh.flac", "tomLow": "drumslofi/tomLow.flac",
                  "hihat": "drumslofi/hihat.flac", "crash": "drumslofi/crash.flac"},
}

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
              "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def name_midi(name):
    """midi of a note name like "C#3" (C4 = 60)."""
    m = re.match(r"([A-G][#b]?)(-?\d)", name)
    return 12 * (int(m.group(2)) + 1) + NOTE_INDEX[m.group(1)]


def sfz_regions(path):
    """Regions of an SFZ file with their <global> and <group> opcodes merged in (enough SFZ for these libraries)."""
    text = re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8", errors="replace"))
    glob, group, current, regions = {}, {}, None, []
    for line in text.splitlines():
        for part in re.split(r"(<\w+>)", line):
            header = re.fullmatch(r"<(\w+)>", part)
            if header:
                kind = header.group(1)
                if kind == "global":
                    glob, group = {}, {}
                    current = glob
                elif kind in ("group", "master"):
                    group = {}
                    current = group
                elif kind == "region":
                    current = {}
                    regions.append((glob, dict(group), current))
                else:
                    current = {}  # <control> and the like: not needed
                continue
            if current is not None:
                for m in re.finditer(r"(\w+)=(.*?)(?=\s+\w+=|$)", part.strip()):
                    current[m.group(1)] = m.group(2).strip()
    return [{**g, **grp, **reg} for g, grp, reg in regions]


def sfz_notes(sfz, low, high):
    """One recording per key centre within low..high: the loudest velocity layer's first round robin."""
    sfz = RAW / sfz
    best = {}
    for r in sfz_regions(sfz):
        key = r.get("pitch_keycenter", r.get("key"))
        if "sample" not in r or key is None:
            continue
        midi = int(key) if key.lstrip("-").isdigit() else name_midi(key)
        if not low <= midi <= high:
            continue
        rank = (-int(r.get("lovel", 0)), float(r.get("lorand", 0)), int(r.get("seq_position", 1)))
        if midi not in best or rank < best[midi][0]:
            best[midi] = (rank, (sfz.parent / r["sample"].replace("\\", "/")).resolve())
    return [(path.relative_to(RAW.resolve()).as_posix(), midi) for midi, (_, path) in sorted(best.items())]


def sf2_notes(sf2, outdir):
    """Writes each mono sample of a SoundFont 2 as a wav under RAW/outdir; [(raw file, original pitch)]."""
    data = (RAW / sf2).read_bytes()

    def chunks(off, end):
        while off < end:
            cid, size = data[off:off + 4], struct.unpack("<I", data[off + 4:off + 8])[0]
            yield cid, off + 8, size
            off += 8 + size + (size & 1)

    smpl = shdr = None
    for cid, off, size in chunks(12, len(data)):
        if cid == b"LIST":
            for sub, o2, s2 in chunks(off + 4, off + size):
                if sub == b"smpl":
                    smpl = o2
                elif sub == b"shdr":
                    shdr = (o2, s2)
    (RAW / outdir).mkdir(parents=True, exist_ok=True)
    out = []
    for i in range(shdr[1] // 46 - 1):  # the last record is the terminal "EOS"
        name, start, end, _, _, rate, pitch, _, _, kind = struct.unpack(
            "<20sIIIIIBbHH", data[shdr[0] + i * 46:shdr[0] + i * 46 + 46])
        if kind != 1:  # mono samples only
            continue
        rel = f"{outdir}/{pitch}.wav"
        with wave.open(str(RAW / rel), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(data[smpl + 2 * start:smpl + 2 * end])
        out.append((rel, pitch))
    return sorted(out, key=lambda e: e[1])


def vcsl_notes(folder, pattern):
    """VCSL files in RAW/folder matching pattern (one group: the note name), labelled by their file names."""
    out = []
    for f in sorted((RAW / folder).iterdir()):
        m = re.fullmatch(pattern, f.name)
        if m:
            out.append((f"{folder}/{f.name}", name_midi(m.group(1))))
    return sorted(out, key=lambda e: e[1])


FP = "_dl"  # FreePATS archives, ganjo and VCSL folders as downloaded (see CREDITS.md)
VCSL = f"{FP}/vcsl"

# tones (2026-10-28): key -> (maxRadius, seconds kept, [(raw file, midi)], options). Options: "octave": the file
# names may be whole octaves off (VCSL): the octave shift most of the tone's files measure is applied to all of
# them, and files measuring otherwise are left out (unmeasurable lows); "lenient": a note whose measured
# pitch is off (distortion, noisy attacks) keeps the source's key centre untuned instead of stopping the build
TONES = {
    "ElectricClean": (35, 3.0, sfz_notes(
        f"{FP}/EGuitarFSBS-clean-SFZ+FLAC-20260807/EGuitarFSBS-clean SFZ+FLAC-20260807/"
        "EGuitarFSBS-clean bridge 20260807.sfz", 34, 94), {"lenient": True}),
    "ElectricJazz": (35, 3.0, sfz_notes(
        f"{FP}/EGuitarFSBS-jazz-SFZ+FLAC-20260807/EGuitarFSBS-jazz SFZ+FLAC-20260807/"
        "EGuitarFSBS-jazz bridge 20260807.sfz", 34, 94), {"lenient": True}),
    "ElectricDistorted": (35, 3.0, sfz_notes(
        f"{FP}/EGuitarFSBS-dist2-SFZ+FLAC-20220911/EGuitarFSBS-dist2 SFZ+FLAC-20220911/"
        "EGuitarFSBS-dist2 bridge 20220911.sfz", 34, 94), {"lenient": True}),
    "BassPick": (30, 3.0, sfz_notes(
        f"{FP}/PickedBassYR-SFZ+FLAC-20190930/PickedBassYR SFZ+FLAC-20190930/PickedBassYR 20190930.sfz",
        22, 73), {"lenient": True}),
    "BassFinger": (30, 3.0, sfz_notes(
        f"{FP}/FingerBassYR-SFZ+FLAC-20190930/FingerBassYR SFZ+FLAC-20190930/FingerBassYR 20190930.sfz",
        22, 73), {"lenient": True}),
    "Banjo5": (30, 3.0, sf2_notes("banjo5/Windsor.sf2", "banjo5/notes"), {}),
    "Banjo6": (30, 3.0, sfz_notes(f"{FP}/ganjo/ganjo.sfz", 42, 87), {"lenient": True}),
    "HonkyTonk": (35, 4.0, sfz_notes(
        f"{FP}/PianoFB-SFZ+FLAC-20200401/PianoFB SFZ+FLAC-20200401/PianoFB 20200401.sfz", 36, 96),
        {"lenient": True}),
    "SaxTenor": (40, 3.0, vcsl_notes(f"{VCSL}/Aerophones/Reed Aerophones/Tenor Saxophone/Vibrato",
                                     r"BrettTenor_Vib_Main_([A-G]#?\d)_var\d+\.wav"), {"octave": True}),
    "HarmonicaBlues": (20, 3.0, vcsl_notes(
        f"{VCSL}/Aerophones/Free Aerophones/Harmonica-Hohner-Special20-C/Sustains/Normal",
        r"Hohner-Special20_Normal_([A-G]#?\d)\.wav"), {"octave": True, "skip": True}),
    "KeytarFM": (35, 3.0, vcsl_notes(f"{VCSL}/Electrophones/TX81Z/FM Piano", r"FMPiano_([A-G]#?\d)_vl2\.wav"),
                 {"octave": True, "skip": True}),
    "KeytarPiano": (35, 3.0, vcsl_notes(f"{VCSL}/Electrophones/TX81Z/Piano 1", r"Piano 1_([A-G]#?\d)_vl2\.wav"),
                    {"octave": True, "skip": True}),
    "OrganRenaissance": (60, 6.0, vcsl_notes(f"{VCSL}/Aerophones/Edge-blown Aerophones/Renaissance Organ/Full",
                                             r"RenOrgan_Full_Room_([A-G]#?\d)_rr1\.wav"), {}),
}


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
    start = 0.15 if len(note) > 0.8 * RATE else 0.03  # short (plucked) notes: measure close to the attack
    seg = note[int(start * RATE):int((start + 0.5) * RATE)]
    seg = seg - seg.mean()
    lo, hi = int(RATE / 2000), int(RATE / 40)
    if len(seg) < 2 * hi:  # too short to measure
        return float("nan")
    corr = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lag = lo + int(np.argmax(corr[lo:hi]))
    # prefer the shortest lag with a comparable peak (avoids octave-down errors)
    for div in (4, 3, 2):
        cand = int(round(lag / div))
        if cand >= lo and corr[cand] > 0.85 * corr[lag]:
            lag = cand
            break
    if 0 < lag < len(corr) - 1:  # parabolic interpolation
        a, b, c = corr[lag - 1], corr[lag], corr[lag + 1]
        denom = a - 2 * b + c
        if denom != 0:
            lag = lag + max(-1.0, min(1.0, 0.5 * (a - c) / denom))
    if not 0 < lag < len(corr):
        return float("nan")
    return 69 + 12 * math.log2((RATE / lag) / 440)


def find_note(audio, wanted, raw, min_len=0.6, optional=False):
    """The note region whose measured pitch rounds to `wanted`, trying looser splits until one matches.
    optional: None when it isn't found (instead of stopping the build)."""
    for floor_db, gap in ((-40, 0.15), (-40, 0.08), (-40, 0.05), (-30, 0.15)):
        for a, b in segments(audio, floor_db=floor_db, min_gap=gap, min_len=min_len):
            note = audio[max(0, a - int(0.01 * RATE)):b]
            measured = pitch_midi(note)
            if math.isfinite(measured) and round(measured) == wanted:
                return note, measured
    if optional:
        print(f"  skipped: {raw} has no clean {note_name(wanted)}")
        return None, None
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


def octave_shift(notes):
    """The whole-octave shift between file names and sounding pitch that most of a tone's files measure."""
    votes = collections.Counter()
    for raw, midi in notes:
        audio = decode(RAW / raw)
        regions = segments(audio, min_len=0.3)
        if regions:
            measured = pitch_midi(audio[regions[0][0]:])
            if math.isfinite(measured):
                votes[round((measured - midi) / 12)] += 1
    return votes.most_common(1)[0][0] if votes else 0


def single_note(audio, midi, raw, octave=False, lenient=False, skip=False, same_octave=False):
    """The file's one note from its start, its midi and tuning (st) against `midi` with octave errors folded away.
    octave: the measured pitch picks the octave (file names an octave or two off). lenient: an off pitch is kept
    at `midi` untuned instead of stopping the build. skip: an off note is left out (returns None). same_octave: also
    left out when it measures in another octave (the detector misreads the lowest and highest files)."""
    regions = segments(audio, min_len=0.3)
    if not regions:
        sys.exit(f"{raw}: no note found")
    a = regions[0][0]
    note = audio[max(0, a - int(0.01 * RATE)):]
    measured = pitch_midi(note)
    if not math.isfinite(measured):
        measured = float(midi)  # unmeasurable: keep the label, untuned
    if octave:
        midi += 12 * round((measured - midi) / 12)
    if same_octave and abs(measured - midi) > 6:
        print(f"  skipped: {raw} measures {measured - midi:+.1f} st from {note_name(midi)} (another octave)")
        return None, midi, 0.0
    off = measured - midi
    off -= 12 * round(off / 12)
    if abs(off) > (0.75 if lenient else 0.5):  # lenient sources: up to 3/4 st is real (de)tuning, kept
        if skip:
            print(f"  skipped: {raw} measures {off:+.2f} st from {note_name(midi)}")
            return None, midi, off
        if not lenient:
            sys.exit(f"{raw}: sounds {off:+.2f} st away from {note_name(midi)}")
        print(f"  warning: {raw} measures {off:+.2f} st from {note_name(midi)}; kept untuned")
        off = 0.0
    return note, midi, off


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
            note, measured = find_note(decoded[raw], label, raw, MIN_NOTE_SECONDS.get(key, 0.6), key in OPTIONAL_NOTES)
            if note is None:
                continue
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
    singles = {key: (radius, seconds, notes, {}) for key, (radius, seconds, notes) in SINGLE.items()}
    for key, (radius, seconds, notes, opts) in {**singles, **TONES}.items():
        lua.append(f"    {key} = {{")
        if not notes:
            sys.exit(f"{key}: no source notes found")
        octave = False
        if opts.get("octave"):
            shift = octave_shift(notes)
            print(f"{key}: file names are {shift:+d} octave(s) from the sounding pitch")
            notes = [(raw, midi + 12 * shift) for raw, midi in notes]
        used = set()
        for raw, midi in notes:
            note, midi, off = single_note(decode(RAW / raw), midi, raw, octave, opts.get("lenient"),
                                          opts.get("skip") or opts.get("octave"), opts.get("octave"))
            if note is None:
                continue
            if midi in used:  # two recordings on one note would share (and overwrite) a sound file
                sys.exit(f"{key}: {raw} lands on {note_name(midi)} a second time")
            used.add(midi)
            worst = max(worst, abs(off))
            print(f"{key:9} {raw:38} {note_name(midi):4} midi {midi} ({off:+.2f} st)")
            name = f"PlayIt_{key}_{note_name(midi)}"
            file = f"{key.lower()}_{note_name(midi).lower()}.ogg"
            write_ogg(finish(note, seconds), SOUND_DIR / file)
            script += sound_script(name, file, radius)
            lua.append(f"        {{ midi = {midi}, tune = {round(off * 100)}, sound = \"{name}\" }},")
        lua.append("    },")
    for key, pieces in DRUM_SETS.items():
        lua.append(f"    {key} = {{")
        for piece, raw in pieces.items():
            name = f"PlayIt_{key}_{piece[0].upper()}{piece[1:]}"
            file = f"{key.lower()}_{piece.lower()}.ogg"
            write_ogg(finish(hit(decode(RAW / raw))), SOUND_DIR / file)
            script += sound_script(name, file, DRUMS_RADIUS)
            lua.append(f"        {piece} = {{ sound = \"{name}\" }},")
            print(f"{key:9} {raw:38} -> {name}")
        lua.append("    },")
    script.append("}")
    lua.append("}")
    SCRIPT.write_text("\n".join(script) + "\n", encoding="utf-8")
    SAMPLES_LUA.write_text("\n".join(lua) + "\n", encoding="utf-8")
    print(f"largest tuning offset: {worst:.2f} semitones (corrected at playback via tune)")


if __name__ == "__main__":
    main()

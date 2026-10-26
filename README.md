# Play it! Playable musical instruments

Project Zomboid (Build 42) mod: the vanilla acoustic guitar, violin, trumpet, harmonica, flute, saxophone and keytar play songs written in the Space Station 13 note format, note by note, heard by every player nearby. Zombies come to listen, wild animals run, tame ones that trust you come closer, and a Music skill decides how often you blunder.

Tests: `python tests/run.py` (Lua 5.1 via lupa).

## Songs

Paste text in the Space Station 13 instrument format: an optional `BPM: 120` first line, chords separated by `,`, notes in a chord joined by `-`, `/n` divides a chord's length (`/0.5` doubles it), an octave digit and `#`/`b`/`n` stick to their letter. Up to 300 lines of 300 characters.

Songs: the /tg/station and Yogstation wikis have "Songs" pages. MIDI files convert with midi2piano (tgstation `tools/midi2piano`, or the web version at midi.dreambubble.xyz).

## Development

- `python tests/run.py`: offline tests (Lua 5.1 via lupa).
- `python -I tools/prep_samples.py`: rebuild the samples from `samples_raw/` (downloads listed in CREDITS.md).
- `python workshop/preview.py`: draw the Workshop cover.
- `bash workshop.sh`: stage the Workshop upload folder.

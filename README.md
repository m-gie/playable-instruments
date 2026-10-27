# Play it! Playable musical instruments

Project Zomboid (Build 42) mod: the vanilla acoustic guitar, violin, trumpet, harmonica, flute, saxophone and keytar play songs written in ABC notation, note by note, heard by every player nearby. Zombies come to listen, wild animals run, tame ones that trust you come closer, and a Music skill decides how often you blunder.

Tests: `python tests/run.py` (Lua 5.1 via lupa).

## Songs

Paste a song in [ABC notation](https://abcnotation.com/) into the music window. A file with several tunes (`X:`) or voices (`V:`) is a band arrangement: pick your part in the Part list. The BPM field starts at the part's tempo (`Q:`); changing it speeds the whole part up or down.

- Supported: keys and modes (`K:`), meters, unit lengths, tempos and their inline changes, accidentals, octaves, note lengths, rests, chords, ties (also on single notes in a chord), broken rhythm, tuplets, repeats with first and second endings. Decorations, chord symbols, grace notes, slurs and lyrics are skipped.
- Drum parts: a tune with `%%MIDI channel 10` is read as General MIDI percussion (note number = drum), folded onto the kit's kick, snare, toms, hi-hat and crash; `%%percmap` is honoured. Any other part played on the drums maps its range to the kit.
- Solo play skips the silence before a part's first note.
- Limits: a part travels to other players as one network string, so at most 30,000 characters (comments, lyrics and blank lines don't count) and 10,000 notes, chords and rests after repeats.

Songs: abcnotation.com and thesession.org have hundreds of thousands of tunes; MIDI files convert with the Play it! MIDI converter (a web page; link to follow).

## Development

- `python tests/run.py`: offline tests (Lua 5.1 via lupa).
- `python -I tools/prep_samples.py`: rebuild the samples from `samples_raw/` (downloads listed in CREDITS.md).
- `python workshop/preview.py`: draw the Workshop cover.
- `bash workshop.sh`: stage the Workshop upload folder.

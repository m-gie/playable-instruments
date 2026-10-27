# Credits

## Instrument samples

The notes are cut from these recordings by `tools/prep_samples.py`: split into single notes, trimmed to 3 s with a fade-out, normalised, and converted to mono ogg.

**Acoustic guitar, trumpet, violin, flute, alto saxophone:** University of Iowa Electronic Music Studios, Musical Instrument Samples (Lawrence Fritts, director). https://theremin.music.uiowa.edu/MIS.html
"These recordings ... may be downloaded and used for any projects, without restrictions."
- Guitar: Raimundo 118, played by Brian Penkrot (2011). Files `Guitar.mf.*.mono.aif`.
- Bb trumpet: Bach Stradivarius 180S37, played by Aren Van Houzen (2003). Files `Trumpet.novib.mf.*.aiff`.
- Violin: Nicolai Tambovsky violin (1998), played by Leonid Iogansen (2012). Files `Violin.arco.mf.*.mono.aif`.
- Flute: played by Sonja Feig (2000). Files `Flute.vib.mf.*.aiff`.
- Alto saxophone: played by Michael Giles (1997). Files `AltoSax.Vib.mf.*.aiff`.

**Harmonica:** Versilian Studios Community Sample Library (VCSL) by Sam Gossner, CC0 1.0. https://github.com/sgossner/VCSL
- Hohner Super 64 chromatic, `Sustains/Normal`. VCSL's file names are one octave below the sounding pitch; the mod uses the measured pitch.

**Keytar:** VCSL as above, Yamaha TX81Z "Clavisynth" patch (`Electrophones/TX81Z/Clavisynth`, velocity layer 2). File names are two octaves below the sounding pitch; the mod uses the measured pitch.

**Upright piano (Western Piano):** VCSL as above, Yamaha upright (`Chordophones/Zithers/Upright Piano, Yamaha/Sustains`, velocity layer 2, round robin 1). Only C and G were recorded; file names are one octave below the sounding pitch.

**Grand piano (Black Grand Piano):** VCSL as above, Steinway B grand (`Chordophones/Zithers/Grand Piano, Steinway B/Sus`, close microphones, velocity layer 3, round robin 1).

**Church organ:** VCSL as above, pipe organ (`Aerophones/Edge-blown Aerophones/Pipe Organ/Loud`).

**Drums:** Virtuosity Drums by Versilian Studios and Karoryfer Lecolds, CC0 1.0, recorded with drummer Austin McMahon at Virtuosity Musical Instruments, Boston. https://github.com/sfzinstruments/virtuosity_drums
- "mid" microphone: kick (snares off, velocity layer 3 of 4), snare centre hit (layer 25 of 36), high and low tom centre hits (layer 11 of 16).

## Song format

The song text format follows Space Station 13's instrument songs (tgstation, `code/modules/instruments`).

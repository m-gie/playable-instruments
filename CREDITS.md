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
- "mid" microphone: kick (snares off, velocity layer 3 of 4), snare centre hit (layer 25 of 36), high and low tom centre hits (layer 11 of 16), closed hi-hat (layer 3 of 4), crash (layer 2 of 3).
- Lo-fi tone: the same hits from the "lofi" mix.

### Tones and later instruments (2026-10-28)

**Electric guitar (Clean, Jazz, Distorted):** FreePats project, "Electric Guitar FSBS", CC0 1.0: a Fender electric guitar, bridge pickup, sampled direct and run through an amp and effects rack. Clean #1, Clean #2 (jazz) and Distorted #2 banks, loudest velocity layer, first round robin. https://freepats.zenvoid.org/ElectricGuitar/clean-electric-guitar.html and https://freepats.zenvoid.org/ElectricGuitar/distorted-electric-guitar.html

**Electric bass (Pick, Fingers):** FreePats project, Yamaha RBX bass sampled by Andrea Biasior, CC0 1.0. https://freepats.zenvoid.org/ElectricGuitar/clean-electric-bass.html

**Banjo, 5-string:** "Windsor Banjo c1920-1930" SoundFont by Clive Nelson, public domain (Polyphone soundfont library): an old 5-string Windsor banjo made in Birmingham, England; its four samples (D3, G3, B3, D4). https://www.polyphone.io/en/soundfonts/plucked-strings/444-windsor-banjo-c1920-1930

**Banjo, 6-string:** "ganjo" by itsclipping (sfzinstruments), CC0 1.0: an SX 6-string guitar banjo, first round robin. https://github.com/sfzinstruments/ganjo

**Upright piano, Honky-tonk:** FreePats project, Francis Bacon player piano recorded by Piotr Barcz, CC0 1.0. https://freepats.zenvoid.org/Piano/honky-tonk-piano.html

**Violin, Plucked:** University of Iowa MIS as above, the same violin and player, pizzicato (`Violin.pizz.mf.*.mono.aif`).

**Saxophone, Tenor:** VCSL as above, tenor saxophone (`Aerophones/Reed Aerophones/Tenor Saxophone/Vibrato`).

**Harmonica, Blues harp:** VCSL as above, Hohner Special 20 in C (`Aerophones/Free Aerophones/Harmonica-Hohner-Special20-C/Sustains/Normal`).

**Keytar, FM Piano and Piano:** VCSL as above, Yamaha TX81Z "FM Piano" and "Piano 1" patches (`Electrophones/TX81Z`, velocity layer 2).

**Church organ, Renaissance:** VCSL as above, Renaissance organ, full registration (`Aerophones/Edge-blown Aerophones/Renaissance Organ/Full`, room microphones, round robin 1).

## Song format

Songs are ABC notation (abcnotation.com). The idea of pasting songs into an in-game instrument comes from Space Station 13's instruments (tgstation, `code/modules/instruments`).

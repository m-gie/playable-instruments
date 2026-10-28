require "PlayIt/Song"
local S = PlayIt.Song
local function notes(song, i) return table.concat(song.chords[i].notes, " ") end
local function near(a, b) return math.abs(a - b) < 1e-9 end
-- a tune with L:1/4, so a plain note is one beat (a quarter note)
local function tune(body, header) return "X:1\nL:1/4\n" .. (header or "") .. "K:C\n" .. body end
local function P(body, header, bpm) return S.parse(tune(body, header), bpm) end
local function seq(song) local t = {} for i in ipairs(song.chords) do t[i] = notes(song, i) end return table.concat(t, ",") end

-- pitches
local s = P("C D E F G A B c d e f g a b")
check(#s.chords == 14 and notes(s, 1) == "60" and notes(s, 8) == "72" and notes(s, 14) == "83", "C = 60, c = 72")
s = P("C, C,, c' c'' C,'")
check(seq(s) == "48,36,84,96,60", "octave marks")
s = P("^C _D =E ^^F __B")
check(seq(s) == "61,61,64,67,69", "accidentals")
s = P("^C C c | C")
check(seq(s) == "61,61,72,60", "accidentals last the bar, same octave only")
s = P("^C =C C")
check(seq(s) == "61,60,60", "= cancels within the bar")

-- key signatures
local function key(k, body) return seq(S.parse("X:1\nL:1/4\nK:" .. k .. "\n" .. body)) end
check(key("G", "F") == "66", "K:G sharpens F")
check(key("F", "B") == "70", "K:F flattens B")
check(key("Bb", "E") == "63", "K:Bb flattens E")
check(key("Am", "F") == "65", "K:Am has no accidentals")
check(key("Em", "F") == "66", "K:Em = G major")
check(key("D dorian", "F") == "65", "K:D dorian = C major")
check(key("Ador", "F") == "66", "K:Ador = G major")
check(key("G mix", "F") == "65", "K:G mix = C major")
check(key("F#m", "C") == "61", "K:F#m = A major")
check(key("G clef=bass", "F") == "66", "extra words after the key are ignored")
check(key("G", "F =F F | F") == "66,65,65,66", "= overrides the key to the bar's end")
check(key("none", "F") == "65", "K:none")
check(key("C", "F [K:G] F") == "65,66", "inline key change")

-- lengths (L:1/4: a beat per plain note)
s = P("C2 C/2 C/ C// C3/2 C2/3")
check(near(s.chords[1].beats, 2) and near(s.chords[2].beats, 0.5) and near(s.chords[3].beats, 0.5)
    and near(s.chords[4].beats, 0.25) and near(s.chords[5].beats, 1.5) and near(s.chords[6].beats, 2 / 3), "length forms")
check(near(S.parse("X:1\nL:1/8\nK:C\nC").chords[1].beats, 0.5), "L:1/8: a plain note is half a beat")
check(near(S.parse("X:1\nM:4/4\nK:C\nC").chords[1].beats, 0.5), "no L: with M:4/4 means 1/8")
check(near(S.parse("X:1\nM:2/4\nK:C\nC").chords[1].beats, 0.25), "no L: with M:2/4 means 1/16")
check(near(S.parse("X:1\nK:C\nC").chords[1].beats, 0.5), "no L: and no M: means 1/8")
check(near(P("C999999").chords[1].beats, 64) and near(P("C/999999").chords[1].beats, 1 / 64), "lengths clamped")

-- rests, chords, ties
s = P("C z D x2")
check(#s.chords == 4 and #s.chords[2].notes == 0 and near(s.chords[4].beats, 2), "rests z and x")
s = S.parse("X:1\nM:3/4\nL:1/4\nK:C\nC Z2 D")
check(#s.chords == 3 and near(s.chords[2].beats, 6), "Z is whole bars of the meter")
s = P("[CEG]2 [C/E/]")
check(notes(s, 1) == "60 64 67" and near(s.chords[1].beats, 2) and near(s.chords[2].beats, 0.5), "chords and their lengths")
s = P("C2- C D")
check(#s.chords == 3 and #s.chords[2].notes == 0 and near(s.chords[1].lens[1], 3) and near(s.chords[2].beats, 1), "a tie holds the note, no new strike")
s = P("[C-E]2 [CG]2")
check(notes(s, 2) == "67" and near(s.chords[1].lens[1], 4) and near(s.chords[1].lens[2], 2), "tie on one note of a chord")
s = P("[CE]2- [CE]")
check(#s.chords[2].notes == 0 and near(s.chords[1].lens[1], 3), "tie after a chord ties every note")
s = P("C- D")
check(notes(s, 2) == "62" and near(s.chords[1].lens[1], 1), "tie to a different pitch is dropped")
s = P("C4- | C2 D")
check(#s.chords[2].notes == 0 and near(s.chords[1].lens[1], 6), "tie across a bar line")
s = P("[C-E]2[A,C]2")
check(notes(s, 2) == "57" and near(s.chords[1].lens[1], 4) and near(s.chords[1].lens[2], 2), "chord ties pair by pitch, not position")
s = P("[C-^C-]2[=C^C]2")
check(#s.chords[2].notes == 0 and near(s.chords[1].lens[1], 4) and near(s.chords[1].lens[2], 4), "tied C and C# are separate notes")
s = P("^C2-|^C2C2")
check(seq(s) == "61,,61" and near(s.chords[1].lens[1], 4) and near(s.chords[3].lens[1], 2), "an accidental on a tied continuation carries through its bar")

-- broken rhythm and tuplets
s = P("C>D E<F")
check(near(s.chords[1].beats, 1.5) and near(s.chords[2].beats, 0.5) and near(s.chords[3].beats, 0.5) and near(s.chords[4].beats, 1.5), "> and <")
s = P("(3CDE F")
check(near(s.chords[1].beats, 2 / 3) and near(s.chords[3].beats, 2 / 3) and near(s.chords[4].beats, 1), "(3 triplet")
check(near(P("(3:2:3CDE").chords[1].beats, 2 / 3), "(p:q:r")
check(near(P("(5CDEFG").chords[1].beats, 2 / 5), "(5 in simple meter")

-- repeats and endings
check(seq(P("|: C D :| E")) == "60,62,60,62,64", "repeat")
check(seq(P("C D :| E")) == "60,62,60,62,64", "repeat from the start")
check(seq(P("|: C |1 D :|2 E |]")) == "60,62,60,64", "first and second endings")
check(seq(P("|: C [1 D :| [2 E |]")) == "60,62,60,64", "endings written [1 [2")
check(seq(P("|: C :: D :|")) == "60,60,62,62", ":: ends one repeat and starts the next")
check(seq(P("C :| :| :| D")) == "60,60,62", "extra :| don't loop again")

-- tempo
check(P("C", "Q:1/4=90\n").bpm == 90 and S.tempoOf(tune("C", "Q:1/4=90\n")) == 90, "Q:1/4=90")
check(P("C", "Q:3/8=40\n").bpm == 60, "Q:3/8=40 is 60 quarter notes a minute")
check(P("C", "Q:100\n").bpm == 100, "bare Q: is quarter notes a minute")
check(P("C", 'Q:"Allegro" 1/4=132\n').bpm == 132, "Q: with text")
check(P("C").bpm == 120 and S.tempoOf(tune("C")) == 120, "default tempo 120")
s = P("C [Q:1/4=60] D", "Q:1/4=120\n")
check(s.chords[1].qpm == 120 and s.chords[2].qpm == 60, "inline tempo change")
s = P("C [Q:1/4=60] D", "Q:1/4=120\n", 240)
check(s.bpm == 240 and s.chords[1].qpm == 240 and s.chords[2].qpm == 120, "the BPM field scales every tempo")
s = P("C [Q:1/4=60] D")
check(s.bpm == 120 and s.chords[1].qpm == 120 and s.chords[2].qpm == 60, "no Q: header: starts at 120 even if the tempo changes later")
check(P("C", "Q:1/4=99999\n").bpm == 600 and P("C", nil, 1).bpm == 12, "tempo clamped")

-- skipped notation
s = P('"Am"C !trill!D +f+E ~F .G {ag}A (B c) \\\nd % comment C\nw: lyrics C D E')
check(seq(s) == "60,62,64,65,67,69,71,72,74", "decorations, chord symbols, grace notes, slurs, comments, lyrics skipped")
s = S.parse("X:1\nT:Title\nC:Composer\nR:reel\nL:1/4\n%%score 1\nK:C\nC")
check(#s.chords == 1 and s.title == "Title", "other fields and directives skipped")

-- drums
s = S.parse("X:1\nT:Drums\n%%MIDI channel 10\nL:1/4\nK:C\nB,,, D,,")
check(s.drums and seq(s) == "35,38", "%%MIDI channel 10 marks a drum part")
check(not P("C").drums, "melodies are not drums")
s = S.parse("%abc-2.1\n%%MIDI channel 10\n\nX:1\nL:1/4\nK:C\nC")
check(s.drums, "channel 10 in the file header applies to the tune")
s = S.parse("X:1\n%%MIDI channel 10\n%%percmap C 36\n%%percmap D acoustic-snare\nL:1/4\nK:C\nC D E")
check(seq(s) == "36,38,64", "%%percmap by number and by name")

-- limits and junk
s = P(string.rep("C", 10001))
check(s.events == S.MAX_EVENTS and s.warnings[1].key == "TooManyNotes", "events capped at MAX_EVENTS")
s = P(string.rep("|: C :| ", 6000))
check(s.events <= S.MAX_EVENTS, "repeat expansion is capped too")
s = S.parse("hello\nthis is not abc")
check(#s.chords == 0 and s.warnings[1].key == "NotAbc", "text without a tune")
s = S.parse("X:1\nT:No key\nC D E")
check(#s.chords == 0 and s.warnings[1].key == "NotAbc", "a tune without K: is not played")
check(seq(S.parse("\239\187\191X:1\nL:1/4\nK:C\nC")) == "60", "BOM before X:")
check(seq(P("C \r\nD\226\153\170 E")) == "60,62,64", "crlf and junk characters")
for _, junk in ipairs({ "[[[[", "((((((", "(0C", "(99C", "C/0", "C0", "[K:", "[Q:1/0=0]", "|1", ":|2", "Z0", "^",
    "{CDE", "\"unclosed", "!unclosed", "[CE", "C>>>>>>D", "[]2", "-" }) do
    check(pcall(S.parse, tune(junk)), "no error on " .. junk)
end
check(seq(P("C,,,,,,,,,,,,,,")) == "0" and seq(P("c''''''''''''''")) == "127", "pitch kept within MIDI 0-127")

-- parts
local band = "%abc-2.1\n%%song-title Test\nX:1\nT:Lead\nL:1/4\nK:C\nC D\n\nX:2\nT:Bass\nL:1/4\nK:C\nC, D,\n"
local parts = S.parts(band)
check(#parts == 2 and parts[1].title == "Lead" and parts[2].title == "Bass", "one part per X: tune")
check(seq(S.parse(parts[2].text)) == "48,50", "a part parses on its own")
local voices = "X:1\nT:Duet\nL:1/4\nK:C\nV:1 name=\"Upper\"\nC D\nV:2 name=\"Lower\"\nC, D,\nV:1\nE\n"
parts = S.parts(voices)
check(#parts == 2 and parts[1].title == "Duet: Upper" and parts[2].title == "Duet: Lower", "one part per V: voice")
check(seq(S.parse(parts[1].text)) == "60,62,64" and seq(S.parse(parts[2].text)) == "48,50", "each voice keeps only its music")
check(#S.parts("X:1\nK:C\nC") == 1 and S.parts("X:1\nK:C\nC")[1].title == "1", "untitled tune named by its number")
check(#S.parts("no tune here") == 0, "no parts without X:")
check(S.parts("%%MIDI channel 10\nX:1\nK:C\nC")[1].text:find("%%MIDI channel 10", 1, true) ~= nil, "a part keeps the file header's channel 10")

-- compact: what travels
local messy = "X:1\nT:Song % comment\n%%MIDI channel 10\nL:1/4\nK:C\n% a comment line\nC D   \n\nw: la la\nE\n"
local c = S.compact(messy)
check(c == "X:1\nT:Song\n%%MIDI channel 10\nL:1/4\nK:C\nC D\nE", "compact drops comments, lyrics, blank lines and trailing spaces")
check(seq(S.parse(c)) == seq(S.parse(messy)) and S.parse(c).drums, "compact text plays exactly like the original")

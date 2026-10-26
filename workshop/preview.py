"""Draws workshop/preview.png (256x256, required by the PZ Workshop uploader).

Uses the game's own item icons, read from your Project Zomboid install and scaled
by whole numbers so the pixel art stays crisp. Run: python workshop/preview.py [game dir]
"""
import pathlib
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pzpack import read_pack  # noqa: E402

GAME = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "E:/SteamLibrary/steamapps/common/ProjectZomboid")
OUT = pathlib.Path(__file__).with_name("preview.png")
FONT = "C:/Windows/Fonts/seguibl.ttf"
S = 256
MOODLES = ("Moodle_Icon_Bored", "Moodle_Icon_Stressed", "Moodle_Icon_Unhappy", "Moodle_Icon_Angry", "Moodle_Icon_Panic")


def icons(*names):
    wanted, found = set(names), {}
    for pack in ("UI2.pack", "UI.pack"):
        for _, page, entries in read_pack(GAME / "media/texturepacks" / pack):
            for name, x, y, w, h, ox, oy, fw, fh in entries:
                if name in wanted and name not in found:
                    full = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
                    full.paste(page.crop((x, y, x + w, y + h)), (ox, oy))
                    found[name] = full
    missing = wanted - found.keys()
    assert not missing, f"icons not found: {missing}"
    return found


def scaled(img, k):
    return img.resize((img.width * k, img.height * k), Image.Resampling.NEAREST)


def place(canvas, img, x, y):
    """Pastes img with its bottom-centre at (x, y), with a soft ground shadow."""
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([x - img.width * 0.42, y - 7, x + img.width * 0.42, y + 5], fill=(0, 0, 0, 120))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3)))
    canvas.alpha_composite(img, (x - img.width // 2, y - img.height))


def note(d, x, y, col):
    """A pixel eighth note: head, stem, flag."""
    d.ellipse([x, y + 10, x + 7, y + 15], fill=col)
    d.rectangle([x + 6, y, x + 7, y + 12], fill=col)
    d.line([(x + 7, y), (x + 12, y + 5)], fill=col, width=2)


def main():
    ic = icons("Item_GuitarAcoustic", "Item_Violin", "Item_Trumpet", "Item_Harmonica", "Moodle_Bkg_Bad_4", *MOODLES)
    random.seed(5)
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    # Dusk sky over a dark field, campfire glow from below.
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=(int(30 + 70 * t), int(26 + 20 * t), int(54 - 20 * t), 255))
    d.rectangle([0, 196, S, S], fill=(34, 40, 26, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([60, 170, 196, 250], fill=(255, 150, 60, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))

    place(img, scaled(ic["Item_GuitarAcoustic"], 4), 92, 232)
    place(img, scaled(ic["Item_Violin"], 3), 176, 226)
    place(img, scaled(ic["Item_Trumpet"], 3), 210, 250)
    place(img, scaled(ic["Item_Harmonica"], 3), 40, 248)

    # what a level-0 player's audience looks like: maxed-out bad moodles down the right edge, as in the game
    for i, name in enumerate(MOODLES):
        y = 6 + i * 34
        img.alpha_composite(ic["Moodle_Bkg_Bad_4"], (S - 38, y))
        img.alpha_composite(ic[name], (S - 38, y))

    for x, y in [(40, 70), (72, 96), (118, 64), (160, 92), (196, 70), (24, 120)]:
        note(d, x, y, (250, 236, 200, 255))

    font = ImageFont.truetype(FONT, 40)
    text = "PLAY IT!"
    w = d.textlength(text, font=font)
    d.text(((S - 44 - w) / 2, 8), text, font=font, fill=(255, 244, 220, 255), stroke_width=3, stroke_fill=(40, 20, 30, 255))
    img.convert("RGB").save(OUT, optimize=True)
    print(OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()

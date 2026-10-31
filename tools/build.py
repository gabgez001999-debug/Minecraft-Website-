"""Baut die Zeus-Mod-Pakete.

Für jede Mod in mods/<id>/ entsteht (plus dist/create_zeus_resources.zip, das Ressourcenpaket):
  dist/<id>.zip   metadata.json + icon.png + main.lua (Import im Mods-Menü)
  dist/<id>.lua   Einzeldatei-Variante (Kopfkommentare -- name/id/version reichen dem Client)

Icons (64x64, vom Client verlangt) werden hier gezeichnet, falls sie fehlen.
Aufruf: python tools/build.py
"""
import json
import math
import pathlib
import shutil
import zipfile

from PIL import Image, ImageDraw

import build_pack

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODS = ROOT / "mods"
DIST = ROOT / "dist"


def gear_icon(path):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, 63, 63), radius=12, fill=(38, 34, 30, 255))
    cx, cy = 32, 32
    teeth = 10
    pts = []
    for i in range(teeth * 2):
        a = math.pi * 2 * i / (teeth * 2)
        r = 26 if i % 2 == 0 else 20
        for da in (-0.13, 0.13):
            pts.append((cx + r * math.cos(a + da), cy + r * math.sin(a + da)))
    d.polygon(pts, fill=(201, 150, 64, 255), outline=(120, 82, 30, 255))
    d.ellipse((cx - 13, cy - 13, cx + 13, cy + 13), fill=(150, 104, 44, 255))
    d.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=(170, 172, 168, 255), outline=(90, 92, 90, 255))
    d.rectangle((cx - 2, cy - 2, cx + 2, cy + 2), fill=(70, 72, 70, 255))
    img.save(path)


def phone_icon(path):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, 63, 63), radius=12, fill=(24, 30, 44, 255))
    d.rounded_rectangle((18, 6, 46, 58), radius=6, fill=(20, 20, 24, 255), outline=(140, 150, 170, 255), width=2)
    d.rectangle((21, 12, 43, 50), fill=(58, 160, 220, 255))
    for row in range(3):
        for col in range(3):
            x, y = 23 + col * 7, 15 + row * 8
            d.rounded_rectangle((x, y, x + 5, y + 5), radius=1, fill=(240, 246, 255, 255))
    d.rectangle((23, 40, 41, 47), fill=(255, 210, 90, 255))
    d.ellipse((30, 52, 34, 56), fill=(140, 150, 170, 255))
    img.save(path)


ICONS = {"create_zeus": gear_icon, "mc_device_zeus": phone_icon}


def build():
    DIST.mkdir(exist_ok=True)
    for mod_dir in sorted(p for p in MODS.iterdir() if p.is_dir()):
        meta = json.loads((mod_dir / "metadata.json").read_text(encoding="utf-8"))
        mod_id = meta["id"]
        icon = mod_dir / "icon.png"
        if not icon.exists() and mod_id in ICONS:
            ICONS[mod_id](icon)
        assert Image.open(icon).size == (64, 64), f"{icon} muss 64x64 sein"
        main = mod_dir / meta.get("main", "main.lua")
        out = DIST / f"{mod_id}.zip"
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(mod_dir / "metadata.json", "metadata.json")
            z.write(icon, "icon.png")
            z.write(main, "main.lua")
        shutil.copyfile(main, DIST / f"{mod_id}.lua")
        print(f"{out.relative_to(ROOT)}  ({out.stat().st_size} Bytes)")


def build_resourcepack():
    build_pack.build()
    out = DIST / "create_zeus_resources.zip"
    src = ROOT / "resourcepack"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(src).as_posix())
    print(f"{out.relative_to(ROOT)}  ({out.stat().st_size} Bytes)")


if __name__ == "__main__":
    build()
    build_resourcepack()

"""Erzeugt das Ressourcenpaket für den Create-Port (eigene Modelle und Texturen im Create-Stil).

Ausgabe: resourcepack/  (pack.mcmeta, pack.png, assets/create_zeus/...)
Keine Create-Assets: alle Texturen werden hier prozedural gezeichnet, alle Modelle hier definiert.
Aufruf: python tools/build_pack.py
"""
import json
import math
import pathlib
import random
import shutil

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "resourcepack"
NS = "create_zeus"
A = OUT / "assets" / NS


# ---------------------------------------------------------------------------
# Texturen (16x16)
# ---------------------------------------------------------------------------
def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3] if len(c) > 3 else 255,)


def noise_fill(img, base, amt, seed):
    rnd = random.Random(seed)
    px = img.load()
    for y in range(16):
        for x in range(16):
            px[x, y] = shade(base, 1 + (rnd.random() * 2 - 1) * amt)


def tex_axis():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (178, 178, 170), 0.05, 1)
    px = img.load()
    for y in range(16):
        for x in range(16):
            if x in (5, 10):
                px[x, y] = (120, 120, 116, 255)
            if (y % 4) == 0 and 5 < x < 10:
                px[x, y] = (205, 205, 196, 255)
    return img


def tex_axis_top():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (150, 150, 144), 0.05, 2)
    d = ImageDraw.Draw(img)
    d.rectangle((5, 5, 10, 10), fill=(190, 190, 182, 255), outline=(110, 110, 106, 255))
    d.point((7, 7), fill=(230, 230, 222, 255))
    return img


def tex_wood(base, seed, dark_edge=True):
    img = Image.new("RGBA", (16, 16))
    rnd = random.Random(seed)
    px = img.load()
    for y in range(16):
        band = 0.92 + 0.12 * math.sin(y * 1.3 + seed)
        for x in range(16):
            px[x, y] = shade(base, band * (1 + (rnd.random() * 2 - 1) * 0.05))
    if dark_edge:
        for i in range(16):
            for (x, y) in ((i, 0), (i, 15), (0, i), (15, i)):
                px[x, y] = shade(base, 0.62)
    return img


def tex_casing():
    """Andesit-Gehäuse: grauer Stein mit Holzrahmen und Messingnieten."""
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (140, 141, 136), 0.07, 3)
    px = img.load()
    wood = (150, 108, 62, 255)
    for i in range(16):
        for (x, y) in ((i, 0), (i, 1), (i, 14), (i, 15), (0, i), (1, i), (14, i), (15, i)):
            px[x, y] = shade(wood, 0.85 + 0.15 * ((x + y) % 3 == 0))
    for (x, y) in ((2, 2), (13, 2), (2, 13), (13, 13)):
        px[x, y] = (226, 182, 82, 255)
    return img


def tex_gearbox():
    img = tex_casing()
    d = ImageDraw.Draw(img)
    d.ellipse((4, 4, 11, 11), fill=(70, 70, 68, 255), outline=(110, 110, 106, 255))
    d.rectangle((6, 6, 9, 9), fill=(178, 178, 170, 255))
    return img


def tex_brass():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (214, 164, 70), 0.06, 4)
    px = img.load()
    for x in range(16):
        px[x, 0] = (245, 210, 120, 255)
        px[x, 15] = (150, 104, 40, 255)
    return img


def tex_motor():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (150, 88, 190), 0.06, 5)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 15, 15), outline=(90, 50, 120, 255))
    for y in (4, 8, 12):
        d.line((3, y, 12, y), fill=(200, 150, 240, 255))
    return img


def tex_iron(seed=6):
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (205, 208, 212), 0.05, seed)
    px = img.load()
    for y in range(16):
        x = (y * 2) % 16
        px[x, y] = (150, 152, 158, 255)
        px[(x + 1) % 16, y] = (170, 172, 178, 255)
    return img


def tex_stone():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (132, 130, 126), 0.09, 7)
    d = ImageDraw.Draw(img)
    d.ellipse((2, 2, 13, 13), outline=(100, 98, 95, 255))
    d.ellipse((6, 6, 9, 9), fill=(90, 88, 85, 255))
    return img


def tex_gauge():
    img = tex_casing()
    d = ImageDraw.Draw(img)
    d.ellipse((3, 3, 12, 12), fill=(238, 232, 214, 255), outline=(150, 108, 62, 255))
    d.line((7, 8, 10, 4), fill=(200, 40, 40, 255))
    d.point((7, 8), fill=(30, 30, 30, 255))
    return img


def tex_wrench():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(9):
        d.point((3 + i, 12 - i), fill=(150, 108, 62, 255))
        d.point((4 + i, 12 - i), fill=(110, 78, 44, 255))
    d.rectangle((11, 1, 14, 4), fill=(214, 164, 70, 255))
    d.point((13, 2), fill=(0, 0, 0, 0))
    d.point((12, 2), fill=(0, 0, 0, 0))
    d.rectangle((1, 12, 4, 15), fill=(214, 164, 70, 255))
    return img


def tex_grill():
    """Lüftergitter: Rahmen mit transparenten Schlitzen."""
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y in range(16):
        for x in range(16):
            edge = x < 2 or y < 2 or x > 13 or y > 13
            bar = (y % 3 == 0)
            if edge:
                px[x, y] = (150, 108, 62, 255)
            elif bar:
                px[x, y] = (120, 120, 116, 255)
    return img


def tex_copper():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (196, 110, 70), 0.07, 21)
    d = ImageDraw.Draw(img)
    for y in range(2, 15, 3):
        d.line((1, y, 14, y), fill=(232, 150, 100, 255))
    d.rectangle((0, 0, 15, 15), outline=(120, 64, 40, 255))
    return img


def tex_cannon():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (58, 58, 64), 0.08, 22)
    px = img.load()
    for x in range(16):
        px[x, 3] = (90, 90, 98, 255)
        px[x, 12] = (90, 90, 98, 255)
    return img


def tex_sail():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (236, 232, 222), 0.03, 23)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 15, 15), outline=(150, 108, 62, 255))
    return img


def tex_solar():
    img = Image.new("RGBA", (16, 16), (40, 52, 90, 255))
    d = ImageDraw.Draw(img)
    for x in range(0, 16, 4):
        for y in range(0, 16, 4):
            d.rectangle((x + 1, y + 1, x + 3, y + 3), fill=(52, 92, 170, 255))
            d.point((x + 1, y + 1), fill=(150, 190, 240, 255))
    d.rectangle((0, 0, 15, 15), outline=(170, 172, 168, 255))
    return img


def tex_enchant():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (70, 30, 90), 0.1, 31)
    px = img.load()
    rnd = random.Random(32)
    for _ in range(14):
        px[rnd.randrange(16), rnd.randrange(16)] = (200, 140, 255, 255)
    return img


def tex_xp():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (60, 110, 60), 0.08, 33)
    d = ImageDraw.Draw(img)
    for y in range(2, 16, 4):
        d.line((1, y, 14, y), fill=(30, 50, 30, 255))
    d.ellipse((5, 5, 10, 10), fill=(170, 240, 90, 255))
    return img


def tex_accent(color, seed):
    img = tex_casing()
    d = ImageDraw.Draw(img)
    d.rectangle((3, 6, 12, 9), fill=color)
    d.rectangle((6, 3, 9, 12), fill=shade(color, 0.8))
    return img


def tex_chain():
    img = tex_casing()
    d = ImageDraw.Draw(img)
    for y in range(3, 13, 3):
        d.rectangle((6, y, 9, y + 1), fill=(90, 92, 98, 255))
        d.point((7, y + 2), fill=(60, 62, 66, 255))
    return img


def tex_blade():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, 15, 15), fill=(196, 198, 204, 255), outline=(120, 122, 128, 255))
    for i in range(8):
        a = math.pi * 2 * i / 8
        d.line((8, 8, 8 + 7 * math.cos(a), 8 + 7 * math.sin(a)), fill=(150, 152, 158, 255))
    d.ellipse((6, 6, 9, 9), fill=(90, 92, 98, 255))
    return img


def tex_crush():
    img = Image.new("RGBA", (16, 16))
    noise_fill(img, (110, 108, 104), 0.12, 41)
    d = ImageDraw.Draw(img)
    for x in range(0, 16, 4):
        d.line((x, 0, x, 15), fill=(80, 78, 75, 255))
    return img


def tex_wood_top():
    img = tex_wood((168, 128, 78), 42)
    d = ImageDraw.Draw(img)
    d.ellipse((5, 5, 10, 10), fill=(120, 120, 116, 255))
    return img


TEXTURES = {
    "block/clutch": lambda: tex_accent((200, 50, 40, 255), 43), "block/gearshift": lambda: tex_accent((60, 120, 210, 255), 44),
    "block/chain": tex_chain, "block/saw_blade": tex_blade, "block/crush": tex_crush, "block/bearing_wood": tex_wood_top,
    "block/solar": tex_solar, "block/enchant": tex_enchant, "block/xp": tex_xp,
    "block/fan_grill": tex_grill, "block/copper_coil": tex_copper, "block/cannon": tex_cannon, "block/sail": tex_sail,
    "block/axis": tex_axis, "block/axis_top": tex_axis_top,
    "block/cogwheel": lambda: tex_wood((178, 132, 80), 11),
    "block/large_cogwheel": lambda: tex_wood((112, 78, 46), 12),
    "block/water_wheel": lambda: tex_wood((168, 128, 78), 13, dark_edge=False),
    "block/andesite_casing": tex_casing, "block/gearbox": tex_gearbox, "block/brass": tex_brass,
    "block/creative_motor": tex_motor, "block/drill": tex_iron, "block/propeller": lambda: tex_iron(9),
    "block/millstone": tex_stone, "block/gauge": tex_gauge, "item/wrench": tex_wrench,
}


# ---------------------------------------------------------------------------
# Modelle (Drehachse aller drehenden Modelle = Y)
# ---------------------------------------------------------------------------
def box(frm, to, tex, rot=None, end_tex=None, uv_full=False, axis="y", origin=(8, 8, 8)):
    faces = {}
    ends = ("up", "down") if axis == "y" else (("north", "south") if axis == "z" else ("east", "west"))
    for f in ("north", "south", "east", "west", "up", "down"):
        t = end_tex if (end_tex and f in ends) else tex
        face = {"texture": "#" + t}
        if uv_full or any(v < 0 or v > 16 for v in frm + to):
            face["uv"] = [0, 0, 16, 16]
        faces[f] = face
    el = {"from": frm, "to": to, "faces": faces}
    if rot is not None and rot != 0:
        el["rotation"] = {"origin": list(origin), "axis": axis, "angle": rot}
    return el


BLOCK_DISPLAY = {
    "gui": {"rotation": [30, 225, 0], "scale": [0.625, 0.625, 0.625]},
    "ground": {"translation": [0, 3, 0], "scale": [0.25, 0.25, 0.25]},
    "fixed": {"scale": [0.5, 0.5, 0.5]},
    "thirdperson_righthand": {"rotation": [75, 45, 0], "translation": [0, 2.5, 0], "scale": [0.375, 0.375, 0.375]},
    "firstperson_righthand": {"rotation": [0, 45, 0], "scale": [0.4, 0.4, 0.4]},
    "firstperson_lefthand": {"rotation": [0, 225, 0], "scale": [0.4, 0.4, 0.4]},
}


def scaled_display(s):
    d = json.loads(json.dumps(BLOCK_DISPLAY))
    for v in d.values():
        v["scale"] = [x * s for x in v["scale"]]
    return d


def model(textures, elements, display=None):
    m = {"textures": {"particle": f"{NS}:block/" + list(textures.values())[0]}, "elements": elements}
    m["textures"].update({k: f"{NS}:block/{v}" for k, v in textures.items()})
    m["display"] = display or BLOCK_DISPLAY
    return m


def teeth(r_out, y0, y1, width, tex, angles=(0, 22.5, 45, -22.5)):
    return [box([8 - r_out, y0, 8 - width / 2], [8 + r_out, y1, 8 + width / 2], tex, rot=a) for a in angles]


SHAFT = box([6, 0, 6], [10, 16, 10], "axis", end_tex="axis_top")
AX = {"axis": "axis", "axis_top": "axis_top"}

# Gleiche Ausrichtung wie die Original-Create-Modelle (siehe tools/create_models.json):
#   Wellen/Zahnräder/Kurbel/Mahlstein: Achse Y · Bohrkopf/Propeller: Achse Z, Spitze nach +Z
#   Gehäuse von Bohrer/Lüfter: Vorderseite oben
MODELS = {
    "d_shaft": model(AX, [SHAFT]),
    "d_cog": model({"wood": "cogwheel", **AX}, [
        SHAFT,
        box([2, 5.5, 2], [14, 10.5, 14], "wood"),
        box([2, 5.5, 2], [14, 10.5, 14], "wood", rot=45),
        *teeth(8, 6, 10, 2, "wood"),
    ]),
    "d_lcog": model({"wood": "large_cogwheel", **AX}, [
        SHAFT,
        *[box([-8, 5.5, -8], [24, 10.5, 24], "wood", rot=a) for a in (0, 45, 22.5, -22.5)],
        *teeth(16, 6, 10, 3, "wood"),
    ], display=scaled_display(0.45)),
    "d_gearbox": model({"casing": "gearbox"}, [box([0, 0, 0], [16, 16, 16], "casing")]),
    "d_gauge": model({"casing": "gauge"}, [box([0, 0, 0], [16, 16, 16], "casing")]),
    "d_cmotor": model({"motor": "creative_motor", "casing": "andesite_casing"}, [
        box([3, 2, 3], [13, 12, 13], "motor"),
        box([2, 0, 2], [14, 2, 14], "casing"),
        box([2, 12, 2], [14, 14, 14], "casing"),
    ]),
    "d_crank": model({"wood": "cogwheel", "brass": "brass", **AX}, [
        box([6, 0, 6], [10, 5, 10], "axis", end_tex="axis_top"),
        box([5, 5, 5], [11, 8, 11], "brass"),
        box([7, 6, 2], [9, 8, 14], "wood"),
        box([6.5, 6, 12], [9.5, 13, 15], "brass"),
    ]),
    "d_wheel": model({"wood": "water_wheel", **AX}, [
        SHAFT,
        box([3, 3, 3], [13, 13, 13], "wood"),
        *[box([-12, 2, 7], [28, 14, 9], "wood", rot=a) for a in (0, 45)],
        *[box([7, 2, -12], [9, 14, 28], "wood", rot=a) for a in (0, 45)],
        *[box([-10, 7, -10], [26, 9, 26], "wood", rot=a) for a in (22.5, -22.5)],
    ], display=scaled_display(0.45)),
    "d_drill_c": model({"casing": "andesite_casing", "top": "drill"}, [
        box([0, 0, 0], [16, 10, 16], "casing", end_tex="top"),
    ]),
    "d_drill_h": model({"drill": "drill", **AX}, [
        box([6, 6, 0], [10, 10, 9], "axis", end_tex="axis_top", axis="z"),
        box([3, 3, 9], [13, 13, 12], "drill", rot=45, axis="z"),
        box([4, 4, 12], [12, 12, 15], "drill", axis="z"),
        box([5, 5, 15], [11, 11, 18], "drill", rot=45, axis="z"),
        box([6.5, 6.5, 18], [9.5, 9.5, 20], "drill", axis="z"),
    ]),
    "d_fan_c": model({"casing": "andesite_casing", "back": "gearbox", "grill": "fan_grill"}, [
        box([0, 0, 0], [2, 16, 16], "casing"), box([14, 0, 0], [16, 16, 16], "casing"),
        box([2, 0, 0], [14, 16, 2], "casing"), box([2, 0, 14], [14, 16, 16], "casing"),
        box([2, 0, 2], [14, 2, 14], "back"),
        box([2, 15, 2], [14, 15.5, 14], "grill"),
    ]),
    "d_prop": model({"blade": "propeller", **AX}, [
        box([6, 6, 1.2], [10, 10, 8], "axis", end_tex="axis_top", axis="z"),
        box([0.5, 6.5, 4], [15.5, 9.5, 12], "blade", rot=22.5, axis="z"),
        box([6.5, 0.5, 4], [9.5, 15.5, 12], "blade", rot=22.5, axis="z"),
    ]),
    "d_press_c": model({"casing": "andesite_casing"}, [box([0, 2, 0], [16, 16, 16], "casing")]),
    "d_press_h": model({"iron": "drill", **AX}, [
        box([1, 0, 1], [15, 3, 15], "iron"),
        box([6, 3, 6], [10, 16, 10], "axis", end_tex="axis_top"),
    ]),
    "d_mill_b": model({"casing": "andesite_casing"}, [box([0, 0, 0], [16, 6, 16], "casing")]),
    "d_mill_i": model({"stone": "millstone", **AX}, [
        box([6, 0, 6], [10, 8, 10], "axis", end_tex="axis_top"),
        box([1, 6, 1], [15, 12, 15], "stone"),
        box([1, 6, 1], [15, 12, 15], "stone", rot=45),
    ]),
}

# Addon-Modelle (gibt es in Create nicht, daher immer aus diesem Paket)
MODELS.update({
    "d_cannon": model({"metal": "cannon", "casing": "andesite_casing"}, [
        box([2, 0, 2], [14, 4, 14], "casing"),
        box([4, 4, 4], [12, 26, 12], "metal"),
        box([3, 22, 3], [13, 25, 13], "metal"),
        box([3, 8, 3], [13, 11, 13], "metal"),
    ]),
    "d_alt": model({"coil": "copper_coil", "casing": "andesite_casing"}, [
        box([0, 0, 0], [16, 2, 16], "casing"), box([0, 14, 0], [16, 16, 16], "casing"),
        box([2, 2, 2], [14, 14, 14], "coil"),
    ]),
    "d_emotor": model({"coil": "copper_coil", "casing": "andesite_casing", "brass": "brass"}, [
        box([2, 0, 2], [14, 3, 14], "casing"),
        box([3, 3, 3], [13, 13, 13], "coil"),
        box([4, 13, 4], [12, 15, 12], "brass"),
    ]),
    "d_bearing": model({"casing": "andesite_casing", "top": "brass"}, [
        box([0, 0, 0], [16, 12, 16], "casing"), box([2, 12, 2], [14, 16, 14], "top"),
    ]),
    "d_bprop": model({"sail": "sail", **AX}, [
        box([6, 0, 6], [10, 8, 10], "axis", end_tex="axis_top"),
        *[box([-14, 6, 6], [30, 7.5, 10], "sail", rot=a) for a in (22.5, -22.5)],
        *[box([6, 6, -14], [10, 7.5, 30], "sail", rot=a) for a in (22.5, -22.5)],
    ], display=scaled_display(0.4)),
    "d_enchanter": model({"casing": "andesite_casing", "top": "enchant", "brass": "brass"}, [
        box([0, 0, 0], [16, 12, 16], "casing", end_tex="top"),
        box([3, 12, 3], [13, 13, 13], "brass"),
        box([4, 13, 5], [12, 15, 11], "top"),
    ]),
    "d_xp_drain": model({"casing": "andesite_casing", "top": "xp"}, [
        box([0, 0, 0], [16, 13, 16], "casing", end_tex="top"),
    ]),
    "d_solar": model({"cell": "solar", "casing": "andesite_casing"}, [
        box([0, 0, 0], [16, 2, 16], "casing"),
        box([1, 2, 1], [15, 3, 15], "cell"),
        box([7, 0, 7], [9, 2, 9], "casing"),
    ]),
    "d_battery": model({"coil": "copper_coil", "casing": "andesite_casing", "brass": "brass"}, [
        box([2, 0, 2], [14, 14, 14], "coil"),
        box([1, 0, 1], [15, 2, 15], "casing"), box([1, 12, 1], [15, 14, 15], "casing"),
        box([6, 14, 6], [10, 16, 10], "brass"),
    ]),
    # weitere Create-Kernblöcke (Achse Y; Gehäuse mit Wellenenden oben/unten)
    "d_encased": model({"casing": "andesite_casing", "end": "axis_top"}, [
        box([0, 0.01, 0], [16, 15.99, 16], "casing"),
        box([6, 0, 6], [10, 16, 10], "end", uv_full=True),
    ]),
    "d_clutch": model({"casing": "clutch", "end": "axis_top"}, [
        box([-0.02, -0.02, -0.02], [16.02, 16.02, 16.02], "casing"),
    ]),
    "d_gearshift": model({"casing": "gearshift"}, [
        box([-0.02, -0.02, -0.02], [16.02, 16.02, 16.02], "casing"),
    ]),
    "d_chain": model({"casing": "chain"}, [box([0, 0, 0], [16, 16, 16], "casing")]),
    "d_saw_c": model({"casing": "andesite_casing", "top": "saw_blade"}, [
        box([0, 0, 0], [16, 10, 16], "casing"),
    ]),
    "d_saw_blade": model({"blade": "saw_blade", **AX}, [
        box([6, 0, 6], [10, 6, 10], "axis", end_tex="axis_top"),
        box([0, 6, 0], [16, 7, 16], "blade"),
        box([0, 6, 0], [16, 7, 16], "blade", rot=45),
    ]),
    "d_crush": model({"stone": "crush", **AX}, [
        SHAFT,
        *[box([-4, 2, -4], [20, 14, 20], "stone", rot=a) for a in (0, 22.5, 45, -22.5)],
    ], display=scaled_display(0.5)),
    "d_wbearing": model({"casing": "andesite_casing", "top": "bearing_wood"}, [
        box([0, 0, 0], [16, 12, 16], "casing"), box([1, 12, 1], [15, 16, 15], "top"),
    ]),
    "d_windmill": model({"sail": "sail", "wood": "water_wheel", **AX}, [
        box([6, 0, 6], [10, 6, 10], "axis", end_tex="axis_top"),
        box([-16, 5, 7], [32, 6, 9], "wood"), box([7, 5, -16], [9, 6, 32], "wood"),
        box([-15, 6, 4], [3, 6.5, 12], "sail"), box([13, 6, 4], [31, 6.5, 12], "sail"),
        box([4, 6, -15], [12, 6.5, 3], "sail"), box([4, 6, 13], [12, 6.5, 31], "sail"),
    ], display=scaled_display(0.3)),
    "d_sail": model({"sail": "sail"}, [box([0, 7, 0], [16, 9, 16], "sail")]),
})

# Item-Definitionen: Name -> Liste von Modellen (mehrere = composite)
ITEMS = {
    # drehende/feste Teile für Display-Entities
    **{k: [k] for k in MODELS},
    "d_speedo": ["d_gauge"], "d_stresso": ["d_gauge"],
    # Inventar-Items
    "shaft": ["d_shaft"], "cogwheel": ["d_cog"], "large_cogwheel": ["d_lcog"],
    "gearbox": ["d_gearbox"], "hand_crank": ["d_crank"], "water_wheel": ["d_wheel"],
    "creative_motor": ["d_cmotor"], "mechanical_drill": ["d_drill_c", "d_drill_h"],
    "encased_fan": ["d_fan_c"], "mechanical_press": ["d_press_c", "d_press_h"],
    "millstone": ["d_mill_b", "d_mill_i"], "speedometer": ["d_gauge"], "stressometer": ["d_gauge"],
    "cannon": ["d_cannon"], "alternator": ["d_alt"], "electric_motor": ["d_emotor"],
    "propeller_bearing": ["d_bearing", "d_bprop"],
    "encased_shaft": ["d_encased"], "clutch": ["d_clutch"], "gearshift": ["d_gearshift"], "chain_drive": ["d_chain"],
    "mechanical_saw": ["d_saw_c", "d_saw_blade"], "crushing_wheel": ["d_crush"], "windmill_bearing": ["d_wbearing", "d_windmill"],
    "sail": ["d_sail"],
    "enchanter": ["d_enchanter"], "xp_drain": ["d_xp_drain"], "solar_panel": ["d_solar"], "battery": ["d_battery"],
}


def item_def(models):
    if len(models) == 1:
        return {"model": {"type": "minecraft:model", "model": f"{NS}:block/{models[0]}"}}
    return {"model": {"type": "minecraft:composite",
                      "models": [{"type": "minecraft:model", "model": f"{NS}:block/{m}"} for m in models]}}


def pack_icon(path):
    img = Image.new("RGBA", (64, 64), (38, 34, 30, 255))
    d = ImageDraw.Draw(img)
    cx = cy = 32
    pts = []
    for i in range(20):
        a = math.pi * 2 * i / 20
        r = 27 if i % 2 == 0 else 21
        for da in (-0.13, 0.13):
            pts.append((cx + r * math.cos(a + da), cy + r * math.sin(a + da)))
    d.polygon(pts, fill=(201, 150, 64, 255))
    d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=(170, 172, 168, 255))
    img.save(path)


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    (A / "textures" / "block").mkdir(parents=True)
    (A / "textures" / "item").mkdir(parents=True)
    (A / "models" / "block").mkdir(parents=True)
    (A / "models" / "item").mkdir(parents=True)
    (A / "items").mkdir(parents=True)
    for name, fn in TEXTURES.items():
        fn().save(A / "textures" / f"{name}.png")
    for name, m in MODELS.items():
        (A / "models" / "block" / f"{name}.json").write_text(json.dumps(m, indent=1), encoding="utf-8")
    (A / "models" / "item" / "wrench.json").write_text(json.dumps(
        {"parent": "minecraft:item/handheld", "textures": {"layer0": f"{NS}:item/wrench"}}, indent=1), encoding="utf-8")
    for item, mdls in ITEMS.items():
        (A / "items" / f"{item}.json").write_text(json.dumps(item_def(mdls), indent=1), encoding="utf-8")
    (A / "items" / "wrench.json").write_text(json.dumps(
        {"model": {"type": "minecraft:model", "model": f"{NS}:item/wrench"}}, indent=1), encoding="utf-8")
    mcmeta = {"pack": {
        "description": "Create-Port für Eaglercraft 26.3 – Modelle (inoffiziell)",
        # 26.3 meldet resource_major 97 / resource_minor 1 (version.json im Client)
        "min_format": 97, "max_format": 999,
    }}
    (OUT / "pack.mcmeta").write_text(json.dumps(mcmeta, indent=1, ensure_ascii=False), encoding="utf-8")
    pack_icon(OUT / "pack.png")
    n = sum(1 for _ in OUT.rglob("*") if _.is_file())
    print(f"resourcepack/: {n} Dateien, {len(MODELS)} Modelle, {len(ITEMS) + 1} Items")


if __name__ == "__main__":
    build()

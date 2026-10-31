"""Baut aus DEINER eigenen Create-Jar ein Ressourcenpaket mit den Original-Create-Modellen für den Port.

Die Create-Assets sind "All Rights Reserved" und werden deshalb nicht mit dem Port verteilt.
Dieses Skript (und die gleiche Funktion auf der Webseite) erzeugt das Paket nur lokal für dich.

Aufruf: python tools/convert_create.py create-1.21.1-6.0.10.jar  [ausgabe.zip]
"""
import io
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPPING = json.loads((ROOT / "converter" / "create_mapping.json").read_text(encoding="utf-8"))
BASE_PACK = ROOT / "dist" / "create_zeus_resources.zip"


def resolve_ok(jar_names, read, path):
    """Prüft, ob ein Create-Modell (inkl. Eltern-Kette) mit Vanilla-Mitteln ladbar ist."""
    seen = set()
    cur = path
    while cur and cur not in seen:
        seen.add(cur)
        full = f"assets/create/models/{cur}.json"
        if full not in jar_names:
            return False, f"fehlt: {cur}"
        data = json.loads(read(full))
        if "loader" in data:
            return False, f"eigener Loader ({data['loader']}) in {cur}"
        parent = data.get("parent")
        if not parent or not parent.startswith("create:"):
            return True, ""
        cur = parent.split(":", 1)[1]
    return True, ""


def item_def(paths):
    models = [{"type": "minecraft:model", "model": f"create:{p}"} for p in paths]
    if len(models) == 1:
        return {"model": models[0]}
    return {"model": {"type": "minecraft:composite", "models": models}}


def convert(jar_path, out_path):
    jar = zipfile.ZipFile(jar_path)
    names = set(jar.namelist())
    read = lambda n: jar.read(n).decode("utf-8")
    report = {"ok": [], "fallback": []}
    replaced = {}
    for section in ("display", "items"):
        for item_id, paths in MAPPING[section].items():
            problems = [msg for ok, msg in (resolve_ok(names, read, p) for p in paths) if not ok]
            if problems:
                report["fallback"].append(f"{item_id}: {problems[0]}")
            else:
                replaced[f"assets/create_zeus/items/{item_id}.json"] = json.dumps(item_def(paths), indent=1)
                report["ok"].append(item_id)
    base = zipfile.ZipFile(BASE_PACK)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
        for n in base.namelist():
            if n in replaced or n.endswith("/"):
                continue
            data = base.read(n)
            if n == "pack.mcmeta":
                meta = json.loads(data)
                meta["pack"]["description"] = "Create-Port – Original-Create-Modelle (nur für dich, nicht weitergeben)"
                data = json.dumps(meta, indent=1, ensure_ascii=False).encode("utf-8")
            out.writestr(n, data)
        copied = 0
        for n in sorted(names):
            if n.startswith(("assets/create/models/", "assets/create/textures/")) and not n.endswith("/"):
                out.writestr(n, jar.read(n))
                copied += 1
        for n, text in replaced.items():
            out.writestr(n, text)
    pathlib.Path(out_path).write_bytes(buf.getvalue())
    return report, copied


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    out = sys.argv[2] if len(sys.argv) > 2 else "create_zeus_original_modelle.zip"
    rep, n = convert(sys.argv[1], out)
    print(f"{out}: {n} Create-Dateien übernommen")
    print("Original-Modelle:", ", ".join(rep["ok"]))
    for f in rep["fallback"]:
        print("Port-Modell bleibt:", f)

"""Erzeugt dashboard/eaglerforge-mods.json aus den offiziellen EaglerForge-Beispielmods (MIT-Lizenz).

Quelle: https://github.com/EaglerForge/EaglerForgeInjector (Ordner examplemods), fester Commit.
Aufruf: python tools/build_ef_catalog.py <pfad-zum-geklonten-repo>
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "dashboard" / "eaglerforge-mods.json"

# id: (datei, titel, beschreibung, autor, kategorie, abhängigkeiten, versionen)
V18, V112, BOTH = ["1.8.8"], ["1.12.2"], ["1.8.8", "1.12.2"]
MODS = {
    "asyncsink": ("AsyncSink.js", "AsyncSink", "Bibliothek: lässt Mods eigene Texturen, Sounds und Übersetzungen ins Spiel laden.", "ZXMushroom63", "Bibliothek", [], BOTH),
    "libcustomitems": ("lib.customitems.js", "LibCustomItems", "Bibliothek: macht eigene Items für andere Mods einfach.", "ZXMushroom63", "Bibliothek", [], V18),
    "worldedit": ("Worldedit.js", "WorldEdit", "Bauen im großen Stil: //wand, //set und //walls im Einzelspieler.", "radmanplays", "Werkzeug", ["libcustomitems"], V18),
    "veinminer": ("veinminer.js", "Vein Miner", "Baut beim Schleichen ganze Bäume und Erzadern auf einmal ab.", "ZXMushroom63", "Werkzeug", [], V18),
    "waypoints": ("waypoints.js", "Waypoints", "/setwp <name> speichert einen Wegpunkt, /wp <name> bringt dich hin.", "blizz828, Block_2222 & ZXMushroom63", "Werkzeug", [], V18),
    "hats": ("hats.js", "SimpleHats", "/hat setzt dir das Item aus deiner Hand auf den Kopf.", "ZXMushroom63", "Befehle", [], V18),
    "grapplehook": ("grapplehook.js", "Enterhaken", "Die Angel wird zum Enterhaken und zieht dich zum Haken.", "ZXMushroom63", "Spaß", [], V18),
    "guns": ("guns.js", "Guns", "Fügt Pistolen hinzu.", "ZXMushroom63", "Inhalt", ["asyncsink"], V18),
    "guns_craftable": ("guns_craftable.js", "Guns (craftbar)", "Pistolen mit eigenem Crafting-Rezept.", "ZXMushroom63", "Inhalt", ["asyncsink"], V18),
    "duck": ("DuckMod.js", "Duck Mod", "Fügt Enten mit eigenem Modell und Quak-Geräusch hinzu.", "ZXMushroom63", "Inhalt", ["asyncsink"], V18),
    "wine": ("winemod.js", "Wine Mod", "Fügt Wein hinzu.", "radmanplays", "Inhalt", ["asyncsink"], V18),
    "unlucky_blocks": ("unlucky_blocks.js", "Unlucky Blocks", "Lila Blöcke mit bösen Überraschungen beim Abbauen.", "ZXMushroom63", "Inhalt", ["asyncsink"], V18),
    "block_of_steve": ("block_of_steve_simple.js", "Block of Steve", "Ein Block mit Steve-Gesicht (Demo für eigene Blöcke).", "ZXMushroom63", "Inhalt", ["asyncsink"], V18),
    "custom_block": ("Tutorial_Custom_Block.js", "Explosiver Block", "Ein eigener Block, der explodiert, wenn man ihn benutzt.", "EaglerForge", "Inhalt", ["asyncsink"], V18),
    "custom_item": ("Tutorial_Custom_Item.js", "Eigenes Item (Demo)", "Beispiel für ein komplett eigenes Item.", "EaglerForge", "Inhalt", ["asyncsink"], V18),
    "useless_item": ("useless_item_example_mod.js", "Item-Demo", "Fügt ein nutzloses, aber hübsches Item hinzu.", "EaglerForge", "Inhalt", ["asyncsink"], V18),
    "custom_items_demo": ("CustomItemsDemo.js", "LibCustomItems-Demo", "Zeigt, wie Mods LibCustomItems benutzen.", "ZXMushroom63", "Inhalt", ["libcustomitems"], V18),
    "diamond_recipe": ("diamondBlockCustomCraft.js", "Diamant-Rezept", "Diamantblöcke aus Erde craften.", "EaglerForge", "Inhalt", [], V18),
    "flammable_string": ("flammable_string.js", "Brennbare Fäden", "Faden brennt im Ofen als Brennstoff.", "EaglerForge", "Inhalt", [], V18),
    "timescale": ("timescale_command.js", "Timescale", "/timescale 0.5 macht das Spiel halb so schnell.", "ZXMushroom63", "Befehle", [], V18),
    "faster_minecarts": ("faster_minecarts.js", "Faster Minecarts", "/minecart_speed <faktor> macht Loren schneller.", "ZXMushroom63", "Befehle", [], V18),
    "xpspawner": ("xpspawner.js", "/spawnxp", "Befehl, der Erfahrungskugeln erzeugt.", "EaglerForge", "Befehle", [], V18),
    "talkback": ("talkback.js", "/talkback", "Der Server antwortet dir mit deiner eigenen Nachricht.", "EaglerForge", "Befehle", [], V18),
    "servermod": ("servermod.js", "Server Manager", "Werkzeuge für den Host einer geteilten Welt.", "ZXMushroom63 & radmanplays", "Werkzeug", [], V18),
    "slippery": ("slippery.js", "Slippery", "Alle Blöcke werden rutschig wie Eis.", "radmanplays", "Spaß", [], V18),
    "afk": ("afkmod.js", "Anti AFK", "Schreib .afk in den Chat, um dich automatisch zu bewegen.", "ZXMushroom63", "Werkzeug", [], V18),
    "vclip": ("vclip.js", "VClip", "Mit .vclip <zahl> senkrecht durch Blöcke teleportieren.", "ZXMushroom63", "Trick", [], V18),
    "microphone": ("microphone.js", "GET A MIC", "Spaß-Mod mit einem Mikrofon-Item.", "ZXMushroom63 & TheIdiotPlays", "Spaß", ["asyncsink"], V18),
    "no_particles": ("no_particles.js", "Keine Partikel", "Schaltet alle Partikel ab – mehr FPS.", "EaglerForge", "Grafik", [], V18),
    "no_block_particles": ("no_block_particles.js", "Keine Block-Partikel", "Keine Splitter mehr beim Abbauen.", "EaglerForge", "Grafik", [], V18),
    "sliders": ("sliders.js", "Sliders", "Entfernt die Grenzen der Schieberegler in den Optionen.", "ZXMushroom63", "Grafik", [], V18),
    "f11fix": ("f11fix.js", "Fullscreen Fixer", "Mod-Menüs bleiben auch im Vollbild sichtbar.", "ZXMushroom63", "Grafik", [], V18),
    "diamond_recipe_112": ("diamondBlockCustomCraft_112.js", "Diamant-Rezept (1.12)", "Diamantblöcke aus Erde craften.", "EaglerForge", "Inhalt", [], V112),
    "useless_item_112": ("useless_item_example_mod_112.js", "Item-Demo (1.12)", "Fügt ein nutzloses, aber hübsches Item hinzu.", "EaglerForge", "Inhalt", ["asyncsink"], V112),
    "custom_block_112": ("custom_block_112.js", "Eigener Block (1.12)", "Beispiel für einen eigenen Block.", "EaglerForge", "Inhalt", ["asyncsink"], V112),
}


def main(repo):
    repo = pathlib.Path(repo)
    sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    base = f"https://raw.githubusercontent.com/EaglerForge/EaglerForgeInjector/{sha}/examplemods/"
    mods = []
    for mid, (file, title, desc, author, cat, deps, versions) in MODS.items():
        path = repo / "examplemods" / file
        assert path.exists(), file
        for d in deps:
            assert d in MODS, d
        mods.append({"id": mid, "file": file, "title": title, "description": desc, "author": author,
                     "category": cat, "dependencies": deps, "versions": versions,
                     "size": path.stat().st_size, "url": base + file,
                     "loader": "eaglerforge", "kind": "mod"})
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps({
        "source": "https://github.com/EaglerForge/EaglerForgeInjector",
        "commit": sha, "license": "MIT (c) 2024 Eagler Forge", "mods": mods,
    }, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(mods)} Mods (Commit {sha[:8]})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/home/user/eaglerforge/eaglerforgeinjector")

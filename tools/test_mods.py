"""Testet die Zeus-Lua-Mods gegen den API-Nachbau (tools/zeus_mock.lua).

Voraussetzung: pip install lupa   (bringt eine echte Lua-5.4-Laufzeit mit)
Aufruf:        python tools/test_mods.py
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCK = (ROOT / "tools" / "zeus_mock.lua").read_text(encoding="utf-8")

failures = []


def check(cond, msg):
    if cond:
        print("  ok   " + msg)
    else:
        print("  FAIL " + msg)
        failures.append(msg)


def runtime(mod, store=None):
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if store:
        for k, v in store.items():
            lua.globals().M.store[k] = v
    code = (ROOT / "mods" / mod / "main.lua").read_text(encoding="utf-8")
    lua.execute(code)
    return lua


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)]


def hit(lua, x, y, z, face):
    lua.execute(f'M.hit = {{ type = "block", x = {x}, y = {y}, z = {z}, face = "{face}" }}')


def hud_at(lua, x, y, z):
    hit(lua, x, y, z, "up")
    return lua.globals().M.renderHud()


def sent(lua):
    return lua_list(lua.globals().M.sent)


# ---------------------------------------------------------------------------
def test_create():
    print("Create-Port")
    lua = runtime("create_zeus")
    M = lua.globals().M
    M.fire("world_join")
    M.ticks(2)

    # Motor (Achse x) an Block (-1,64,0) Ostseite -> landet auf (0,64,0)
    hit(lua, -1, 64, 0, "east")
    M.runCommand("create", "setzen", "motor")
    hit(lua, 0, 64, 0, "east")
    M.runCommand("create", "setzen", "welle")          # (1,64,0)
    hit(lua, 1, 64, 0, "east")
    M.runCommand("create", "setzen", "zahnrad")        # (2,64,0)
    # kleines Zahnrad oberhalb, gleiche Achse x: Klick auf Ostseite von (1,65,0) -> (2,65,0)
    hit(lua, 1, 65, 0, "east")
    M.runCommand("create", "setzen", "zahnrad")        # (2,65,0), Achse x
    # großes Zahnrad diagonal (2,66,1) in der y/z-Ebene
    hit(lua, 1, 66, 1, "east")
    M.runCommand("create", "setzen", "gross")          # (2,66,1)
    hit(lua, 2, 64, 0, "east")
    M.runCommand("create", "setzen", "tacho")          # (3,64,0)
    M.ticks(5)

    check("64 RPM" in hud_at(lua, 1, 64, 0), "Welle hinter Motor dreht mit 64 RPM")
    check("64 RPM" in hud_at(lua, 2, 65, 0), "kleines Zahnrad kämmt: 64 RPM (gegenläufig)")
    check("32 RPM" in hud_at(lua, 2, 66, 1), "großes Zahnrad diagonal: 32 RPM (Übersetzung 2:1)")
    cmds = sent(lua)
    check(any(c.startswith("summon item_display 1.5 64.5 0.5") for c in cmds), "Welle wird als item_display beschworen")
    check(any('text:{text:"64 RPM"' in c for c in cmds), "Tachometer zeigt 64 RPM per text_display")
    check(any("left_rotation" in c and c.startswith("execute as @e[tag=c") for c in cmds), "Drehanimation per data merge")
    check(any(c.startswith("gamerule send_command_feedback false") for c in cmds), "Befehlsausgaben werden ausgeblendet")
    too_long = [c for c in cmds if len(c) > 256]
    check(not too_long, f"alle Befehle <= 256 Zeichen (längster: {max(len(c) for c in cmds)})")

    # Motor auf 128 RPM -> großes Zahnrad 64
    hit(lua, 0, 64, 0, "up")
    M.runCommand("create", "motor", "128")
    M.ticks(2)
    check("64 RPM" in hud_at(lua, 2, 66, 1), "Motor 128 RPM -> großes Zahnrad 64 RPM")

    # Bohrer: Motor (Achse x) bei (10,60,0), Bohrer schaut nach Osten bei (11,60,0)
    hit(lua, 9, 60, 0, "east")
    M.runCommand("create", "setzen", "motor")
    lua.execute('M.facing = "east"')
    hit(lua, 10, 60, 0, "east")
    M.runCommand("create", "setzen", "bohrer")
    before = len(sent(lua))
    M.ticks(40)
    new = sent(lua)[before:]
    check(any("setblock 12 60 0 air destroy" in c for c in new), "Bohrer baut Block vor sich ab")
    check("64 RPM" in hud_at(lua, 11, 60, 0), "Bohrer bekommt 64 RPM vom Motor")

    # Überlastung: Handkurbel (256 SU) treibt Presse (8 SU/RPM * 32 = 256) + Bohrer (4*32 = 128)
    hit(lua, 19, 70, 0, "east")
    M.runCommand("create", "setzen", "kurbel")          # (20,70,0) Achse x
    hit(lua, 20, 70, 0, "east")
    M.runCommand("create", "setzen", "welle")           # (21,70,0)
    lua.execute('M.facing = "east"')
    hit(lua, 21, 70, 0, "east")
    M.runCommand("create", "setzen", "bohrer")          # (22,70,0) facing east
    # Kurbel festhalten (Blick auf Kurbel)
    hit(lua, 20, 70, 0, "up")
    lua.execute('M.down["g"] = true')
    M.ticks(3)
    out = M.renderHud()
    check("32 RPM" in out and "128 / 256 SU" in out, "Handkurbel: 32 RPM, 128/256 SU")
    # Presse direkt hinter die Kurbel (19,70,0), quer zur Blickrichtung Süd -> Achse x
    lua.execute('M.facing = "south"')
    hit(lua, 20, 70, 0, "west")
    M.runCommand("create", "setzen", "presse")          # (19,70,0) Achse x
    hit(lua, 20, 70, 0, "up")
    M.ticks(3)
    out = M.renderHud()
    check("Überlastet" in out, "Netz meldet Überlastung (384 > 256 SU)")
    lua.execute('M.down["g"] = false')

    # Konflikt: zwei Motoren mit unterschiedlicher Drehzahl an einer Welle
    hit(lua, 29, 80, 0, "east")
    M.runCommand("create", "setzen", "motor")           # (30,80,0)
    hit(lua, 30, 80, 0, "east")
    M.runCommand("create", "setzen", "welle")           # (31,80,0)
    hit(lua, 31, 80, 0, "east")
    M.runCommand("create", "setzen", "motor")           # (32,80,0)
    hit(lua, 32, 80, 0, "up")
    M.runCommand("create", "motor", "32")
    M.ticks(2)
    check("Konflikt" in hud_at(lua, 31, 80, 0), "zwei Motoren mit 64/32 RPM -> Konflikt")

    # Speichern + neu laden
    M.fire("world_leave")
    store = {k: v for k, v in M.store.items()}
    check(any(k.startswith("welt:") for k in store), "Anlagen landen im storage")
    lua2 = runtime("create_zeus", store)
    M2 = lua2.globals().M
    M2.fire("world_join")
    M2.ticks(3)
    check("64 RPM" in hud_at(lua2, 1, 64, 0) or "128 RPM" in hud_at(lua2, 1, 64, 0), "nach Neuladen dreht die Welle weiter")
    errs = [l for l in lua_list(M.logs) + lua_list(M2.logs) if "fehlgeschlagen" in l]
    check(not errs, "keine API-Fehler im Log " + (str(errs[:2]) if errs else ""))


# ---------------------------------------------------------------------------
def test_device():
    print("MC-Device-Port")
    lua = runtime("mc_device_zeus")
    M = lua.globals().M
    M.fire("world_join")
    M.ticks(2)
    M.binds["phone"].onPress()
    txt = M.screenText()
    check("GPS" in txt and "Rechner" in txt, "Handy öffnet Startbildschirm mit Apps")
    M.click("GPS")
    check("X " in M.screenText() or "XYZ" in M.screenText(), "GPS zeigt Koordinaten")
    M.click("Wegpunkt hier speichern")
    check(any("Wegpunkt" in t for t in lua_list(M.toasts)), "Wegpunkt gespeichert")
    M.click("Zurück")
    M.click("Taschenlampe")
    check(any("night_vision" in c for c in sent(lua)), "Taschenlampe gibt Nachtsicht")
    M.click("Staubsauger")
    before = len(sent(lua))
    M.ticks(25)
    check(any("tp @e[type=item" in c for c in sent(lua)[before:]), "Staubsauger zieht Items heran")
    M.runCommand("rechne", "2", "*", "(3", "+", "4)")
    check(any("= 14" in c for c in lua_list(M.chatlog)), "/rechne 2 * (3 + 4) = 14")
    M.runCommand("rechne", "os.exit()")
    check(not any("os.exit" in c and "=" in c and "Fehler" not in c for c in lua_list(M.chatlog)), "Rechner führt keinen Code aus")
    M.runCommand("notiz", "Diamanten", "bei", "x=120")
    M.binds["phone"].onPress()
    M.click("Notizen")
    check("Diamanten bei x=120" in M.screenText(), "Notiz erscheint in der Notizen-App")
    M.click("Zurück")
    M.click("Uhr")
    check("12:00" in M.screenText(), "Uhr: timeOfDay 6000 = 12:00")
    M.click("Zurück")
    # Laptop bekommt Create-Statistiken
    lua.execute('emit("create_zeus:stats", { count = 5, networks = { { id = 1, size = 5, capacity = 256, impact = 128, running = true } } })')
    M.click("Laptop")
    check("128 / 256 SU" in M.screenText(), "Laptop zeigt Create-Netze")
    errs = [l for l in lua_list(M.logs) if "fehlgeschlagen" in l]
    check(not errs, "keine API-Fehler im Log " + (str(errs[:2]) if errs else ""))


if __name__ == "__main__":
    test_create()
    test_device()
    print()
    if failures:
        print(f"{len(failures)} Test(s) fehlgeschlagen")
        sys.exit(1)
    print("Alle Tests bestanden")

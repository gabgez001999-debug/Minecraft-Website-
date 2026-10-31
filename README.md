# Create & MC-Device für Eaglercraft 26.3 (Lua-Mods)

Zwei inoffizielle Mods für den **Eaglercraft-26.3-Client** mit seinem eingebauten Mod-System „Zeus“
(Lua 5.4, Mod-API 1). Webseite mit Download und Anleitung: [`index.html`](index.html), gedacht für GitHub Pages.

| Mod | Datei | Inhalt |
|-----|-------|--------|
| **Create (Eaglercraft-Port)** | [`dist/create_zeus.zip`](dist/create_zeus.zip) | Wellen, Zahnräder, Getriebe, Handkurbel, Wasserrad, Kreativmotor, Bohrer, Lüfter, Presse, Mahlstein, Förderband, Tacho, Stressometer, Stress-System, Ingenieursbrille |
| **MC-Device (Eaglercraft-Port)** | [`dist/mc_device_zeus.zip`](dist/mc_device_zeus.zip) | Handy mit GPS/Wegpunkten, Uhr/Wecker, Wetter, Rechner, Notizen, Musik, Status, Taschenlampe, Staubsauger, Laptop für Create-Anlagen |

## Installation

1. [eaglercraft.com/play?version=26.3](https://eaglercraft.com/play?version=26.3) öffnen.
2. Einzelspieler-Welt **mit Cheats** erstellen.
3. Hauptmenü → **Mods** → **Importieren** → `.zip` wählen (oder Datei aufs Fenster ziehen).
4. In der Welt: `B` = Create-Baumenü, `P` = Handy. `/create hilfe` zeigt alle Befehle.

## Wie das funktioniert

- Der 26.3-Client bringt einen eigenen Lua-Interpreter mit. Mods sind `.zip`-Dateien mit
  `metadata.json` + `icon.png` (64×64) + `main.lua`, oder einzelne `.lua`-Dateien mit Kopfkommentaren.
- Die API ist **clientseitig**: Events (`tick`, `world_join`, `chat_receive` …), HUD, Tasten,
  eigene Menüs, Chatbefehle, Spielerdaten, `storage`. Eigene Blöcke registrieren geht nicht.
- Darum besteht jedes Create-Bauteil aus einem Vanilla-Trägerblock und Display-Entities, die über
  `chat.command` per `/setblock`, `/summon` und `/data merge` gesetzt und gedreht werden.
  Drehzahl, Übersetzung und Stress rechnet die Mod selbst in Lua.
- Mods laufen nur im Einzelspieler. Auf Servern und bei LAN-Welten pausiert der Client sie.

Die API-Namen stammen aus der Analyse des 26.3-Clients (eingebaute Beispiel-Mods und Strings), nicht aus
offizieller Doku. Bei Abweichungen hilft `/create api`: Das schreibt alle verfügbaren Lua-Funktionen ins Mod-Log.

## Entwicklung

```bash
pip install lupa pillow
python tools/test_mods.py   # testet beide Mods gegen den API-Nachbau tools/zeus_mock.lua
python tools/build.py       # baut dist/*.zip und dist/*.lua
```

## Credits

- [Create](https://github.com/Creators-of-Create/Create) von simibubi & dem Create-Team. Code MIT,
  Assets „All Rights Reserved“. Hier werden keine Create-Assets verwendet.
- [Phone: MC-Device](https://www.curseforge.com/minecraft/mc-mods/phone-mc-device) von NotPumpkins. Nur die Idee, kein Code.
- [Eaglercraft](https://eaglercraft.com). Kein offizielles Produkt von Mojang/Microsoft.

Lizenz der Mods in diesem Repo: MIT (siehe [`LICENSE`](LICENSE)).

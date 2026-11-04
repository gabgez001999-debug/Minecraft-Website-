# Create & MC-Device für Eaglercraft 26.3 und 26.2 (Lua-Mods)

Zwei inoffizielle Mods für die **Eaglercraft-Clients 26.3 und 26.2** mit ihrem eingebauten Mod-System „Zeus“
(Lua 5.4, Mod-API 1). Webseite mit Download und Anleitung: [`index.html`](index.html), gedacht für GitHub Pages.

| Mod | Datei | Inhalt |
|-----|-------|--------|
| **Create (Eaglercraft-Port)** v0.4 | [`dist/create_zeus.zip`](dist/create_zeus.zip) | 30 Bauteile als Items (Kupplung, Gangschaltung, Kettenantrieb, Säge, Brechräder, Windmühle …), Linksklick abbauen, drehende 3D-Modelle, Rechtsklick-Platzierung, Schraubenschlüssel, B-Menü mit 6 Addons (Kanonen, Elektrik, Aeronautik, Dragons Plus, Verzauberungsindustrie, Kraftwerk) samt Abhängigkeiten, Stress-System, Ingenieursbrille |
| **Ressourcenpaket** | [`dist/create_zeus_resources.zip`](dist/create_zeus_resources.zip) | 35 eigene 3D-Modelle im Create-Stil ([Vorschau](vorschau.html)) – oder per Konverter die Original-Modelle aus deiner eigenen Create-Jar |
| **MC-Device (Eaglercraft-Port)** | [`dist/mc_device_zeus.zip`](dist/mc_device_zeus.zip) | Handy mit GPS/Wegpunkten, Uhr/Wecker, Wetter, Rechner, Notizen, Musik, Status, Taschenlampe, Staubsauger, Laptop für Create-Anlagen |

## Mod-Dashboard

[`dashboard.html`](dashboard.html) ist ein Launcher im Browser mit zwei Loadern:

| Version | Loader | Mods | „Spielen“ |
|---------|--------|------|-----------|
| 26.3, 26.2 | **Zeus (Lua)**, eingebaut | Create, Ressourcenpaket, MC-Device aus diesem Repo | lädt den offiziellen Client von eaglercraft.com (deren CDN erlaubt das per CORS), startet ihn im Dashboard und übergibt die Mods automatisch |
| 1.8.8, 1.12.2 | **EaglerForge** | 35 offizielle Beispielmods | startet deinen EaglerForge-Client mit den Mods |

Ablauf:

- Beim ersten Start eine Instanz anlegen (Name, Version, Loader). Die Version bestimmt den Loader. Oben rechts siehst und
  wechselst du Instanz, Loader und Version.
- **Mods entdecken** zeigt nur Mods für den Loader der Instanz. Braucht eine Mod andere (z. B. Create → Ressourcenpaket,
  WorldEdit → LibCustomItems, Guns → AsyncSink), fragt ein Popup, ob die mit heruntergeladen werden sollen.
- **Spielen** (unten rechts) bei 26.x: Beim ersten Mal lädt das Dashboard den offiziellen Client direkt von eaglercraft.com
  (gut 55 MB, bei neuem Build erneut) und speichert ihn im Browser. Der Client nimmt Mods über ein Fallenlassen-Ereignis an;
  das Dashboard löst es selbst aus, sobald im Spiel das Mods-Menü (bzw. die Ressourcenpakete) offen ist. Eine kleine Leiste im
  Spiel zeigt den Stand, mit „Jetzt übergeben“ und „Dateien speichern“ als Rückfall. Unter Einstellungen lässt sich auf
  „auf eaglercraft.com spielen“ (Mods selbst importieren) umstellen. Hinweis: Dieser Teil ist nur gegen einen Nachbau des
  Clients getestet, nicht im echten Spiel.
- **Spielen** bei EaglerForge: öffnet EaglerForge mit den Mods der Instanz in einem neuen Tab. Beim ersten Mal pro Version
  fragt das Dashboard nach dem Client: Datei per Link aus dem
  [Eaglercraft-Archive](https://github.com/Eaglercraft-Archive/unminified-eaglercraft-builds/releases/latest) holen und
  reinziehen. Das Dashboard baut EaglerForge dann selbst ein (gleicher Injector wie auf der EaglerForge-Seite, mitgeliefert in
  [`vendor/eaglerforge-injector`](vendor/eaglerforge-injector), MIT) und speichert den Client im Browser. Eine fertige
  `processed.html` geht auch. Automatisch herunterladen kann die Seite die Datei nicht: GitHub-Releases schicken keine
  CORS-Header, und einen kompletten Minecraft-Client legt dieses Repo bewusst nicht selbst ab.
- **Mehrspieler:** Einladungslink teilen. Wer andere Mods hat, bekommt beim Öffnen die Frage, ob eine Instanz mit allen Mods der Welt erstellt werden soll.

Kataloge: [`dashboard/zeus-mods.json`](dashboard/zeus-mods.json) baut `python tools/build.py` mit,
[`dashboard/eaglerforge-mods.json`](dashboard/eaglerforge-mods.json) entsteht mit
`python tools/build_ef_catalog.py <klon-von-EaglerForgeInjector>` und zeigt auf einen festen Commit.

## Installation

1. [eaglercraft.com/play?version=26.3](https://eaglercraft.com/play?version=26.3) oder [26.2](https://eaglercraft.com/play?version=26.2) öffnen.
2. Einzelspieler-Welt **mit Cheats** erstellen.
3. **Ressourcenpaket (nicht bei Mods!):** Optionen → Ressourcenpakete… → „Import Pack…“ → `create_zeus_resources.zip`
   wählen, dann links beim Paket auf den Pfeil klicken, damit es zu „Ausgewählt“ wandert → Fertig.
4. Hauptmenü → **Mods** → **Importieren** → `create_zeus.zip` wählen (oder Datei aufs Fenster ziehen).
5. In der Welt: `B` = Create-Menü (Tab Bauteile → „Alle Teile geben“), Teil in die Hand + Rechtsklick setzt es. `P` = Handy.

## Original-Create-Modelle

Create-Assets sind „All Rights Reserved“ und liegen deshalb nicht in diesem Repo. Die Webseite (Abschnitt
„Original-Create-Modelle“) oder `python tools/convert_create.py <create.jar>` baut aus deiner eigenen Create-Jar lokal
ein Ressourcenpaket mit den Originalmodellen. Getestet mit Create 6.0.10: 43 Modelle werden ersetzt
(Wasserrad und Brechrad bleiben, weil Create dafür OBJ-Modelle nutzt). Zuordnung: [`converter/create_mapping.json`](converter/create_mapping.json).

## Wie das funktioniert

- Die 26.x-Clients bringen einen eigenen Lua-Interpreter mit. 26.2 und 26.3 sind derselbe Zeus-Stand
  (gleiche Lua-API 1, gleiche Prüfung der `metadata.json`), nur das Ressourcenpaket-Format unterscheidet sich
  (26.2: 88, 26.3: 97.1). Das Paket deckt mit `min_format` 88 beide ab.
- Mods sind `.zip`-Dateien mit
  `metadata.json` + `icon.png` (64×64) + `main.lua`, oder einzelne `.lua`-Dateien mit Kopfkommentaren.
- Die API ist **clientseitig**: Events (`tick`, `world_join`, `chat_receive` …), HUD, Tasten,
  eigene Menüs, Chatbefehle, Spielerdaten, `storage`. Eigene Blöcke registrieren geht nicht.
- Darum besteht jedes Create-Bauteil aus einem Vanilla-Trägerblock und Display-Entities, die über
  `chat.command` per `/setblock`, `/summon` und `/data merge` gesetzt und gedreht werden.
  Drehzahl, Übersetzung und Stress rechnet die Mod selbst in Lua.
- Mods laufen nur im Einzelspieler. Auf Servern und bei LAN-Welten pausiert der Client sie.

Die API-Namen stammen aus der Analyse der 26.x-Clients (eingebaute Beispiel-Mods und Strings), nicht aus
offizieller Doku. Bei Abweichungen hilft `/create api`: Das schreibt alle verfügbaren Lua-Funktionen ins Mod-Log.

## Entwicklung

```bash
pip install lupa pillow
python tools/test_mods.py   # testet beide Mods gegen den API-Nachbau tools/zeus_mock.lua
python tools/build.py       # baut dist/*.zip, dist/*.lua und das Ressourcenpaket (resourcepack/)
```

## Credits

- [Create](https://github.com/Creators-of-Create/Create) von simibubi & dem Create-Team. Code MIT,
  Assets „All Rights Reserved“. Hier werden keine Create-Assets verwendet.
- [Phone: MC-Device](https://www.curseforge.com/minecraft/mc-mods/phone-mc-device) von NotPumpkins. Nur die Idee, kein Code.
- [EaglerForge](https://github.com/EaglerForge/EaglerForgeInjector): Mod-Loader, Injector (in `vendor/`) und Beispiel-Mods (MIT).
- [Eaglercraft-Archive](https://github.com/Eaglercraft-Archive): unminifizierte EaglercraftX-Builds, die das Dashboard zum Einbauen verlinkt.
- [Eaglercraft](https://eaglercraft.com). Kein offizielles Produkt von Mojang/Microsoft.

Lizenz der Mods in diesem Repo: MIT (siehe [`LICENSE`](LICENSE)).

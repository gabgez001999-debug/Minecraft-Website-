-- name: MC-Device (Eaglercraft-Port)
-- id: mc_device_zeus
-- version: 0.1.0
-- author: Larpbase
-- description: Inoffizieller Port der Idee von "Phone: MC-Device" für Eaglercraft 26.2 und 26.3 (Zeus-Lua). Handy mit Apps, Staubsauger, Taschenlampe und Laptop für Create-Anlagen.
--
-- Hinweis: Zeus-Mods laufen nur im Einzelspieler. Anrufe zwischen Spielern (das Herzstück von
-- MC-Device) gehen deshalb nicht; das Handy konzentriert sich auf nützliche Einzelspieler-Apps.
-- Kein Code und keine Assets von MC-Device übernommen, nur das Konzept.

local MOD_VERSION = "0.1.0"

---------------------------------------------------------------------------
-- Kompatibilität
---------------------------------------------------------------------------
local function lib(name)
  local ok, v = pcall(function() return _G[name] end)
  if ok then return v end
  return nil
end
local function field(t, k)
  if t == nil then return nil end
  local ok, v = pcall(function() return t[k] end)
  if ok then return v end
  return nil
end
local warned = {}
local function logMsg(msg) pcall(lib("log") or print, "[Handy] " .. tostring(msg)) end
local function call(t, fname, ...)
  local f = field(t, fname)
  if type(f) ~= "function" then return false end
  local res = table.pack(pcall(f, ...))
  if not res[1] then
    if not warned[fname] then warned[fname] = true; logMsg(fname .. " fehlgeschlagen: " .. tostring(res[2])) end
    return false
  end
  return true, table.unpack(res, 2, res.n)
end

local chat, player, game, world, keys, hud, ui, commands, storage, settings, sound =
  lib("chat"), lib("player"), lib("game"), lib("world"), lib("keys"), lib("hud"), lib("ui"), lib("commands"),
  lib("storage"), lib("settings"), lib("sound")
local floor, abs = math.floor, math.abs
local mmax = math.max or function(a, b) if a > b then return a end return b end
local mmin = math.min or function(a, b) if a < b then return a end return b end
local tremove = table.remove or function(t, i)
  local n = #t
  local v = t[i]
  for k = i, n - 1 do t[k] = t[k + 1] end
  t[n] = nil
  return v
end

local function say(msg)
  if not call(chat, "print", "§b[Handy]§r " .. msg) then logMsg(msg) end
end
local function toast(msg)
  local n = lib("notify")
  if type(n) == "function" and pcall(n, msg) then return end
  say(msg)
end

local defaults = { hud_clock = true, nav_hud = true, vac_radius = 8, slash = false }
local function setting(name)
  local v = field(settings, name)
  if v == nil then return defaults[name] end
  return v
end
if settings then
  pcall(function()
    settings.toggle("hud_clock", { label = "Uhr im HUD", default = true })
    settings.toggle("nav_hud", { label = "Navigation zum Wegpunkt im HUD", default = true })
    settings.slider("vac_radius", { label = "Staubsauger-Reichweite", min = 3, max = 16, step = 1, default = 8 })
    settings.toggle("slash", { label = "Befehle mit / senden (nur falls nichts passiert)", default = false })
  end)
end

local function command(s)
  if setting("slash") then s = "/" .. s end
  if not call(chat, "command", s) then say("§cBefehle sind nicht verfügbar (Cheats an?).") end
end

---------------------------------------------------------------------------
-- Speicher (JSON-Text in storage)
---------------------------------------------------------------------------
local function quote(str)
  return '"' .. str:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    return string.format("\\%03d", c:byte())
  end) .. '"'
end

local function encode(v)
  local t = type(v)
  if t == "string" then return quote(v) end
  if t == "number" then
    if floor(v) == v then return string.format("%d", v) end
    return string.format("%.4f", v)
  end
  if t == "boolean" then return v and "true" or "false" end
  if t == "table" then
    local out = {}
    if #v > 0 or next(v) == nil then
      for i = 1, #v do out[i] = encode(v[i]) end
      return "{" .. table.concat(out, ",") .. "}"
    end
    for k, val in pairs(v) do out[#out + 1] = "[" .. quote(tostring(k)) .. "]=" .. encode(val) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "nil"
end
-- Daten werden als Lua-Tabellenliteral gespeichert und in einer leeren Umgebung gelesen.
local function decode(s)
  if type(s) ~= "string" then return s end
  local loader = lib("load")
  if type(loader) ~= "function" then return nil end
  local ok, fn = pcall(loader, "return " .. s, "daten", "t", {})
  if not ok or not fn then return nil end
  local ok2, v = pcall(fn)
  if ok2 then return v end
  return nil
end

local function sget(key, default)
  if not storage then return default end
  local ok, raw = call(storage, "get", key)
  if not ok or raw == nil then return default end
  local v = decode(raw)
  if v == nil then return default end
  return v
end
local function sset(key, value)
  if not storage then return end
  call(storage, "set", key, encode(value))
end

local function worldName()
  local ok, s = call(game, "server")
  if ok and type(s) == "string" and s ~= "" then return s end
  local ok2, n = call(world, "name")
  if ok2 and type(n) == "string" and n ~= "" then return n end
  return "welt"
end

---------------------------------------------------------------------------
-- Zustand
---------------------------------------------------------------------------
local active = false
local tickNo = 0
local waypoints = {}
local notes = {}
local navTarget = nil
local flashlight = false
local vacuum = false
local createStats = nil
local alarmDawn, alarmDusk = false, false
local lastPhase = nil

local function wpKey() return "wegpunkte:" .. worldName() end
local function loadAll()
  waypoints = sget(wpKey(), {})
  notes = sget("notizen", {})
  local st = sget("status", {})
  alarmDawn, alarmDusk = st.dawn == true, st.dusk == true
end
local function saveWaypoints() sset(wpKey(), waypoints) end
local function saveNotes() sset("notizen", notes) end
local function saveStatus() sset("status", { dawn = alarmDawn, dusk = alarmDusk }) end

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------
local function pos()
  local ok, x, y, z = call(player, "pos")
  if ok and type(x) == "number" then return x, y, z end
  return nil
end

local function dimName()
  local ok, d = call(player, "dimension")
  if not ok or not d then return "?" end
  d = tostring(d):gsub("^minecraft:", "")
  local names = { overworld = "Oberwelt", the_nether = "Nether", the_end = "Ende" }
  return names[d] or d
end

local function ticksOfDay()
  local ok, t = call(world, "timeOfDay")
  if not ok or type(t) ~= "number" then return nil end
  if t >= 0 and t <= 1 and floor(t) ~= t then t = t * 24000 end
  return t % 24000
end

local function clock()
  local t = ticksOfDay()
  if not t then return "--:--" end
  local h = floor(t / 1000 + 6) % 24
  local m = floor((t % 1000) * 60 / 1000)
  return string.format("%02d:%02d", h, m)
end

local function realClock()
  local ok, s = pcall(os.date, "%H:%M")
  if ok and s then return s end
  return "--:--"
end

local ARROWS = { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }
local function bearing(tx, tz)
  local px, _, pz = pos()
  if not px then return "?", 0 end
  local dx, dz = tx - px, tz - pz
  local dist = math.sqrt(dx * dx + dz * dz)
  local okY, yaw = call(player, "yaw")
  if not okY or type(yaw) ~= "number" then return "•", dist end
  local want = math.deg(math.atan(-dx, dz))
  local rel = (want - yaw) % 360
  return ARROWS[floor((rel + 22.5) / 45) % 8 + 1], dist
end

---------------------------------------------------------------------------
-- Rechner (nur Zahlen, Klammern, Grundrechenarten und math-Funktionen)
---------------------------------------------------------------------------
local MATHFN = { "sqrt", "abs", "floor", "ceil", "sin", "cos", "tan", "log", "exp", "pi", "max", "min" }
local function calculate(expr)
  expr = tostring(expr or ""):gsub(",", "."):gsub("×", "*"):gsub("÷", "/"):gsub("wurzel", "sqrt")
  local stripped = expr
  for _, n in ipairs(MATHFN) do stripped = stripped:gsub(n, "") end
  if expr:match("^%s*$") then return nil, "Leerer Ausdruck" end
  if not stripped:match("^[%d%s%+%-%*/%%%^%(%)%.]*$") then return nil, "Nur Zahlen und + - * / ^ ( ) erlaubt" end
  local env = {}
  for _, n in ipairs(MATHFN) do env[n] = math[n] end
  local loader = lib("load")
  if type(loader) ~= "function" then return nil, "load() fehlt" end
  local ok, fn = pcall(loader, "return " .. expr, "rechner", "t", env)
  if not ok or not fn then return nil, "Ausdruck ungültig" end
  local ok2, v = pcall(fn)
  if not ok2 or type(v) ~= "number" then return nil, "Ausdruck ungültig" end
  if v ~= v or v == math.huge or v == -math.huge then return nil, "Nicht definiert" end
  if floor(v) == v and abs(v) < 1e15 then return string.format("%d", v) end
  return (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ""))
end

---------------------------------------------------------------------------
-- Bildschirme
---------------------------------------------------------------------------
local openHome

local function screen(title, build)
  if not ui then say("UI nicht verfügbar.") return end
  local ok, scr = pcall(ui.screen, {
    title = title,
    init = function(s)
      local ok2, err = pcall(build, s)
      if not ok2 then pcall(s.label, s, { text = "Fehler: " .. tostring(err) }) end
    end,
  })
  if ok then call(ui, "open", scr) else say("Bildschirm-Fehler: " .. tostring(scr)) end
end

local function back(s)
  s:button({ text = "← Zurück", onClick = function() s:close(); openHome() end })
end

local function textInput(s, initial, onChange, hint)
  local f = field(s, "textField")
  if type(f) ~= "function" then return false end
  local spec = { text = initial or "", value = initial or "", placeholder = hint, hint = hint,
    onChange = onChange, onInput = onChange }
  return pcall(f, s, spec)
end

local function openGps()
  screen("GPS & Wegpunkte", function(s)
    local x, y, z = pos()
    if x then
      s:label({ text = string.format("XYZ %.1f / %.1f / %.1f", x, y, z), centered = true })
    end
    local okF, f = call(player, "facing")
    local okB, b = call(player, "biome")
    local biome = okB and (tostring(b or "?"):gsub("^minecraft:", "")) or "?"
    s:label({ text = string.format("Blick: %s · Biom: %s · %s", okF and tostring(f) or "?", biome, dimName()), centered = true })
    s:button({ text = "Wegpunkt hier speichern", onClick = function()
      local px, py, pz = pos()
      if not px then return end
      local name = "Wegpunkt " .. (#waypoints + 1)
      waypoints[#waypoints + 1] = { name = name, x = floor(px), y = floor(py), z = floor(pz), d = dimName() }
      saveWaypoints()
      toast(name .. " gespeichert")
      s:rebuild()
    end })
    for i, w in ipairs(waypoints) do
      local arrow, dist = bearing(w.x + 0.5, w.z + 0.5)
      local mark = (navTarget == w) and "» " or ""
      s:button({ text = string.format("%s%s %s %d m (%d %d %d)", mark, arrow, w.name, floor(dist), w.x, w.y, w.z), onClick = function()
        navTarget = (navTarget == w) and nil or w
        s:rebuild()
      end })
    end
    if navTarget then
      s:button({ text = "Navigation beenden", onClick = function() navTarget = nil; s:rebuild() end })
    end
    if #waypoints > 0 then
      s:button({ text = "Letzten Wegpunkt löschen", onClick = function()
        local w = tremove(waypoints)
        if navTarget == w then navTarget = nil end
        saveWaypoints()
        s:rebuild()
      end })
    end
    s:label({ text = "Tipp: /wegpunkt <name> speichert mit eigenem Namen", centered = true })
    back(s)
  end)
end

local function openClock()
  screen("Uhr & Wecker", function(s)
    local okD, day = call(world, "day")
    s:label({ text = "Spielzeit: " .. clock() .. (okD and ("  ·  Tag " .. tostring(day)) or ""), centered = true })
    s:label({ text = "Echte Zeit: " .. realClock(), centered = true })
    s:button({ text = "Wecker bei Sonnenaufgang: " .. (alarmDawn and "AN" or "AUS"), onClick = function()
      alarmDawn = not alarmDawn; saveStatus(); s:rebuild()
    end })
    s:button({ text = "Warnung bei Sonnenuntergang: " .. (alarmDusk and "AN" or "AUS"), onClick = function()
      alarmDusk = not alarmDusk; saveStatus(); s:rebuild()
    end })
    s:button({ text = "Aktualisieren", onClick = function() s:rebuild() end })
    back(s)
  end)
end

local function openWeather()
  screen("Wetter & Zeit", function(s)
    s:label({ text = "Braucht Cheats in der Welt.", centered = true })
    s:button({ text = "☀ Sonne", onClick = function() command("weather clear") end })
    s:button({ text = "☂ Regen", onClick = function() command("weather rain") end })
    s:button({ text = "⚡ Gewitter", onClick = function() command("weather thunder") end })
    s:button({ text = "Morgen (06:00)", onClick = function() command("time set 0") end })
    s:button({ text = "Mittag (12:00)", onClick = function() command("time set 6000") end })
    s:button({ text = "Abend (18:00)", onClick = function() command("time set 12000") end })
    s:button({ text = "Mitternacht", onClick = function() command("time set 18000") end })
    back(s)
  end)
end

local calcExpr, calcResult = "", nil
local function openCalc()
  screen("Rechner", function(s)
    s:label({ text = calcResult and (calcExpr .. " = " .. calcResult) or "Ausdruck eingeben, z. B. 64*3+5", centered = true })
    local hasField = textInput(s, calcExpr, function(v) calcExpr = tostring(v or "") end, "64*3+5")
    if hasField then
      s:button({ text = "=", onClick = function()
        local r, err = calculate(calcExpr)
        calcResult = r or ("Fehler: " .. err)
        s:rebuild()
      end })
    else
      s:label({ text = "Eingabe per Chat: /rechne 64*3+5", centered = true })
    end
    for _, preset in ipairs({ { "Stack → Items: 64×", "*64" }, { "Items → Stacks: ÷64", "/64" } }) do
      s:button({ text = preset[1] .. " (letztes Ergebnis)", onClick = function()
        local base = tonumber(calcResult) or 1
        calcExpr = tostring(base) .. preset[2]
        local r, err = calculate(calcExpr)
        calcResult = r or ("Fehler: " .. err)
        s:rebuild()
      end })
    end
    back(s)
  end)
end

local noteDraft = ""
local function openNotes()
  screen("Notizen", function(s)
    if #notes == 0 then s:label({ text = "Noch keine Notizen.", centered = true }) end
    for i, n in ipairs(notes) do s:label({ text = i .. ". " .. n }) end
    local hasField = textInput(s, noteDraft, function(v) noteDraft = tostring(v or "") end, "Neue Notiz")
    if hasField then
      s:button({ text = "Notiz speichern", onClick = function()
        if noteDraft:match("%S") then notes[#notes + 1] = noteDraft; noteDraft = ""; saveNotes() end
        s:rebuild()
      end })
    end
    s:label({ text = "Oder im Chat: /notiz <text>", centered = true })
    for i = #notes, 1, -1 do
      s:button({ text = "Notiz " .. i .. " löschen", onClick = function() tremove(notes, i); saveNotes(); s:rebuild() end })
    end
    back(s)
  end)
end

local DISCS = { "13", "cat", "blocks", "chirp", "far", "mall", "mellohi", "stal", "strad", "ward", "wait",
  "pigstep", "otherside", "relic", "5", "creator", "creator_music_box", "precipice", "tears", "lava_chicken" }
local function openMusic()
  screen("Musik", function(s)
    s:button({ text = "■ Stopp", onClick = function() command("stopsound @s") end })
    for _, d in ipairs(DISCS) do
      s:button({ text = "♫ " .. d, onClick = function()
        command("stopsound @s record")
        if not call(sound, "play", "minecraft:music_disc." .. d) then
          command("playsound minecraft:music_disc." .. d .. " record @s")
        end
      end })
    end
    back(s)
  end)
end

local function openStatus()
  screen("Status", function(s)
    local function v(fn) local ok, r = call(player, fn); if ok and r ~= nil then return r end return "?" end
    local function fmt(x) if type(x) == "number" then return string.format("%g", floor(x * 10 + 0.5) / 10) end return tostring(x) end
    s:label({ text = "❤ Leben: " .. fmt(v("health")) .. " / " .. fmt(v("maxHealth")), centered = true })
    s:label({ text = "Hunger: " .. fmt(v("food")) .. " · Sättigung: " .. fmt(v("saturation")), centered = true })
    s:label({ text = "Rüstung: " .. fmt(v("armor")) .. " · Level: " .. fmt(v("xpLevel")), centered = true })
    s:label({ text = "Spielmodus: " .. tostring(v("gamemode")) .. " · " .. dimName(), centered = true })
    local okF, fps = call(game, "fps")
    if okF then s:label({ text = "FPS: " .. tostring(fps), centered = true }) end
    back(s)
  end)
end

local function openLaptop()
  screen("Laptop – Create-Anlagen", function(s)
    if not createStats then
      s:label({ text = "Keine Daten. Ist der Create-Port (create_zeus) installiert?", centered = true })
    else
      s:label({ text = string.format("%d Bauteile in %d Netzen", createStats.count or 0, #(createStats.networks or {})), centered = true })
      for _, n in ipairs(createStats.networks or {}) do
        local state = n.overstressed and "ÜBERLASTET" or (n.conflict and "KONFLIKT" or (n.running and "läuft" or "steht"))
        s:label({ text = string.format("Netz #%s: %d Teile · %d / %d SU · %s", tostring(n.id), n.size or 0,
          floor((n.impact or 0) + 0.5), floor((n.capacity or 0) + 0.5), state) })
      end
    end
    back(s)
  end)
end

openHome = function()
  screen("Handy  ·  " .. clock(), function(s)
    s:button({ text = "GPS & Wegpunkte", onClick = function() s:close(); openGps() end })
    s:button({ text = "Uhr & Wecker", onClick = function() s:close(); openClock() end })
    s:button({ text = "Wetter & Zeit", onClick = function() s:close(); openWeather() end })
    s:button({ text = "Rechner", onClick = function() s:close(); openCalc() end })
    s:button({ text = "Notizen", onClick = function() s:close(); openNotes() end })
    s:button({ text = "Taschenlampe: " .. (flashlight and "AN" or "AUS"), onClick = function()
      flashlight = not flashlight
      if flashlight then command("effect give @s night_vision infinite 0 true") else command("effect clear @s night_vision") end
      s:rebuild()
    end })
    s:button({ text = "Staubsauger: " .. (vacuum and "AN" or "AUS"), onClick = function()
      vacuum = not vacuum
      toast("Staubsauger " .. (vacuum and "an" or "aus"))
      s:rebuild()
    end })
    s:button({ text = "Musik", onClick = function() s:close(); openMusic() end })
    s:button({ text = "Status", onClick = function() s:close(); openStatus() end })
    s:button({ text = "Laptop: Create-Anlagen", onClick = function() s:close(); openLaptop() end })
    s:button({ text = "Schließen", onClick = function() s:close() end })
  end)
end

---------------------------------------------------------------------------
-- Tasten, Befehle, HUD
---------------------------------------------------------------------------
if keys then
  pcall(keys.bind, { id = "phone", label = "Handy öffnen", default = "p", onPress = function()
    if active then openHome() end
  end })
  pcall(keys.bind, { id = "vacuum", label = "Staubsauger an/aus", default = "j", onPress = function()
    if not active then return end
    vacuum = not vacuum
    toast("Staubsauger " .. (vacuum and "an" or "aus"))
  end })
end

if commands then
  pcall(commands.register, "handy", function() if active then openHome() end end, "Öffnet das Handy")
  pcall(commands.register, "rechne", function(args)
    local expr = table.concat(args, " ")
    local r, err = calculate(expr)
    if r then say(expr .. " = " .. r) else say("§cFehler: " .. err) end
  end, "Rechnet: /rechne 64*3+5")
  pcall(commands.register, "notiz", function(args)
    local text = table.concat(args, " ")
    if not text:match("%S") then say("Nutzung: /notiz <text>") return end
    notes[#notes + 1] = text
    saveNotes()
    say("Notiz gespeichert (" .. #notes .. ").")
  end, "Speichert eine Notiz im Handy")
  pcall(commands.register, "wegpunkt", function(args)
    local px, py, pz = pos()
    if not px then return end
    local name = table.concat(args, " ")
    if not name:match("%S") then name = "Wegpunkt " .. (#waypoints + 1) end
    waypoints[#waypoints + 1] = { name = name, x = floor(px), y = floor(py), z = floor(pz), d = dimName() }
    saveWaypoints()
    say("Wegpunkt \"" .. name .. "\" gespeichert.")
  end, "Speichert einen Wegpunkt: /wegpunkt <name>")
end

if hud then
  pcall(hud.add, "mc_device", function(ctx)
    if not active then return end
    local okS, scr = call(game, "screen")
    if okS and scr then return end
    local w = field(ctx, "width") or 320
    local y = 4
    if setting("hud_clock") then
      local txt = clock()
      if vacuum then txt = txt .. "  Staubsauger" end
      if flashlight then txt = txt .. "  Licht" end
      local okW, tw = pcall(ctx.textWidth, ctx, txt)
      tw = okW and tw or #txt * 6
      pcall(ctx.rect, ctx, w - tw - 8, y - 2, tw + 6, 12, 0x90000000)
      pcall(ctx.text, ctx, txt, w - tw - 5, y, "#9FE7FF")
      y = y + 14
    end
    if navTarget and setting("nav_hud") then
      local arrow, dist = bearing(navTarget.x + 0.5, navTarget.z + 0.5)
      local txt = string.format("%s %s  %d m", arrow, navTarget.name, floor(dist))
      local okW, tw = pcall(ctx.textWidth, ctx, txt)
      tw = okW and tw or #txt * 6
      pcall(ctx.rect, ctx, floor(w / 2 - tw / 2) - 3, 2, tw + 6, 12, 0x90000000)
      pcall(ctx.text, ctx, txt, floor(w / 2 - tw / 2), 4, dist < 4 and "#7CFF7C" or "#FFFFFF")
    end
  end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function onJoin()
  loadAll()
  active = true
  tickNo = 0
  navTarget = nil
end

on("world_join", onJoin)
on("world_leave", function() active = false; vacuum = false end)

on("create_zeus:stats", function(e)
  if type(e) == "table" or type(e) == "userdata" then createStats = e end
end)

on("tick", function()
  if not active then
    local ok, ex = call(player, "exists")
    if ok and ex then onJoin() else return end
  end
  tickNo = tickNo + 1
  if vacuum and tickNo % 10 == 0 then
    local r = floor(setting("vac_radius") or 8)
    command(string.format("tp @e[type=item,distance=..%d] @s", r))
    command(string.format("tp @e[type=experience_orb,distance=..%d] @s", r))
  end
  if tickNo % 20 == 0 then
    local t = ticksOfDay()
    if t then
      local phase = (t >= 23000 or t < 1000) and "dawn" or ((t >= 12000 and t < 13000) and "dusk" or "other")
      if phase ~= lastPhase then
        if phase == "dawn" and alarmDawn and lastPhase then toast("Guten Morgen! Die Sonne geht auf.") end
        if phase == "dusk" and alarmDusk and lastPhase then toast("Achtung: Die Nacht beginnt!") end
        lastPhase = phase
      end
    end
  end
  if navTarget and tickNo % 20 == 0 then
    local _, dist = bearing(navTarget.x + 0.5, navTarget.z + 0.5)
    if dist < 3 then toast("Ziel erreicht: " .. navTarget.name); navTarget = nil end
  end
end)

logMsg("MC-Device-Port v" .. MOD_VERSION .. " geladen. Taste P öffnet das Handy.")

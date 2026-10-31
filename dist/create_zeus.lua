-- name: Create (Eaglercraft-Port)
-- id: create_zeus
-- version: 0.4.0
-- author: Larpbase
-- description: Inoffizieller Create-Port für Eaglercraft 26.3 (Zeus-Lua). Wellen, Zahnräder, Motoren, Bohrer, Lüfter, Presse, Mahlstein, Förderband und Stress-System.
--
-- Funktionsweise
--   * Zeus-Lua-Mods laufen nur im Einzelspieler und können keine eigenen Blöcke registrieren.
--     Deshalb besteht jedes Bauteil aus einem Vanilla-Trägerblock plus Display-Entities,
--     die per Befehl gesetzt und animiert werden. Die Welt braucht dafür aktivierte Cheats.
--   * Das Kinetik-Netz (Drehzahl, Drehrichtung, Übersetzung, Stress) rechnet diese Mod in Lua,
--     angelehnt an Create (Code MIT, (c) simibubi & Create-Team). Es werden keine Create-Assets genutzt.

local MOD_VERSION = "0.4.0"

---------------------------------------------------------------------------
-- Kompatibilität: Zeus-Bibliotheken defensiv ansprechen
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
local function logMsg(msg)
  local lg = lib("log") or print
  pcall(lg, "[Create] " .. tostring(msg))
end
local function warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  logMsg(msg)
end

-- call(lib, "fn", ...) -> ok, results...
local function call(t, fname, ...)
  local f = field(t, fname)
  if type(f) ~= "function" then return false end
  local res = table.pack(pcall(f, ...))
  if not res[1] then
    warnOnce("err:" .. fname, fname .. " fehlgeschlagen: " .. tostring(res[2]))
    return false
  end
  return true, table.unpack(res, 2, res.n)
end

local chat, player, game, world, keys, hud, ui, commands, storage, settings =
  lib("chat"), lib("player"), lib("game"), lib("world"), lib("keys"), lib("hud"), lib("ui"), lib("commands"), lib("storage"), lib("settings")

local floor, abs, sqrt = math.floor, math.abs, math.sqrt
local mmin = math.min or function(a, b) if a < b then return a end return b end
local mmax = math.max or function(a, b) if a > b then return a end return b end
local tinsert = table.insert
local tremove = table.remove or function(t, i)
  local n = #t
  i = i or n
  local v = t[i]
  for k = i, n - 1 do t[k] = t[k + 1] end
  t[n] = nil
  return v
end
local function tsort(t, lt)
  if table.sort then return table.sort(t, lt) end
  for i = 2, #t do
    local v, j = t[i], i - 1
    while j >= 1 and lt(v, t[j]) do t[j + 1] = t[j]; j = j - 1 end
    t[j + 1] = v
  end
end

local function say(msg)
  if not call(chat, "print", "§6[Create]§r " .. msg) then logMsg(msg) end
end
local function toast(msg)
  local n = lib("notify")
  if type(n) == "function" and pcall(n, msg) then return end
  if not call(ui, "notify", msg) then say(msg) end
end

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
local defaults = { goggles = true, quiet = true, animate = true, slash = false, budget = 24, models = true }
local function setting(name)
  local v = field(settings, name)
  if v == nil then return defaults[name] end
  return v
end
if settings then
  pcall(function()
    settings.toggle("models", { label = "3D-Modelle (Ressourcenpaket nötig)", default = true })
    settings.toggle("goggles", { label = "Ingenieursbrille (HUD)", default = true })
    settings.toggle("animate", { label = "Drehende Teile animieren", default = true })
    settings.toggle("quiet", { label = "Befehlsausgaben ausblenden", default = true })
    settings.toggle("slash", { label = "Befehle mit / senden (nur falls nichts passiert)", default = false })
    settings.slider("budget", { label = "Max. Befehle pro Tick", min = 4, max = 64, step = 1, default = 24 })
  end)
end

---------------------------------------------------------------------------
-- Mini-JSON (für storage)
---------------------------------------------------------------------------
local json = {}
do
  local function esc(s)
    return (s:gsub('[%c"\\]', function(c)
      local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return m[c] or string.format("\\u%04x", c:byte())
    end))
  end
  local function enc(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then return "0" end
      if floor(v) == v and abs(v) < 1e15 then return string.format("%d", floor(v)) end
      return string.format("%.6g", v)
    elseif t == "string" then return '"' .. esc(v) .. '"'
    elseif t == "table" then
      if #v > 0 or next(v) == nil then
        local out = {}
        for i = 1, #v do out[i] = enc(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
      end
      local out = {}
      for k, val in pairs(v) do out[#out + 1] = '"' .. esc(tostring(k)) .. '":' .. enc(val) end
      return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
  end
  json.encode = enc

  function json.decode(s)
    local i = 1
    local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
    local val
    local function str()
      i = i + 1
      local out = {}
      while true do
        local c = s:sub(i, i)
        if c == "" then error("JSON: Zeichenkette offen") end
        if c == '"' then i = i + 1; break end
        if c == "\\" then
          local n = s:sub(i + 1, i + 1)
          local m = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f" }
          if n == "u" then
            out[#out + 1] = utf8 and utf8.char(tonumber(s:sub(i + 2, i + 5), 16)) or "?"
            i = i + 6
          else
            out[#out + 1] = m[n] or n
            i = i + 2
          end
        else
          out[#out + 1] = c
          i = i + 1
        end
      end
      return table.concat(out)
    end
    function val()
      ws()
      local c = s:sub(i, i)
      if c == "{" then
        i = i + 1
        local o = {}
        ws()
        if s:sub(i, i) == "}" then i = i + 1; return o end
        while true do
          ws()
          local k = str()
          ws(); i = i + 1 -- ':'
          o[k] = val()
          ws()
          local d = s:sub(i, i); i = i + 1
          if d == "}" then return o end
        end
      elseif c == "[" then
        i = i + 1
        local a = {}
        ws()
        if s:sub(i, i) == "]" then i = i + 1; return a end
        while true do
          a[#a + 1] = val()
          ws()
          local d = s:sub(i, i); i = i + 1
          if d == "]" then return a end
        end
      elseif c == '"' then return str()
      elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
      elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
      elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
      else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" then error("JSON: unerwartetes Zeichen bei " .. i) end
        i = i + #num
        return tonumber(num)
      end
    end
    return val()
  end
end

---------------------------------------------------------------------------
-- Geometrie
---------------------------------------------------------------------------
local FACINGS = {
  east = { 1, 0, 0, "x", 1 }, west = { -1, 0, 0, "x", -1 },
  up = { 0, 1, 0, "y", 1 }, down = { 0, -1, 0, "y", -1 },
  south = { 0, 0, 1, "z", 1 }, north = { 0, 0, -1, "z", -1 },
}
local FACING_LIST = { "east", "west", "up", "down", "south", "north" }
local OPPOSITE = { east = "west", west = "east", up = "down", down = "up", south = "north", north = "south" }
local AXIS_VEC = { x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }
local PERP = { x = { "y", "z" }, y = { "x", "z" }, z = { "x", "y" } }

local function key3(x, y, z) return x .. "," .. y .. "," .. z end

local function normFacing(f)
  if f == nil then return nil end
  if type(f) == "string" then
    f = f:lower()
    if FACINGS[f] then return f end
    local alias = { top = "up", bottom = "down", n = "north", s = "south", e = "east", w = "west", ["+x"] = "east", ["-x"] = "west", ["+y"] = "up", ["-y"] = "down", ["+z"] = "south", ["-z"] = "north" }
    return alias[f]
  end
  if type(f) == "table" then
    local x, y, z = f.x or f[1] or 0, f.y or f[2] or 0, f.z or f[3] or 0
    for name, v in pairs(FACINGS) do
      if v[1] == x and v[2] == y and v[3] == z then return name end
    end
  end
  return nil
end

-- Quaternionen als {x, y, z, w}
local function qmul(a, b)
  return {
    a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
    a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
    a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
  }
end
local function qaxis(ax, ay, az, deg)
  local h = math.rad(deg) / 2
  local s = math.sin(h)
  return { ax * s, ay * s, az * s, math.cos(h) }
end
-- Basis: lokale Y-Achse (Drehachse aller Modelle) -> Weltachse
local BASE = {
  y = { 0, 0, 0, 1 },
  x = qaxis(0, 0, 1, -90),
  z = qaxis(1, 0, 0, 90),
}
-- Basis für gerichtete Modelle: lokales +Y (Spitze von Bohrkopf/Propeller) -> Blickrichtung
local BASE_FACING = {
  up = { 0, 0, 0, 1 },
  down = qaxis(1, 0, 0, 180),
  east = qaxis(0, 0, 1, -90),
  west = qaxis(0, 0, 1, 90),
  south = qaxis(1, 0, 0, 90),
  north = qaxis(1, 0, 0, -90),
}

local function f3(v)
  local s = string.format("%.3f", v)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s .. "f"
end
local function farr(t)
  local out = {}
  for i = 1, #t do out[i] = f3(t[i]) end
  return "[" .. table.concat(out, ",") .. "]"
end

---------------------------------------------------------------------------
-- Bauteile
---------------------------------------------------------------------------
-- Stresswerte angelehnt an Create's Standard-Config (SU pro RPM).
local TYPES = {
  shaft = { name = "Welle", axial = true, carrier = "barrier",
    parts = { { item = "polished_andesite", s = { 0.22, 1.0, 0.22 } } } },
  cog = { name = "Zahnrad", axial = true, cog = "small", carrier = "barrier",
    parts = {
      { item = "polished_andesite", s = { 0.22, 1.0, 0.22 } },
      { item = "spruce_planks", s = { 0.9, 0.24, 0.9 } },
      { item = "spruce_planks", s = { 0.9, 0.24, 0.9 }, yaw = 45 },
      { item = "stripped_spruce_log", s = { 0.48, 0.3, 0.48 } },
    } },
  large_cog = { name = "Großes Zahnrad", axial = true, cog = "large", carrier = "barrier",
    parts = {
      { item = "polished_andesite", s = { 0.22, 1.0, 0.22 } },
      { item = "dark_oak_planks", s = { 2.35, 0.24, 2.35 } },
      { item = "dark_oak_planks", s = { 2.35, 0.24, 2.35 }, yaw = 30 },
      { item = "dark_oak_planks", s = { 2.35, 0.24, 2.35 }, yaw = 60 },
      { item = "stripped_dark_oak_log", s = { 1.1, 0.32, 1.1 } },
    } },
  gearbox = { name = "Getriebe", gearbox = true, carrier = "polished_andesite", parts = {} },
  crank = { name = "Handkurbel", axial = true, carrier = "barrier", source = { rpm = 32, cap = 8, manual = true },
    parts = {
      { item = "polished_andesite", s = { 0.22, 0.7, 0.22 } },
      { item = "stripped_spruce_log", s = { 0.45, 0.16, 0.45 } },
      { item = "spruce_planks", s = { 1.0, 0.12, 0.18 } },
    } },
  water_wheel = { name = "Wasserrad", axial = true, carrier = "barrier", source = { rpm = 8, cap = 32 },
    parts = {
      { item = "stripped_oak_log", s = { 0.6, 0.9, 0.6 } },
      { item = "oak_planks", s = { 2.7, 0.85, 0.14 } },
      { item = "oak_planks", s = { 0.14, 0.85, 2.7 } },
      { item = "oak_planks", s = { 2.2, 0.1, 2.2 }, yaw = 45 },
    } },
  motor = { name = "Kreativmotor", axial = true, carrier = "purpur_pillar", carrierAxis = true,
    source = { rpm = 64, creative = true },
    parts = { { item = "polished_andesite", s = { 0.22, 1.5, 0.22 } } } },
  drill = { name = "Mechanischer Bohrer", directional = true, carrier = "polished_andesite", impact = 4,
    parts = {
      { item = "iron_block", s = { 0.62, 0.3, 0.62 }, off = 0.62 },
      { item = "iron_block", s = { 0.62, 0.3, 0.62 }, yaw = 45, off = 0.62 },
      { item = "iron_block", s = { 0.32, 0.25, 0.32 }, off = 0.86 },
    } },
  fan = { name = "Lüfter", directional = true, carrier = "polished_andesite", impact = 2,
    parts = {
      { item = "light_gray_concrete", s = { 0.92, 0.06, 0.16 }, off = 0.53 },
      { item = "light_gray_concrete", s = { 0.16, 0.06, 0.92 }, off = 0.53 },
      { item = "polished_andesite", s = { 0.3, 0.12, 0.3 }, off = 0.54 },
    } },
  press = { name = "Mechanische Presse", horizontal = true, carrier = "polished_andesite", impact = 8,
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  millstone = { name = "Mahlstein", millstone = true, carrier = "polished_andesite", impact = 4,
    parts = {
      { item = "smooth_stone", s = { 0.95, 0.28, 0.95 }, off = 0.62 },
      { item = "smooth_stone", s = { 0.95, 0.28, 0.95 }, yaw = 45, off = 0.62 },
    } },
  belt = { name = "Förderband", belt = true, carrier = "black_carpet", parts = {} },
  speedometer = { name = "Tachometer", axial = true, gauge = "speed", carrier = "polished_andesite",
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  stressometer = { name = "Stressometer", axial = true, gauge = "stress", carrier = "polished_andesite",
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  -- weitere Create-Kernblöcke
  encased_shaft = { name = "Gehäuste Welle", axial = true, carrier = "polished_andesite", parts = {} },
  clutch = { name = "Kupplung", axial = true, redstone = "clutch", carrier = "redstone_lamp", parts = {} },
  gearshift = { name = "Gangschaltung", axial = true, redstone = "gearshift", carrier = "redstone_lamp", parts = {} },
  chain_drive = { name = "Kettenantrieb", axial = true, chain = true, carrier = "polished_andesite", parts = {} },
  saw = { name = "Mechanische Säge", directional = true, carrier = "polished_andesite", impact = 4,
    parts = {
      { item = "iron_block", s = { 0.9, 0.06, 0.9 }, off = 0.55 },
      { item = "iron_block", s = { 0.9, 0.06, 0.9 }, yaw = 45, off = 0.55 },
    } },
  crushing_wheel = { name = "Brechrad", axial = true, crusher = true, carrier = "barrier", impact = 8,
    parts = {
      { item = "cobblestone", s = { 1.7, 0.9, 1.7 } },
      { item = "cobblestone", s = { 1.7, 0.9, 1.7 }, yaw = 45 },
      { item = "polished_andesite", s = { 0.22, 1.0, 0.22 } },
    } },
  windmill_bearing = { name = "Windmühlenlager", directional = true, carrier = "polished_andesite",
    source = { windmill = true, cap = 32 },
    parts = {
      { item = "white_wool", s = { 4.2, 0.08, 0.7 }, off = 0.6 },
      { item = "white_wool", s = { 0.7, 0.08, 4.2 }, off = 0.6 },
    } },
  sail = { name = "Segel", static = true, carrier = "white_wool", parts = {} },
  -- Addon "Create: Kanonen"
  cannon = { name = "Kanonenrohr", addon = "kanonen", directional = true, carrier = "polished_blackstone", impact = 8,
    parts = { { item = "black_concrete", s = { 0.5, 1.2, 0.5 }, off = 0.45 } } },
  -- Addon "Create: Elektrik"
  alternator = { name = "Lichtmaschine", addon = "elektrik", axial = true, carrier = "copper_block", impact = 8,
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  electric_motor = { name = "Elektromotor", addon = "elektrik", axial = true, carrier = "waxed_copper_block",
    source = { rpm = 128, cap = 16, electric = true },
    parts = { { item = "polished_andesite", s = { 0.22, 1.5, 0.22 } } } },
  -- Addon "Create: Aeronautik"
  -- Addon "Create: Verzauberungsindustrie"
  enchanter = { name = "Mechanischer Verzauberer", addon = "verzauberung", axial = true, carrier = "enchanting_table", impact = 8,
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  xp_drain = { name = "Erfahrungs-Abfluss", addon = "verzauberung", axial = true, carrier = "sculk", impact = 4,
    parts = { { item = "polished_andesite", s = { 0.22, 1.3, 0.22 } } } },
  -- Addon "Create: Kraftwerk" (keine Drehung, nur Strom)
  solar_panel = { name = "Solarpanel", addon = "kraftwerk", static = true, carrier = "daylight_detector", parts = {} },
  battery = { name = "Akku", addon = "kraftwerk", static = true, carrier = "copper_block", parts = {} },
  propeller_bearing = { name = "Propeller-Lager", addon = "aeronautik", directional = true, carrier = "polished_andesite", impact = 6,
    parts = {
      { item = "white_wool", s = { 2.6, 0.08, 0.4 }, off = 0.6 },
      { item = "white_wool", s = { 0.4, 0.08, 2.6 }, off = 0.6 },
    } },
}
local TYPE_ORDER = { "shaft", "encased_shaft", "cog", "large_cog", "gearbox", "chain_drive", "clutch", "gearshift",
  "crank", "water_wheel", "windmill_bearing", "sail", "motor",
  "drill", "saw", "fan", "press", "millstone", "crushing_wheel", "belt", "speedometer", "stressometer",
  "cannon", "alternator", "electric_motor", "propeller_bearing", "enchanter", "xp_drain", "solar_panel", "battery" }

-- 3D-Modelle aus dem Ressourcenpaket (assets/create_zeus/items/<name>.json).
-- Gleiche Ausrichtung wie die Original-Create-Modelle, damit beide Pakete passen:
--   Wellen/Zahnräder: Achse Y · Bohrkopf/Propeller: Achse Z (fix dreht Z nach Y) · Gehäuse: Vorderseite oben
local FIX_Z = qaxis(1, 0, 0, -90)
local MODELS = {
  shaft = { spin = "d_shaft" },
  cog = { spin = "d_cog", teeth = 8 },
  large_cog = { spin = "d_lcog", teeth = 16 },
  gearbox = { static = "d_gearbox" },
  crank = { spin = "d_crank", useFacing = true },
  water_wheel = { spin = "d_wheel" },
  motor = { static = "d_cmotor", staticAxis = true, useFacing = true, spin = "d_shaft" },
  drill = { static = "d_drill_c", staticFacing = true, spin = "d_drill_h", fix = FIX_Z },
  fan = { static = "d_fan_c", staticFacing = true, spin = "d_prop", fix = FIX_Z },
  press = { static = "d_press_c", spin = "d_shaft", head = "d_press_h" },
  millstone = { static = "d_mill_b", spin = "d_mill_i" },
  belt = {},
  speedometer = { static = "d_speedo", spin = "d_shaft" },
  stressometer = { static = "d_stresso", spin = "d_shaft" },
  encased_shaft = { static = "d_encased", staticAxis = true },
  clutch = { static = "d_clutch", staticAxis = true },
  gearshift = { static = "d_gearshift", staticAxis = true },
  chain_drive = { static = "d_chain", staticAxis = true },
  saw = { static = "d_saw_c", staticFacing = true, spin = "d_saw_blade", off = 0.55 },
  crushing_wheel = { spin = "d_crush" },
  windmill_bearing = { static = "d_wbearing", staticFacing = true, spin = "d_windmill", off = 0.6, scale = 2 },
  sail = { static = "d_sail" },
  cannon = { static = "d_cannon", staticFacing = true },
  alternator = { static = "d_alt", staticAxis = true, spin = "d_shaft" },
  electric_motor = { static = "d_emotor", staticAxis = true, spin = "d_shaft" },
  propeller_bearing = { static = "d_bearing", staticFacing = true, spin = "d_bprop", off = 0.6 },
  enchanter = { static = "d_enchanter", staticAxis = true, spin = "d_shaft" },
  xp_drain = { static = "d_xp_drain", staticAxis = true, spin = "d_shaft" },
  solar_panel = { static = "d_solar" },
  battery = { static = "d_battery" },
}

-- Inventar-Items: eindeutiges Vanilla-Grunditem ohne Rechtsklick-Funktion + eigenes Modell
local KIT = {
  { "shaft", "breeze_rod", "create_zeus:shaft", 64 },
  { "cog", "nautilus_shell", "create_zeus:cogwheel", 64 },
  { "large_cog", "heart_of_the_sea", "create_zeus:large_cogwheel", 16 },
  { "gearbox", "shulker_shell", "create_zeus:gearbox", 16 },
  { "crank", "rabbit_hide", "create_zeus:hand_crank", 4 },
  { "water_wheel", "prismarine_crystals", "create_zeus:water_wheel", 8 },
  { "motor", "popped_chorus_fruit", "create_zeus:creative_motor", 8 },
  { "drill", "prismarine_shard", "create_zeus:mechanical_drill", 8 },
  { "fan", "phantom_membrane", "create_zeus:encased_fan", 8 },
  { "press", "armadillo_scute", "create_zeus:mechanical_press", 8 },
  { "millstone", "turtle_scute", "create_zeus:millstone", 8 },
  { "belt", "disc_fragment_5", "minecraft:black_carpet", 64 },
  { "speedometer", "echo_shard", "create_zeus:speedometer", 4 },
  { "encased_shaft", "angler_pottery_sherd", "create_zeus:encased_shaft", 32 },
  { "clutch", "archer_pottery_sherd", "create_zeus:clutch", 8 },
  { "gearshift", "arms_up_pottery_sherd", "create_zeus:gearshift", 8 },
  { "chain_drive", "blade_pottery_sherd", "create_zeus:chain_drive", 16 },
  { "saw", "brewer_pottery_sherd", "create_zeus:mechanical_saw", 4 },
  { "crushing_wheel", "burn_pottery_sherd", "create_zeus:crushing_wheel", 4 },
  { "windmill_bearing", "danger_pottery_sherd", "create_zeus:windmill_bearing", 2 },
  { "sail", "explorer_pottery_sherd", "create_zeus:sail", 64 },
  { "stressometer", "firework_star", "create_zeus:stressometer", 4 },
  { "cannon", "ghast_tear", "create_zeus:cannon", 4 },
  { "alternator", "resin_brick", "create_zeus:alternator", 8 },
  { "electric_motor", "amethyst_shard", "create_zeus:electric_motor", 8 },
  { "propeller_bearing", "nether_star", "create_zeus:propeller_bearing", 4 },
  { "enchanter", "netherite_scrap", "create_zeus:enchanter", 4 },
  { "xp_drain", "quartz", "create_zeus:xp_drain", 4 },
  { "solar_panel", "glowstone_dust", "create_zeus:solar_panel", 16 },
  { "battery", "nether_brick", "create_zeus:battery", 8 },
  { "wrench", "rabbit_foot", "create_zeus:wrench", 1 },
}
local PART_BY_ITEM, PART_BY_NAME = {}, {}
for _, k in ipairs(KIT) do PART_BY_ITEM[k[2]] = k[1] end
for name, T in pairs(TYPES) do PART_BY_NAME[T.name:lower()] = name end
PART_BY_NAME["schraubenschlüssel"] = "wrench"

-- Addons (Erweiterungen dieses Ports, inspiriert von bekannten Create-Addons)
local ADDONS = {
  { id = "kanonen", name = "Create: Kanonen", inspired = "Create Big Cannons", version = "1.0.0", size = 38,
    desc = "Kanonenrohr: feuert mit Rotation TNT in Blickrichtung. Je schneller, desto öfter.",
    deps = { "create" }, types = { "cannon" } },
  { id = "elektrik", name = "Create: Elektrik", inspired = "Create Crafts & Additions", version = "1.0.0", size = 52,
    desc = "Lichtmaschine macht aus Rotation Strom (FE), der Elektromotor macht daraus wieder Rotation.",
    deps = { "create" }, types = { "alternator", "electric_motor" } },
  { id = "aeronautik", name = "Create: Aeronautik", inspired = "Create Aeronautics", version = "1.0.0", size = 64,
    desc = "Propeller-Lager: hebt dich und alles über dem Propeller in die Luft. Am besten mit Elektromotor.",
    deps = { "create", "elektrik" }, types = { "propeller_bearing" } },
  { id = "dragons_plus", name = "Create: Dragons Plus", inspired = "Create: Dragons Plus", version = "1.8.1", size = 41,
    desc = "Bibliothek für andere Addons. Neue Lüfter-Verarbeitung: vor Pulverschnee einfrieren, vor einem Drachenkopf enden.",
    deps = { "create" }, types = {} },
  { id = "verzauberung", name = "Create: Verzauberungsindustrie", inspired = "Create: Enchantment Industry", version = "2.5.0", size = 73,
    desc = "Mechanischer Verzauberer macht aus Büchern verzauberte Bücher, der Erfahrungs-Abfluss saugt XP-Kugeln zu dir.",
    deps = { "create", "dragons_plus" }, types = { "enchanter", "xp_drain" } },
  { id = "kraftwerk", name = "Create: Kraftwerk", inspired = "Create: New Age", version = "1.1.0", size = 58,
    desc = "Solarpanel erzeugt am Tag Strom, der Akku speichert mehr davon für deine Elektromotoren.",
    deps = { "create", "elektrik" }, types = { "solar_panel", "battery" } },
}
local ADDON_BY_ID = { create = { id = "create", name = "Create (Port)", version = MOD_VERSION, core = true } }
for _, a in ipairs(ADDONS) do ADDON_BY_ID[a.id] = a end
local addonState = { installed = {}, enabled = {} }

local function addonOn(id)
  if id == nil or id == "create" then return true end
  return addonState.installed[id] == true and addonState.enabled[id] == true
end
local function typeOn(typeName)
  local T = TYPES[typeName]
  return T ~= nil and addonOn(T.addon)
end

-- Rezepte (nur Vanilla-Items)
local MILL = {
  { "cobblestone", "gravel" }, { "gravel", "sand" }, { "sandstone", "sand" }, { "red_sandstone", "red_sand" },
  { "bone", "bone_meal" }, { "sugar_cane", "sugar" }, { "blaze_rod", "blaze_powder" },
  { "dandelion", "yellow_dye" }, { "poppy", "red_dye" }, { "cornflower", "blue_dye" },
  { "lily_of_the_valley", "white_dye" }, { "wither_rose", "black_dye" }, { "cactus", "green_dye" },
}
local PRESS = {
  { "sugar_cane", "paper" }, { "ice", "packed_ice" }, { "packed_ice", "blue_ice" },
  { "melon", "melon_slice" }, { "dirt", "coarse_dirt" },
}
local SMELT = {
  { "raw_iron", "iron_ingot" }, { "raw_gold", "gold_ingot" }, { "raw_copper", "copper_ingot" },
  { "sand", "glass" }, { "red_sand", "glass" }, { "cobblestone", "stone" }, { "clay_ball", "brick" },
  { "potato", "baked_potato" }, { "beef", "cooked_beef" }, { "porkchop", "cooked_porkchop" },
  { "chicken", "cooked_chicken" }, { "mutton", "cooked_mutton" }, { "cod", "cooked_cod" },
  { "salmon", "cooked_salmon" }, { "kelp", "dried_kelp" }, { "cactus", "green_dye" },
  { "wet_sponge", "sponge" }, { "netherrack", "nether_brick" },
}
local WASH = {
  { "gravel", "flint" }, { "sand", "clay_ball" }, { "red_sand", "gold_nugget" }, { "soul_sand", "quartz" },
  { "magma_block", "obsidian" }, { "white_wool", "string" },
}
local FREEZE = {
  { "water_bucket", "powder_snow_bucket" }, { "magma_cream", "slime_ball" }, { "blaze_rod", "breeze_rod" },
  { "lava_bucket", "bucket" }, { "magma_block", "packed_ice" },
}
local ENDING = {
  { "ender_pearl", "ender_eye" }, { "chorus_fruit", "popped_chorus_fruit" }, { "cobblestone", "end_stone" },
  { "stone_bricks", "end_stone_bricks" }, { "purple_dye", "purpur_block" },
}
-- Brechräder (Ausgabe pro Einzel-Item, wie Create es auf Bändern/Depots verarbeitet)
local CRUSH = {
  { "iron_ore", "raw_iron", 2 }, { "deepslate_iron_ore", "raw_iron", 2 }, { "gold_ore", "raw_gold", 2 },
  { "deepslate_gold_ore", "raw_gold", 2 }, { "copper_ore", "raw_copper", 5 }, { "deepslate_copper_ore", "raw_copper", 5 },
  { "coal_ore", "coal", 2 }, { "deepslate_coal_ore", "coal", 2 }, { "redstone_ore", "redstone", 6 },
  { "lapis_ore", "lapis_lazuli", 8 }, { "diamond_ore", "diamond", 2 }, { "emerald_ore", "emerald", 2 },
  { "nether_gold_ore", "gold_nugget", 18 }, { "nether_quartz_ore", "quartz", 3 }, { "cobblestone", "gravel", 1 },
  { "gravel", "sand", 1 }, { "white_wool", "string", 3 }, { "bone", "bone_meal", 5 }, { "blaze_rod", "blaze_powder", 3 },
  { "sugar_cane", "sugar", 2 },
}
local SAW = {
  { "oak_log", "oak_planks" }, { "spruce_log", "spruce_planks" }, { "birch_log", "birch_planks" },
  { "jungle_log", "jungle_planks" }, { "acacia_log", "acacia_planks" }, { "dark_oak_log", "dark_oak_planks" },
  { "mangrove_log", "mangrove_planks" }, { "cherry_log", "cherry_planks" }, { "pale_oak_log", "pale_oak_planks" },
  { "crimson_stem", "crimson_planks" }, { "warped_stem", "warped_planks" },
}
local ENCHANTS = { "mending", "unbreaking", "efficiency", "fortune", "sharpness", "protection", "feather_falling",
  "looting", "power", "silk_touch", "respiration", "depth_strider" }
local HAUNT = {
  { "soul_sand", "soul_soil" }, { "red_mushroom", "crimson_fungus" }, { "brown_mushroom", "warped_fungus" },
  { "potato", "poisonous_potato" }, { "egg", "turtle_egg" },
}

---------------------------------------------------------------------------
-- Zustand
---------------------------------------------------------------------------
local comps = {}        -- key3 -> Bauteil
local byId = {}         -- id -> Bauteil
local nextId = 1
local networks = {}     -- netId -> {capacity, impact, overstressed, conflict, speedMax}
local worldKey = "welt"
local dirty = false
local solveNeeded = true
local tickNo = 0
local selected = "shaft"
local crankHeld = false
local active = false   -- in einer Welt
local query = { ok = false, pinged = false }   -- Rückkanal: Weltabfragen per tellraw
local energy = 0       -- Strom (FE) aus Lichtmaschinen, für Elektromotoren
local ENERGY_MAX = 200000

local function worldName()
  for _, try in ipairs({
    function() return field(world, "name") and world.name() end,
    function() return field(game, "worldName") and game.worldName() end,
    function() local s = field(game, "server") and game.server(); if type(s) == "string" and s ~= "" then return s end end,
  }) do
    local ok, v = pcall(try)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return "welt"
end

local function dimension()
  local ok, d = call(player, "dimension")
  if ok and d then return tostring(d) end
  return "overworld"
end

local function storageKey() return "welt:" .. worldKey end

local function save()
  if not storage then warnOnce("nostore", "storage fehlt – Anlagen werden nicht gespeichert"); return end
  local list = {}
  for _, c in pairs(comps) do
    list[#list + 1] = { id = c.id, t = c.type, x = c.x, y = c.y, z = c.z, a = c.axis, f = c.facing,
      rpm = c.rpm, rev = c.rev, d = c.dim, m = c.mode, ba = c.baseAngle }
  end
  local data = json.encode({ v = 2, nextId = nextId, comps = list, energy = floor(energy) })
  if not call(storage, "set", storageKey(), data) then warnOnce("savefail", "Speichern fehlgeschlagen") end
  dirty = false
end

local function loadState()
  comps, byId, nextId = {}, {}, 1
  if not storage then return end
  local ok, raw = call(storage, "get", storageKey())
  if not ok or raw == nil then return end
  local data = raw
  if type(raw) == "string" then
    local ok2, dec = pcall(json.decode, raw)
    if not ok2 then warnOnce("loadfail", "Gespeicherte Anlagen unlesbar: " .. tostring(dec)); return end
    data = dec
  end
  if type(data) ~= "table" then return end
  nextId = tonumber(data.nextId) or 1
  energy = tonumber(data.energy) or 0
  for _, e in ipairs(data.comps or {}) do
    if TYPES[e.t] then
      local c = { id = e.id, type = e.t, x = e.x, y = e.y, z = e.z, axis = e.a, facing = e.f,
        rpm = e.rpm, rev = e.rev, dim = e.d or "overworld", angle = e.ba or 0, baseAngle = e.ba, speed = 0, progress = 0,
        mode = e.m or "parts" }
      comps[key3(c.x, c.y, c.z)] = c
      byId[c.id] = c
      if c.id >= nextId then nextId = c.id + 1 end
    end
  end
end

---------------------------------------------------------------------------
-- Befehlswarteschlange
---------------------------------------------------------------------------
local queue = {}
local qhead = 1
local lastCmdTick = -100
local cmdBroken = false

local function cmd(s)
  queue[#queue + 1] = s
end

local function sendRaw(s)
  if setting("slash") then s = "/" .. s end
  local ok = call(chat, "command", s)
  if not ok and not cmdBroken then
    cmdBroken = true
    say("§cchat.command ist nicht verfügbar – Bauteile können nicht gesetzt werden.")
  end
  lastCmdTick = tickNo
end

local function flushQueue()
  local budget = setting("budget") or 24
  local n = 0
  while qhead <= #queue and n < budget do
    sendRaw(queue[qhead])
    queue[qhead] = nil
    qhead = qhead + 1
    n = n + 1
  end
  if qhead > #queue then queue = {}; qhead = 1 end
end

local function pending() return #queue - qhead + 1 end

-- Meldungen, die unsere eigenen Befehle im Chat erzeugen
local FEEDBACK = {
  "^Modified entity data", "^Entitätsdaten", "^Changed the block", "^Block .* geändert", "^Summoned new",
  "wurde erzeugt", "^Killed", "^Teleported", "teleportiert", "^Game ?rule", "^Spielregel", "^Could not set the block",
  "konnte nicht", "^No entity was found", "^Es wurde keine", "^That position is not loaded", "nicht geladen",
  "^Test passed", "^Test failed", "^Gamerule", "^Removed", "entfernt",
}

---------------------------------------------------------------------------
-- Display-Entities
---------------------------------------------------------------------------
local function axisOf(c)
  local T = TYPES[c.type]
  if T.directional then return FACINGS[c.facing][4] end
  if T.millstone then return "y" end
  return c.axis or "y"
end

local function carrierBlock(c)
  local T = TYPES[c.type]
  if c.mode == "model" and not T.belt and not T.redstone then return "minecraft:barrier" end
  local b = "minecraft:" .. T.carrier
  if T.carrierAxis then b = b .. "[axis=" .. axisOf(c) .. "]" end
  return b
end

local function baseQuat(c)
  if TYPES[c.type].directional then return BASE_FACING[c.facing] end
  if c.mode == "model" and MODELS[c.type].useFacing and c.facing and FACINGS[c.facing][4] == axisOf(c) then
    return BASE_FACING[c.facing]
  end
  return BASE[axisOf(c)]
end

local function spinQuat(c)
  local q = qmul(baseQuat(c), qaxis(0, 1, 0, c.angle or 0))
  local fix = c.mode == "model" and MODELS[c.type].fix
  if fix then q = qmul(q, fix) end
  return q
end

local function summonModel(c, modelId, tag, q, tr, sc)
  sc = sc or 1
  cmd(string.format(
    'summon item_display %.1f %.1f %.1f {item:{id:"stick",components:{item_model:"create_zeus:%s"}},Tags:["cz","%s"],transformation:{left_rotation:%s,right_rotation:[0f,0f,0f,1f],translation:%s,scale:%s}}',
    c.x + 0.5, c.y + 0.5, c.z + 0.5, modelId, tag, farr(q), farr(tr), farr({ sc, sc, sc })))
end

local function summonModels(c)
  local T, Mo = TYPES[c.type], MODELS[c.type]
  if Mo.static then
    local q = { 0, 0, 0, 1 }
    if Mo.staticFacing then q = BASE_FACING[c.facing]
    elseif Mo.useFacing and c.facing and FACINGS[c.facing][4] == axisOf(c) then q = BASE_FACING[c.facing]
    elseif Mo.staticAxis then q = BASE[axisOf(c)] end
    summonModel(c, Mo.static, "c" .. c.id .. "s", q, { 0, 0, 0 })
  end
  if Mo.spin then
    local tr = { 0, 0, 0 }
    if Mo.off and T.directional then
      local f = FACINGS[c.facing]
      tr = { f[1] * Mo.off, f[2] * Mo.off, f[3] * Mo.off }
    end
    summonModel(c, Mo.spin, "c" .. c.id, spinQuat(c), tr, Mo.scale)
  end
  if Mo.head then summonModel(c, Mo.head, "c" .. c.id .. "h", { 0, 0, 0, 1 }, { 0, 0, 0 }) end
  if T.gauge then
    cmd(string.format(
      'summon text_display %.1f %.2f %.1f {Tags:["cz","c%dt"],billboard:"center",text:{text:"...",color:"gold"},background:1610612736}',
      c.x + 0.5, c.y + 1.25, c.z + 0.5, c.id))
  end
end

local function summonParts(c)
  if c.mode == "model" then return summonModels(c) end
  local T = TYPES[c.type]
  local q = spinQuat(c)
  local fx, fy, fz = 0, 0, 0
  if T.directional then local f = FACINGS[c.facing]; fx, fy, fz = f[1], f[2], f[3] end
  if T.millstone then fy = 1 end
  for _, p in ipairs(T.parts) do
    local off = p.off or 0
    local tr = { fx * off, fy * off, fz * off }
    local rr = p.yaw and qaxis(0, 1, 0, p.yaw) or { 0, 0, 0, 1 }
    cmd(string.format(
      'summon item_display %.1f %.1f %.1f {item:{id:"%s"},Tags:["cz","c%d"],transformation:{left_rotation:%s,right_rotation:%s,translation:%s,scale:%s}}',
      c.x + 0.5, c.y + 0.5, c.z + 0.5, p.item, c.id, farr(q), farr(rr), farr(tr), farr(p.s)))
  end
  if T.gauge then
    cmd(string.format(
      'summon text_display %.1f %.2f %.1f {Tags:["cz","c%dt"],billboard:"center",text:{text:"...",color:"gold"},background:1610612736}',
      c.x + 0.5, c.y + 1.25, c.z + 0.5, c.id))
  end
  if c.type == "press" then
    cmd(string.format(
      'summon block_display %.2f %.2f %.2f {block_state:{Name:"minecraft:iron_block"},Tags:["cz","c%dh"],transformation:{left_rotation:[0f,0f,0f,1f],right_rotation:[0f,0f,0f,1f],translation:[0f,0f,0f],scale:[0.8f,0.25f,0.8f]}}',
      c.x + 0.1, c.y - 0.3, c.z + 0.1, c.id))
  end
end

local function buildComponent(c)
  local T = TYPES[c.type]
  cmd(string.format("setblock %d %d %d %s keep", c.x, c.y, c.z, carrierBlock(c)))
  summonParts(c)
end

local function unbuildComponent(c, keepBlock)
  cmd(string.format("kill @e[tag=c%d]", c.id))
  if TYPES[c.type].gauge then cmd(string.format("kill @e[tag=c%dt]", c.id)) end
  if c.type == "press" then cmd(string.format("kill @e[tag=c%dh]", c.id)) end
  if c.mode == "model" and MODELS[c.type].static then cmd(string.format("kill @e[tag=c%ds]", c.id)) end
  if not keepBlock then cmd(string.format("setblock %d %d %d air", c.x, c.y, c.z)) end
end

---------------------------------------------------------------------------
-- Kinetik-Netz
---------------------------------------------------------------------------
local function at(x, y, z) return comps[key3(x, y, z)] end

-- Nimmt das Bauteil über die Seite `face` (Richtung von c aus gesehen) eine Wellenverbindung an?
local function acceptsShaft(c, face)
  local T = TYPES[c.type]
  local fa = FACINGS[face][4]
  if T.axial then return fa == c.axis end
  if T.gearbox then return fa ~= c.axis end
  if T.directional then return face == OPPOSITE[c.facing] end
  if T.horizontal then return fa == c.axis end
  if T.millstone then return face ~= "up" end
  return false
end

-- Getriebe: Vorzeichen pro Ausgangsachse
local function gearboxSign(c, face)
  local fa = FACINGS[face][4]
  local p = PERP[c.axis]
  return (fa == p[1]) and 1 or -1
end

-- Liefert {nachbar, verhältnis} mit speed(nachbar) = verhältnis * speed(c)
local function powered(c)
  return (c.rsPowered == true) or (c.manualOn == true)
end

local function links(c)
  local out = {}
  local T = TYPES[c.type]
  if T.belt or not typeOn(c.type) then return out end
  if T.redstone == "clutch" and powered(c) then return out end   -- gekuppelt: trennt die Drehung
  for _, face in ipairs(FACING_LIST) do
    if acceptsShaft(c, face) then
      local f = FACINGS[face]
      local n = at(c.x + f[1], c.y + f[2], c.z + f[3])
      if n and not TYPES[n.type].belt and typeOn(n.type) and acceptsShaft(n, OPPOSITE[face]) then
        local r = 1
        if T.gearbox then r = r * gearboxSign(c, face) end
        if TYPES[n.type].gearbox then r = r * gearboxSign(n, OPPOSITE[face]) end
        -- Gangschaltung mit Redstone: dreht die Ausgangsseite um
        if T.redstone == "gearshift" and powered(c) and FACINGS[face][5] < 0 then r = -r end
        if TYPES[n.type].redstone == "gearshift" and powered(n) and FACINGS[OPPOSITE[face]][5] < 0 then r = -r end
        if TYPES[n.type].redstone == "clutch" and powered(n) then r = nil end
        if r then out[#out + 1] = { n, r } end
      end
    end
  end
  -- Kettenantriebe nebeneinander (gleiche Achse) laufen gleich schnell
  if T.chain then
    for _, ax in ipairs(PERP[c.axis]) do
      local v = AXIS_VEC[ax]
      for _, sgn in ipairs({ 1, -1 }) do
        local n = at(c.x + v[1] * sgn, c.y + v[2] * sgn, c.z + v[3] * sgn)
        if n and TYPES[n.type].chain and n.axis == c.axis and typeOn(n.type) then out[#out + 1] = { n, 1 } end
      end
    end
  end
  if T.cog then
    local p = PERP[c.axis]
    local a, b = AXIS_VEC[p[1]], AXIS_VEC[p[2]]
    local function probe(dx, dy, dz, wantLarge, ratio)
      local n = at(c.x + dx, c.y + dy, c.z + dz)
      if n and TYPES[n.type].cog == wantLarge and n.axis == c.axis then out[#out + 1] = { n, ratio } end
    end
    for _, s in ipairs({ 1, -1 }) do
      if T.cog == "small" then
        probe(a[1] * s, a[2] * s, a[3] * s, "small", -1)
        probe(b[1] * s, b[2] * s, b[3] * s, "small", -1)
        for _, t in ipairs({ 1, -1 }) do
          probe(a[1] * s + b[1] * t, a[2] * s + b[2] * t, a[3] * s + b[3] * t, "large", -0.5)
        end
      else
        for _, t in ipairs({ 1, -1 }) do
          probe(a[1] * s + b[1] * t, a[2] * s + b[2] * t, a[3] * s + b[3] * t, "small", -2)
        end
      end
    end
  end
  return out
end

local function sourceSpeed(c)
  local T = TYPES[c.type]
  if not T.source or not typeOn(c.type) then return nil end
  local sign = c.rev and -1 or 1
  if T.source.electric then
    if not c.powered then return nil end
    return (c.rpm or T.source.rpm) * sign
  end
  if T.source.manual then
    if (c.crankUntil or -1) >= tickNo then return T.source.rpm * (c.crankDir or 1) end
    return nil
  end
  if T.source.creative then return (c.rpm or T.source.rpm) * sign end
  if T.source.windmill then
    local n = c.sails or 0
    if n < 8 then return nil end          -- wie in Create: mindestens 8 Segel
    return mmin(16, floor(n / 2)) * sign
  end
  if c.type == "water_wheel" and c.waterKnown and not c.water then return nil end
  return T.source.rpm * sign
end

local function sourceCapacity(c, speed)
  local T = TYPES[c.type]
  if T.source.creative then return 16384 end
  if T.source.windmill then return T.source.cap * abs(speed) end
  if T.source.electric then return T.source.cap * abs(speed) end
  return T.source.cap * abs(speed)
end

local function solve()
  networks = {}
  local visited = {}
  local netId = 0
  for _, start in pairs(comps) do
    if not visited[start] and not TYPES[start.type].belt then
      netId = netId + 1
      local rel = { [start] = 1 }
      local members = { start }
      visited[start] = true
      local conflict = false
      local qi = 1
      while qi <= #members do
        local c = members[qi]; qi = qi + 1
        for _, l in ipairs(links(c)) do
          local n, r = l[1], l[2]
          local want = rel[c] * r
          if rel[n] == nil then
            rel[n] = want
            visited[n] = true
            members[#members + 1] = n
          elseif abs(rel[n] - want) > 1e-6 * mmax(1, abs(want)) then
            conflict = true
          end
        end
      end
      -- Quellen abgleichen
      local k = nil
      local capacity = 0
      for _, c in ipairs(members) do
        local s = sourceSpeed(c)
        if s then
          local kk = s / rel[c]
          if k == nil then k = kk
          elseif abs(k - kk) > 1e-6 * mmax(1, abs(kk)) then conflict = true end
          capacity = capacity + sourceCapacity(c, s)
        end
      end
      k = k or 0
      -- Höchstdrehzahl 256 RPM
      local maxRel = 0
      for _, c in ipairs(members) do maxRel = mmax(maxRel, abs(rel[c])) end
      local overspeed = false
      if maxRel * abs(k) > 256 then
        overspeed = true
        k = (k > 0 and 1 or -1) * 256 / maxRel
      end
      local impact = 0
      for _, c in ipairs(members) do
        local imp = TYPES[c.type].impact
        if imp and typeOn(c.type) then impact = impact + imp * abs(rel[c] * k) end
      end
      local over = impact > capacity + 1e-6 and k ~= 0
      local stopped = conflict or over
      for _, c in ipairs(members) do
        c.net = netId
        c.speed = stopped and 0 or rel[c] * k
      end
      networks[netId] = { capacity = capacity, impact = impact, overstressed = over, conflict = conflict,
        overspeed = overspeed, size = #members, running = (not stopped) and k ~= 0 }
    end
  end
  -- Förderbänder: Gruppen in Laufrichtung, angetrieben von einem angrenzenden Bauteil
  for _, c in pairs(comps) do
    if TYPES[c.type].belt then c.speed = 0; c.net = nil end
  end
  for _, c in pairs(comps) do
    if TYPES[c.type].belt and c.speed == 0 then
      local driven = 0
      for _, face in ipairs(FACING_LIST) do
        local f = FACINGS[face]
        local n = at(c.x + f[1], c.y + f[2], c.z + f[3])
        if n and not TYPES[n.type].belt and abs(n.speed or 0) > abs(driven) then driven = n.speed end
      end
      if driven ~= 0 then
        local f = FACINGS[c.facing]
        for _, dir in ipairs({ 1, -1 }) do
          local i = 0
          while true do
            local b = at(c.x + f[1] * i * dir, c.y, c.z + f[3] * i * dir)
            if not b or not TYPES[b.type].belt or b.facing ~= c.facing then break end
            if abs(b.speed) < abs(driven) then b.speed = abs(driven) end
            i = i + 1
          end
        end
      end
    end
  end
  solveNeeded = false
  -- Anzeigen der Messgeräte aktualisieren
  for _, c in pairs(comps) do
    local T = TYPES[c.type]
    if T.gauge then
      local text, color
      local net = c.net and networks[c.net]
      if T.gauge == "speed" then
        text = string.format("%d RPM", floor(abs(c.speed) + 0.5))
        color = abs(c.speed) >= 64 and "aqua" or (abs(c.speed) > 0 and "green" or "gray")
      else
        local cap, imp = net and net.capacity or 0, net and net.impact or 0
        text = string.format("%d / %d SU", floor(imp + 0.5), floor(cap + 0.5))
        color = (net and net.overstressed) and "red" or "gold"
      end
      if c.lastText ~= text then
        c.lastText = text
        cmd(string.format('data merge entity @e[tag=c%dt,limit=1] {text:{text:"%s",color:"%s"}}', c.id, text, color))
      end
    end
  end
end

-- Für andere Mods (z. B. Handy/Laptop aus dem MC-Device-Port)
local function emitStats()
  local em = lib("emit")
  if type(em) ~= "function" then return end
  local nets, count = {}, 0
  for _ in pairs(comps) do count = count + 1 end
  for id, n in pairs(networks) do
    nets[#nets + 1] = { id = id, size = n.size, capacity = n.capacity, impact = n.impact,
      overstressed = n.overstressed, conflict = n.conflict, running = n.running }
  end
  pcall(em, "create_zeus:stats", { networks = nets, count = count })
end

---------------------------------------------------------------------------
-- Platzieren / Entfernen
---------------------------------------------------------------------------
local function playerBlockPos()
  local ok, x, y, z = call(player, "blockPos")
  if ok and type(x) == "number" then return floor(x), floor(y), floor(z) end
  if ok and type(x) == "table" then return floor(x.x or x[1]), floor(x.y or x[2]), floor(x.z or x[3]) end
  local ok2, px, py, pz = call(player, "pos")
  if ok2 and type(px) == "number" then return floor(px), floor(py), floor(pz) end
  return nil
end

local function lookFacing()
  local okp, pitch = call(player, "pitch")
  if okp and type(pitch) == "number" then
    if pitch > 55 then return "down" end
    if pitch < -55 then return "up" end
  end
  local okf, f = call(player, "facing")
  if okf then
    local n = normFacing(f)
    if n then return n end
  end
  local oky, yaw = call(player, "yaw")
  if oky and type(yaw) == "number" then
    local d = floor(((yaw % 360) + 45) / 90) % 4
    return ({ "south", "west", "north", "east" })[d + 1]
  end
  return "north"
end

local function horizontalFacing()
  local f = lookFacing()
  if f == "up" or f == "down" then
    local oky, yaw = call(player, "yaw")
    if oky and type(yaw) == "number" then
      local d = floor(((yaw % 360) + 45) / 90) % 4
      return ({ "south", "west", "north", "east" })[d + 1]
    end
    return "north"
  end
  return f
end

-- Normalisiert player.lookingAt() auf {x,y,z,face,id} oder nil
local function lookTarget()
  local res = table.pack(call(player, "lookingAt"))
  if not res[1] then return nil end
  local a = res[2]
  if a == nil or a == false then return nil end
  local t = {}
  if type(a) == "table" or type(a) == "userdata" then
    local kind = field(a, "type") or field(a, "kind")
    if kind and kind ~= "block" then return nil end
    local pos = field(a, "pos") or field(a, "blockPos") or field(a, "block_pos")
    local function num(k, i)
      local v = field(a, k)
      if v == nil and pos then v = field(pos, k) or field(pos, i) end
      if v == nil then v = field(a, i) end
      return tonumber(v)
    end
    t.x, t.y, t.z = num("x", 1), num("y", 2), num("z", 3)
    t.face = normFacing(field(a, "face") or field(a, "side") or field(a, "direction") or field(a, "facing"))
    local id = field(a, "block") or field(a, "id") or field(a, "name")
    t.id = type(id) == "string" and id or nil
  elseif type(a) == "number" then
    t.x, t.y, t.z = a, res[3], res[4]
    t.face = normFacing(res[5])
    if type(res[6]) == "string" then t.id = res[6] end
  else
    return nil
  end
  if type(t.x) ~= "number" or type(t.y) ~= "number" or type(t.z) ~= "number" then return nil end
  t.x, t.y, t.z = floor(t.x), floor(t.y), floor(t.z)
  if not t.face then
    -- Seite zum Spieler hin schätzen
    local ok, ex, ey, ez = call(player, "eyePos")
    if not (ok and type(ex) == "number") then ok, ex, ey, ez = call(player, "pos") end
    if ok and type(ex) == "number" then
      local dx, dy, dz = ex - (t.x + 0.5), ey - (t.y + 0.5), ez - (t.z + 0.5)
      if abs(dx) >= abs(dy) and abs(dx) >= abs(dz) then t.face = dx > 0 and "east" or "west"
      elseif abs(dy) >= abs(dz) then t.face = dy > 0 and "up" or "down"
      else t.face = dz > 0 and "south" or "north" end
    end
  end
  return t
end

local function targetComponent()
  local t = lookTarget()
  if t then
    local c = at(t.x, t.y, t.z)
    if c then return c end
  end
  -- Ersatz: nächstes Bauteil direkt vor dem Spieler
  local x, y, z = playerBlockPos()
  if not x then return nil end
  local f = FACINGS[lookFacing()]
  for dist = 1, 3 do
    for dy = 0, 1 do
      local c = at(x + f[1] * dist, y + dy + f[2] * dist, z + f[3] * dist)
      if c then return c end
    end
  end
  return nil
end

local function place(typeName, x, y, z, face)
  local T = TYPES[typeName]
  if not T then return false, "Unbekanntes Bauteil" end
  if not typeOn(typeName) then return false, "Addon nicht aktiv: B-Menü → Bestätigen" end
  if at(x, y, z) then return false, "Da steht schon ein Bauteil" end
  local c = { id = nextId, type = typeName, x = x, y = y, z = z, dim = dimension(), angle = 0, speed = 0, progress = 0, near = true,
    mode = setting("models") and "model" or "parts" }
  nextId = nextId + 1
  local look = lookFacing()
  if typeName == "propeller_bearing" or typeName == "windmill_bearing" then
    c.facing = face or "up"
  elseif T.directional then
    c.facing = look
  elseif T.belt then
    c.facing = horizontalFacing()
  elseif T.horizontal then
    local hf = horizontalFacing()
    c.axis = (FACINGS[hf][4] == "x") and "z" or "x"
  elseif T.gearbox then
    c.axis = "y"
  elseif T.millstone or T.static then
    c.axis = "y"
  else
    c.axis = face and FACINGS[face][4] or FACINGS[look][4]
    if MODELS[typeName].useFacing then c.facing = face or look end
  end
  if T.source and (T.source.creative or T.source.electric) then c.rpm = T.source.rpm end
  -- Zahnräder um einen halben Zahn versetzen, damit sie sichtbar ineinandergreifen (wie in Create)
  local teeth = MODELS[typeName].teeth
  if teeth and c.axis then
    local p = PERP[c.axis]
    local sum = ({ x = x, y = y, z = z })[p[1]] + ({ x = x, y = y, z = z })[p[2]]
    c.angle = (sum % 2 == 1) and (180 / teeth) or 0
    c.baseAngle = c.angle
  end
  comps[key3(x, y, z)] = c
  byId[c.id] = c
  buildComponent(c)
  dirty, solveNeeded = true, true
  return true, c
end

local function remove(c)
  unbuildComponent(c)
  comps[key3(c.x, c.y, c.z)] = nil
  byId[c.id] = nil
  dirty, solveNeeded = true, true
end

local function placeSelected()
  local t = lookTarget()
  local x, y, z, face
  if t and t.face then
    local f = FACINGS[t.face]
    x, y, z, face = t.x + f[1], t.y + f[2], t.z + f[3], t.face
  else
    local px, py, pz = playerBlockPos()
    if not px then say("Kein Spieler gefunden.") return end
    local f = FACINGS[horizontalFacing()]
    x, y, z = px + f[1], py, pz + f[3]
  end
  local ok, res = place(selected, x, y, z, face)
  if ok then
    toast(TYPES[selected].name .. " gesetzt")
  else
    say("§c" .. tostring(res))
  end
end

local function cycleAxis(c)
  local T = TYPES[c.type]
  unbuildComponent(c, true)
  if T.directional then
    local i = 1
    for k, n in ipairs(FACING_LIST) do if n == c.facing then i = k end end
    c.facing = FACING_LIST[i % #FACING_LIST + 1]
  elseif T.belt then
    local order = { "north", "east", "south", "west" }
    local i = 1
    for k, n in ipairs(order) do if n == c.facing then i = k end end
    c.facing = order[i % 4 + 1]
  elseif T.horizontal then
    c.axis = c.axis == "x" and "z" or "x"
  elseif not T.millstone then
    c.axis = ({ x = "y", y = "z", z = "x" })[c.axis or "y"]
  end
  if T.carrierAxis then cmd(string.format("setblock %d %d %d %s", c.x, c.y, c.z, carrierBlock(c))) end
  summonParts(c)
  c.lastText = nil
  dirty, solveNeeded = true, true
end

---------------------------------------------------------------------------
-- Maschinen
---------------------------------------------------------------------------
local function convertItems(px, py, pz, radius, recipes, condition)
  for _, r in ipairs(recipes) do
    cmd(string.format(
      'execute %spositioned %.2f %.2f %.2f as @e[type=item,distance=..%.1f,nbt={Item:{id:"minecraft:%s"}}] run data modify entity @s Item.id set value "minecraft:%s"',
      condition or "", px, py, pz, radius, r[1], r[2]))
  end
end

local function processDrill(c)
  local f = FACINGS[c.facing]
  local tx, ty, tz = c.x + f[1], c.y + f[2], c.z + f[3]
  if at(tx, ty, tz) then return end
  cmd(string.format(
    "execute unless block %d %d %d #minecraft:air unless block %d %d %d minecraft:bedrock unless block %d %d %d minecraft:water unless block %d %d %d minecraft:lava run setblock %d %d %d air destroy",
    tx, ty, tz, tx, ty, tz, tx, ty, tz, tx, ty, tz, tx, ty, tz))
end

local function fanRange(c) return mmax(2, mmin(20, floor(abs(c.speed) / 12 + 0.5))) end

local function fanBox(c, from, to)
  local f = FACINGS[c.facing]
  local x0, y0, z0 = c.x + f[1] * from, c.y + f[2] * from, c.z + f[3] * from
  local len = to - from
  local dx, dy, dz = f[1] * len, f[2] * len, f[3] * len
  return x0, y0, z0, dx, dy, dz
end

local function pushFan(c)
  local f = FACINGS[c.facing]
  local range = fanRange(c)
  local dir = c.speed > 0 and 1 or -1
  local v = mmin(0.6, abs(c.speed) / 256 * 0.5 + 0.08) * dir
  local x0, y0, z0, dx, dy, dz = fanBox(c, 1, range)
  cmd(string.format(
    "execute positioned %d %d %d as @e[tag=!cz,type=!player,dx=%d,dy=%d,dz=%d] run data merge entity @s {Motion:[%.3fd,%.3fd,%.3fd]}",
    x0, y0, z0, dx, dy, dz, f[1] * v, f[2] * v + (f[2] == 0 and 0.02 or 0), f[3] * v))
  -- Spieler im Luftstrom
  local ok, px, py, pz = call(player, "pos")
  if ok and type(px) == "number" then
    local minx, maxx = mmin(x0, x0 + dx), mmax(x0, x0 + dx) + 1
    local miny, maxy = mmin(y0, y0 + dy) - 1, mmax(y0, y0 + dy) + 1
    local minz, maxz = mmin(z0, z0 + dz), mmax(z0, z0 + dz) + 1
    if px >= minx and px <= maxx and py >= miny and py <= maxy and pz >= minz and pz <= maxz then
      local okv, vx, vy, vz = call(player, "velocity")
      if okv and type(vx) == "number" then
        call(player, "setVelocity", vx + f[1] * v * 0.35, vy + f[2] * v * 0.35, vz + f[3] * v * 0.35)
      end
    end
  end
end

local function processFan(c)
  local f = FACINGS[c.facing]
  local cx, cy, cz = c.x + f[1], c.y + f[2], c.z + f[3]
  local range = fanRange(c)
  local mid = (range + 2) / 2
  local px, py, pz = c.x + 0.5 + f[1] * mid, c.y + 0.5 + f[2] * mid, c.z + 0.5 + f[3] * mid
  local rad = range / 2 + 0.6
  local cat = string.format("%d %d %d", cx, cy, cz)
  convertItems(px, py, pz, rad, SMELT, "if block " .. cat .. " minecraft:lava ")
  convertItems(px, py, pz, rad, SMELT, "if block " .. cat .. " minecraft:fire ")
  convertItems(px, py, pz, rad, WASH, "if block " .. cat .. " minecraft:water ")
  convertItems(px, py, pz, rad, HAUNT, "if block " .. cat .. " minecraft:soul_fire ")
  if addonOn("dragons_plus") then
    convertItems(px, py, pz, rad, FREEZE, "if block " .. cat .. " minecraft:powder_snow ")
    convertItems(px, py, pz, rad, ENDING, "if block " .. cat .. " minecraft:dragon_head ")
  end
end

local function setPressHead(c, down)
  local y = down and (c.mode == "model" and -0.9 or -0.75) or 0
  cmd(string.format(
    "data merge entity @e[tag=c%dh,limit=1] {start_interpolation:0,interpolation_duration:4,transformation:{translation:[0f,%s,0f]}}",
    c.id, f3(y)))
end

local processSaw, processCrusher

local function fireCannon(c)
  local f = FACINGS[c.facing]
  local x, y, z = c.x + 0.5 + f[1] * 1.3, c.y + 0.5 + f[2] * 1.3, c.z + 0.5 + f[3] * 1.3
  local v = mmin(3.0, 1.0 + abs(c.speed) / 128)
  local up = (f[2] == 0) and 0.15 or 0
  cmd(string.format("summon tnt %.2f %.2f %.2f {fuse:80,Motion:[%.3fd,%.3fd,%.3fd]}", x, y, z, f[1] * v, f[2] * v + up, f[3] * v))
  cmd(string.format("playsound minecraft:entity.generic.explode block @a %.1f %.1f %.1f 0.6 1.8", x, y, z))
end

local function liftPropeller(c)
  local f = FACINGS[c.facing]
  local range = mmax(3, mmin(16, floor(abs(c.speed) / 16 + 0.5)))
  local v = mmin(0.6, abs(c.speed) / 256 * 0.5 + 0.12) * (c.speed > 0 and 1 or -1)
  local x0, y0, z0, dx, dy, dz = fanBox(c, 1, range)
  -- Säule 3x3 quer zur Blickrichtung
  local wx, wy, wz = (f[1] == 0) and 1 or 0, (f[2] == 0) and 1 or 0, (f[3] == 0) and 1 or 0
  x0, y0, z0 = mmin(x0, x0 + dx) - wx, mmin(y0, y0 + dy) - wy, mmin(z0, z0 + dz) - wz
  dx, dy, dz = abs(dx) + 2 * wx, abs(dy) + 2 * wy, abs(dz) + 2 * wz
  cmd(string.format(
    "execute positioned %d %d %d as @e[tag=!cz,type=!player,dx=%d,dy=%d,dz=%d] run data merge entity @s {Motion:[%.3fd,%.3fd,%.3fd]}",
    x0, y0, z0, dx, dy, dz, f[1] * v, f[2] * v, f[3] * v))
  local ok, px, py, pz = call(player, "pos")
  if ok and type(px) == "number" and px >= x0 and px <= x0 + dx + 1 and py >= y0 - 1 and py <= y0 + dy + 1 and pz >= z0 and pz <= z0 + dz + 1 then
    local okv, vx, vy, vz = call(player, "velocity")
    local okS, sneaking = call(player, "isSneaking")
    if okv and type(vx) == "number" and not (okS and sneaking) then
      if f[2] ~= 0 then call(player, "setVelocity", vx, f[2] * v, vz)
      else call(player, "setVelocity", vx + f[1] * v * 0.3, vy, vz + f[3] * v * 0.3) end
    end
  end
end

-- Strom: Elektromotoren verbrauchen FE, gehen aus, wenn nichts mehr da ist
local function isDay()
  local ok, t = call(world, "timeOfDay")
  if not ok or type(t) ~= "number" then return true end
  if t >= 0 and t <= 1 and floor(t) ~= t then t = t * 24000 end
  t = t % 24000
  return t < 12500 or t > 23500
end

-- Ein Item aus einem Stapel verarbeiten: Ergebnis daneben erzeugen, Stapel um 1 verkleinern
local function processOne(px, py, pz, radius, input, output, count)
  local sel = string.format('@e[type=item,distance=..%.1f,nbt={Item:{id:"minecraft:%s"}},limit=1]', radius, input)
  cmd(string.format('execute positioned %.2f %.2f %.2f as %s at @s run summon item ~ ~ ~ {Item:{id:"minecraft:%s",count:%d}}',
    px, py, pz, sel, output, count))
  cmd(string.format('execute positioned %.2f %.2f %.2f as %s store result entity @s Item.count int 1 run data get entity @s Item.count 0.999',
    px, py, pz, sel))
end

processSaw = function(c)
  local f = FACINGS[c.facing]
  local tx, ty, tz = c.x + f[1], c.y + f[2], c.z + f[3]
  -- Bäume fällen: Stamm vor der Säge und alles darüber
  for dy = 0, 12 do
    cmd(string.format("execute if block %d %d %d #minecraft:logs run setblock %d %d %d air destroy", tx, ty + dy, tz, tx, ty + dy, tz))
  end
  -- Stämme, die vor der Säge liegen, zu je 6 Brettern sägen
  for _, r in ipairs(SAW) do processOne(tx + 0.5, ty + 0.3, tz + 0.5, 0.9, r[1], r[2], 6) end
end

processCrusher = function(c)
  local p = PERP[c.axis]
  for _, ax in ipairs(p) do
    if ax ~= "y" then
      local v = AXIS_VEC[ax]
      for dist = 1, 2 do
        local n = at(c.x + v[1] * dist, c.y, c.z + v[3] * dist)
        if n and n.type == "crushing_wheel" and n.id > c.id and n.axis == c.axis and (n.speed or 0) == -(c.speed or 0) then
          -- Mitte zwischen beiden Rädern: Items fallen hinein (mit Lücke) oder liegen oben drauf
          local mx, mz = c.x + 0.5 + v[1] * dist / 2, c.z + 0.5 + v[3] * dist / 2
          local my = dist == 2 and c.y + 0.5 or c.y + 1.2
          for _, r in ipairs(CRUSH) do processOne(mx, my, mz, 0.9, r[1], r[2], r[3]) end
        end
      end
    end
  end
end

local function updateEnergy()
  local akkus, solar = 0, 0
  for _, c in pairs(comps) do
    if c.near and typeOn(c.type) then
      if c.type == "battery" then akkus = akkus + 1 elseif c.type == "solar_panel" then solar = solar + 1 end
    end
  end
  ENERGY_MAX = 200000 + akkus * 100000
  if solar > 0 and isDay() then energy = mmin(ENERGY_MAX, energy + solar * 40) end
  for _, c in pairs(comps) do
    if c.type == "electric_motor" and c.near and typeOn(c.type) then
      local cost = abs(c.rpm or 128) * 4
      if c.powered then
        if energy >= cost then energy = energy - cost
        else c.powered = false; solveNeeded = true end
      elseif energy >= cost * 20 then
        c.powered = true; solveNeeded = true
      end
    end
  end
end

local function processMachines()
  for _, c in pairs(comps) do
    local T = TYPES[c.type]
    if c.near and c.speed ~= 0 and (T.impact or T.belt) and typeOn(c.type) then
      local s = abs(c.speed)
      if c.type == "saw" then
        c.progress = c.progress + s
        if c.progress >= 1600 then c.progress = 0; processSaw(c) end
      elseif c.type == "crushing_wheel" then
        c.progress = c.progress + s
        if c.progress >= 1200 then c.progress = 0; processCrusher(c) end
      elseif c.type == "enchanter" then
        c.progress = c.progress + s
        if c.progress >= 3600 then
          c.progress = 0
          local ench = ENCHANTS[math.random(#ENCHANTS)]
          cmd(string.format(
            'execute positioned %.1f %.1f %.1f as @e[type=item,distance=..0.9,nbt={Item:{id:"minecraft:book"}}] run data merge entity @s {Item:{id:"minecraft:enchanted_book",components:{"minecraft:stored_enchantments":{"minecraft:%s":1}}}}',
            c.x + 0.5, c.y + 1.2, c.z + 0.5, ench))
        end
      elseif c.type == "xp_drain" then
        if tickNo % 10 == 0 then
          local r = mmax(4, mmin(16, floor(s / 16) + 4))
          cmd(string.format("execute positioned %.1f %.1f %.1f run tp @e[type=experience_orb,distance=..%d] @p",
            c.x + 0.5, c.y + 0.5, c.z + 0.5, r))
        end
      elseif c.type == "cannon" then
        c.progress = c.progress + s
        if c.progress >= 4800 then c.progress = 0; fireCannon(c) end
      elseif c.type == "alternator" then
        energy = mmin(ENERGY_MAX, energy + s * 16)
      elseif c.type == "propeller_bearing" then
        if tickNo % 2 == 0 then liftPropeller(c) end
      elseif c.type == "drill" then
        c.progress = c.progress + s
        if c.progress >= 1200 then c.progress = 0; processDrill(c) end
      elseif c.type == "fan" then
        if tickNo % 2 == 0 then pushFan(c) end
        c.progress = c.progress + s
        if c.progress >= 3000 then c.progress = 0; processFan(c) end
      elseif c.type == "millstone" then
        c.progress = c.progress + s
        if c.progress >= 2400 then
          c.progress = 0
          convertItems(c.x + 0.5, c.y + 1.2, c.z + 0.5, 0.9, MILL)
        end
      elseif c.type == "press" then
        c.progress = c.progress + s
        if c.progress >= 2400 then
          c.progress = 0
          setPressHead(c, true)
          c.pressUp = tickNo + 6
          convertItems(c.x + 0.5, c.y - 0.8, c.z + 0.5, 0.8, PRESS)
        end
        if c.pressUp and tickNo >= c.pressUp then c.pressUp = nil; setPressHead(c, false) end
      end
    end
  end
  -- Förderbänder: eine Befehlszeile pro zusammenhängendem Stück
  local done = {}
  for _, c in pairs(comps) do
    if TYPES[c.type].belt and c.near and c.speed ~= 0 and not done[c] then
      local f = FACINGS[c.facing]
      -- Anfang der Reihe suchen
      local sx, sz = c.x, c.z
      while true do
        local b = at(sx - f[1], c.y, sz - f[3])
        if not b or not TYPES[b.type].belt or b.facing ~= c.facing then break end
        sx, sz = sx - f[1], sz - f[3]
      end
      local len = 0
      while true do
        local b = at(sx + f[1] * len, c.y, sz + f[3] * len)
        if not b or not TYPES[b.type].belt or b.facing ~= c.facing then break end
        done[b] = true
        len = len + 1
      end
      local v = mmin(0.5, c.speed / 256 * 0.4 + 0.04)
      cmd(string.format(
        "execute positioned %d %d %d as @e[tag=!cz,type=!player,dx=%d,dy=0,dz=%d] run data merge entity @s {Motion:[%.3fd,0.0d,%.3fd]}",
        sx, c.y, sz, f[1] * (len - 1), f[3] * (len - 1), f[1] * v, f[3] * v))
      local ok, px, py, pz = call(player, "pos")
      if ok and type(px) == "number" then
        local bx, by, bz = floor(px), floor(py + 0.01), floor(pz)
        local onBelt = at(bx, by, bz)
        if onBelt and done[onBelt] then
          local okv, vx, vy, vz = call(player, "velocity")
          if okv and type(vx) == "number" then
            call(player, "setVelocity", vx * 0.5 + f[1] * v, vy, vz * 0.5 + f[3] * v)
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------
local function animate()
  if not setting("animate") then return end
  for _, c in pairs(comps) do
    local T = TYPES[c.type]
    local spins = (c.mode == "model") and MODELS[c.type].spin ~= nil or (c.mode ~= "model" and #T.parts > 0)
    if spins and c.near and c.speed ~= 0 and typeOn(c.type) then
      local degPerTick = c.speed * 0.3
      c.angle = ((c.angle or 0) + degPerTick) % 360
      local interval = mmax(1, mmin(10, floor(150 / mmax(1, abs(degPerTick)))))
      if (tickNo + c.id) % interval == 0 then
        cmd(string.format(
          "execute as @e[tag=c%d] run data merge entity @s {start_interpolation:0,interpolation_duration:%d,transformation:{left_rotation:%s}}",
          c.id, interval, farr(spinQuat(c))))
      end
    end
  end
end

local function countSails()
  for _, c in pairs(comps) do
    if c.type == "windmill_bearing" then
      local n = 0
      for _, o in pairs(comps) do
        if o.type == "sail" and o.dim == c.dim and abs(o.x - c.x) <= 5 and abs(o.y - c.y) <= 5 and abs(o.z - c.z) <= 5 then n = n + 1 end
      end
      if n ~= c.sails then c.sails = n; solveNeeded = true end
    end
  end
end

local function updateNear()
  local ok, px, py, pz = call(player, "pos")
  local dim = dimension()
  for _, c in pairs(comps) do
    if ok and type(px) == "number" then
      local dx, dy, dz = c.x - px, c.y - py, c.z - pz
      c.near = c.dim == dim and (dx * dx + dy * dy + dz * dz) < 64 * 64
    else
      c.near = false
    end
  end
end

---------------------------------------------------------------------------
-- Menüs
---------------------------------------------------------------------------
local openMenu
local function openMotorMenu(c)
  if not ui then return end
  local ok, scr = pcall(ui.screen, {
    title = TYPES[c.type].name,
    init = function(screen)
      screen:label({ text = string.format("Drehzahl: %d RPM%s", c.rpm or 64, c.rev and " (rückwärts)" or ""), centered = true })
      for _, step in ipairs({ -32, -8, -1, 1, 8, 32 }) do
        screen:button({ text = (step > 0 and "+" or "") .. step .. " RPM", onClick = function()
          c.rpm = mmax(1, mmin(256, (c.rpm or 64) + step))
          dirty, solveNeeded = true, true
          screen:rebuild()
        end })
      end
      screen:button({ text = "Richtung umkehren", onClick = function()
        c.rev = not c.rev
        dirty, solveNeeded = true, true
        screen:rebuild()
      end })
      screen:button({ text = "Fertig", onClick = function() screen:close() end })
    end,
  })
  if ok then call(ui, "open", scr) end
end

---------------------------------------------------------------------------
-- Addons: Zustand, Installation
---------------------------------------------------------------------------
local function saveAddons()
  if storage then call(storage, "set", "addons", json.encode(addonState)) end
end
local function loadAddons()
  addonState = { installed = {}, enabled = {} }
  if not storage then return end
  local ok, raw = call(storage, "get", "addons")
  if ok and type(raw) == "string" then
    local ok2, d = pcall(json.decode, raw)
    if ok2 and type(d) == "table" then
      addonState.installed = type(d.installed) == "table" and d.installed or {}
      addonState.enabled = type(d.enabled) == "table" and d.enabled or {}
    end
  end
end

local function missingDeps(id, out, seen)
  out, seen = out or {}, seen or {}
  for _, d in ipairs(ADDON_BY_ID[id].deps or {}) do
    if d ~= "create" and not seen[d] then
      seen[d] = true
      missingDeps(d, out, seen)
      if not addonState.installed[d] then out[#out + 1] = d end
    end
  end
  return out
end

local install = nil   -- { queue, idx, progress, phase, wait, speed, stall }
pcall(math.randomseed, floor((os.clock() or 0) * 1000003) % 2147483647)

-- Tempo pro Phase zufällig: schnell, normal, langsam oder sehr langsam (Prozent pro Tick)
local function pickSpeed()
  local r = math.random()
  if r < 0.30 then return 1.4 end
  if r < 0.65 then return 0.6 end
  if r < 0.88 then return 0.25 end
  return 0.1
end

local function stageText()
  if not install then return "" end
  local a = ADDON_BY_ID[install.queue[install.idx]]
  if install.phase == "connect" then return "Verbinde mit Server …" end
  if install.stall > 0 then
    return install.phase == "download" and "Warte auf Antwort vom Server …" or "Bitte warten …"
  end
  if install.phase == "download" then
    return string.format("Lade herunter … %d / %d KB", floor(a.size * install.progress / 70), a.size)
  end
  if install.progress < 80 then return "Entpacke Dateien …" end
  if install.progress < 92 then return "Prüfe Abhängigkeiten …" end
  return "Aktiviere …"
end

local function bar(pr, width)
  local n = floor(mmax(0, mmin(100, pr)) / 100 * width + 0.5)
  return string.rep("█", n) .. string.rep("░", width - n)
end

local function beginAddon()
  install.progress = 0
  install.phase = "connect"
  install.wait = 80          -- 4 Sekunden bei 0 %
  install.stall = 0
end

local function startInstall(id)
  if install then toast("Es läuft schon eine Installation.") return end
  local q = missingDeps(id)
  if not addonState.installed[id] then q[#q + 1] = id end
  if #q == 0 then return end
  install = { queue = q, idx = 1 }
  beginAddon()
  toast("Installation gestartet: " .. ADDON_BY_ID[id].name)
end

local function finishAddon(a)
  addonState.installed[a.id] = true
  addonState.enabled[a.id] = true
  saveAddons()
  toast(a.name .. " installiert")
  say("§a" .. a.name .. " v" .. a.version .. " installiert und aktiviert.")
  solveNeeded = true
  install.idx = install.idx + 1
  if install.idx > #install.queue then install = nil else beginAddon() end
end

local function stepInstall()
  if not install then return end
  local a = ADDON_BY_ID[install.queue[install.idx]]
  if install.phase == "connect" then
    install.wait = install.wait - 1
    if install.wait <= 0 then install.phase = "download"; install.speed = pickSpeed() end
    return
  end
  if install.stall > 0 then install.stall = install.stall - 1 return end
  -- ab und zu hängt es kurz (1–4 Sekunden) und läuft dann weiter
  if math.random() < 1 / 160 then install.stall = math.random(20, 80) return end
  -- das Tempo kann sich unterwegs ändern
  if math.random() < 1 / 200 then install.speed = pickSpeed() end
  local sizeFactor = mmax(0.6, mmin(1.4, 45 / a.size))
  local cap = install.phase == "download" and 70 or 100
  install.progress = mmin(cap, install.progress + install.speed * sizeFactor * (0.4 + math.random() * 1.2))
  if install.phase == "download" and install.progress >= 70 then
    install.phase = "install"
    install.speed = pickSpeed()
    install.stall = math.random(5, 30)
  elseif install.phase == "install" and install.progress >= 100 then
    finishAddon(a)
  end
end

local function dependents(id)
  local out = {}
  for _, a in ipairs(ADDONS) do
    for _, d in ipairs(a.deps) do
      if d == id and addonState.enabled[a.id] then out[#out + 1] = a.id end
    end
  end
  return out
end

local function toggleAddon(id)
  if not addonState.installed[id] then return end
  local on = not addonState.enabled[id]
  if on then
    for _, d in ipairs(missingDeps(id)) do
      toast("Fehlt: " .. ADDON_BY_ID[d].name)
      return
    end
    for _, d in ipairs(ADDON_BY_ID[id].deps) do if d ~= "create" then addonState.enabled[d] = true end end
  else
    for _, d in ipairs(dependents(id)) do addonState.enabled[d] = false end
  end
  addonState.enabled[id] = on
  saveAddons()
  solveNeeded = true
  toast(ADDON_BY_ID[id].name .. (on and " aktiviert" or " deaktiviert"))
end

local function uninstallAddon(id)
  for _, d in ipairs(dependents(id)) do addonState.enabled[d] = false end
  addonState.installed[id] = nil
  addonState.enabled[id] = nil
  saveAddons()
  solveNeeded = true
  toast(ADDON_BY_ID[id].name .. " deinstalliert")
end

---------------------------------------------------------------------------
-- Inventar-Items
---------------------------------------------------------------------------
local function partLabel(part) return part == "wrench" and "Schraubenschlüssel" or TYPES[part].name end

local function giveCmd(k, count)
  local glint = k[2] == "nether_star" and ",minecraft:enchantment_glint_override=false" or ""
  return string.format('give @s minecraft:%s[minecraft:item_model="%s",minecraft:item_name="%s"%s] %d',
    k[2], k[3], partLabel(k[1]), glint, count or k[4])
end

local function giveKit()
  local n = 0
  for _, k in ipairs(KIT) do
    if k[1] == "wrench" or typeOn(k[1]) then cmd(giveCmd(k)); n = n + 1 end
  end
  toast(n .. " Create-Teile ins Inventar gelegt")
end

local function heldPart()
  local ok, h = call(player, "heldItem")
  if not ok or h == nil then return nil end
  local id, name
  if type(h) == "string" then id = h
  else
    id = field(h, "id") or field(h, "item") or field(h, "type")
    name = field(h, "name") or field(h, "displayName") or field(h, "customName") or field(h, "label")
  end
  if type(name) == "string" then
    local p = PART_BY_NAME[(name:gsub("§.", "")):lower()]
    if p then return p end
  end
  if type(id) == "string" then return PART_BY_ITEM[(id:gsub("^minecraft:", ""))] end
  return nil
end

---------------------------------------------------------------------------
-- B-Menü
---------------------------------------------------------------------------
local Menu = { scr = nil, tab = "teile", detail = nil, reveal = 0, total = 0, page = 1, pages = 1 }
local TABS = { { "teile", "Bauteile" }, { "entdecken", "Entdecken" }, { "abh", "Abhängigkeiten" }, { "bestaetigen", "Bestätigen" } }
local guiHeight = nil   -- vom HUD gemessen, damit das Menü auf den Bildschirm passt

-- Wie viele Zeilen (Knöpfe/Texte) passen untereinander auf den Bildschirm?
local function menuRows()
  local h = guiHeight or 240
  return mmax(5, mmin(14, floor((h - 46) / 24)))
end

-- Text auf mehrere kurze Zeilen verteilen (Labels werden nicht umgebrochen)
local function wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line > 0 and #line + 1 + #word > width then lines[#lines + 1] = line; line = word
    else line = (#line > 0) and (line .. " " .. word) or word end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

local function tabIndex()
  for i, t in ipairs(TABS) do if t[1] == Menu.tab then return i end end
  return 1
end

local function setTab(i)
  Menu.tab = TABS[((i - 1) % #TABS) + 1][1]
  Menu.detail = nil
  Menu.page = 1
end

-- Kopfzeilen (immer oben) und Liste (seitenweise)
local function menuContent()
  local head, list = {}, {}
  local function L(dst, t) dst[#dst + 1] = { "label", t } end
  local function B(dst, t, fn) dst[#dst + 1] = { "button", t, fn } end

  if Menu.detail then
    local a = ADDON_BY_ID[Menu.detail]
    B(head, "◂ Zurück zu Entdecken", function() Menu.detail = nil; Menu.refresh(true) end)
    if install then
      local cur = ADDON_BY_ID[install.queue[install.idx]]
      L(head, string.format("%s %s %d%%", cur.name, bar(install.progress, 12), floor(install.progress)))
      L(head, stageText() .. (#install.queue > 1 and string.format("  (%d/%d)", install.idx, #install.queue) or ""))
    end
    if addonState.installed[a.id] then
      B(head, addonState.enabled[a.id] and "✔ AN – klicken zum Ausschalten" or "✖ AUS – klicken zum Einschalten", function()
        toggleAddon(a.id); Menu.refresh(false)
      end)
    elseif not install then
      local miss = missingDeps(a.id)
      B(head, #miss > 0 and ("↓ Installieren (+" .. #miss .. " Abhängigkeit)") or "↓ Installieren", function()
        startInstall(a.id); Menu.refresh(false)
      end)
    end
    L(list, a.name .. "  v" .. a.version)
    for i, d in ipairs(a.deps) do
      L(list, (i == 1 and "Braucht: " or "              ") .. ADDON_BY_ID[d].name ..
        ((d == "create" or addonState.installed[d]) and " ✔" or " ✖"))
    end
    for _, line in ipairs(wrap(a.desc, 44)) do L(list, line) end
    L(list, "Vorbild: " .. a.inspired .. " · " .. a.size .. " KB")
    if addonState.installed[a.id] then
      B(list, "Deinstallieren", function() uninstallAddon(a.id); Menu.refresh(false) end)
    end
    return head, list
  end

  -- Tab-Leiste oben: ein Knopf, Klick = nächster Tab (Tasten 1–4 springen direkt)
  local ti = tabIndex()
  B(head, "Tab: " .. TABS[ti][2] .. "  ▸", function() setTab(ti + 1); Menu.refresh(true) end)
  if install then
    local cur = ADDON_BY_ID[install.queue[install.idx]]
    L(head, string.format("%s %s %d%%", cur.name, bar(install.progress, 12), floor(install.progress)))
    L(head, stageText() .. (#install.queue > 1 and string.format("  (%d/%d)", install.idx, #install.queue) or ""))
  end

  if Menu.tab == "teile" then
    B(list, "★ Alle Teile geben", function() giveKit() end)
    for _, k in ipairs(KIT) do
      if k[1] == "wrench" or typeOn(k[1]) then
        B(list, partLabel(k[1]) .. "  ×" .. k[4], function() cmd(giveCmd(k)); toast(partLabel(k[1]) .. " erhalten") end)
      end
    end
  elseif Menu.tab == "entdecken" then
    for _, a in ipairs(ADDONS) do
      local st = addonState.installed[a.id] and (addonState.enabled[a.id] and "✔" or "○") or "↓"
      B(list, st .. " " .. a.name, function() Menu.detail = a.id; Menu.page = 1; Menu.refresh(true) end)
    end
  elseif Menu.tab == "abh" then
    for _, a in ipairs(ADDONS) do
      L(list, a.name .. ":")
      for _, d in ipairs(a.deps) do
        L(list, "   braucht " .. ADDON_BY_ID[d].name .. ((d == "create" or addonState.installed[d]) and " ✔" or " ✖"))
      end
    end
  elseif Menu.tab == "bestaetigen" then
    B(list, "✔ Create (Port) v" .. MOD_VERSION, function() toast("Create (Port) ist immer aktiv") end)
    local any = false
    for _, a in ipairs(ADDONS) do
      if addonState.installed[a.id] then
        any = true
        B(list, (addonState.enabled[a.id] and "✔ AN  " or "✖ AUS  ") .. a.name, function()
          toggleAddon(a.id)
          Menu.refresh(false)
        end)
      end
    end
    if not any then L(list, "Noch keine Addons – Tab Entdecken") end
  end
  return head, list
end

-- Sichtbare Einträge: Kopf + Seitenknopf + eine Seite der Liste
local function menuItems()
  local head, list = menuContent()
  local items = {}
  for _, it in ipairs(head) do items[#items + 1] = it end
  local per = mmax(2, menuRows() - #head)
  if #list > per then per = per - 1 end   -- Platz für den Seitenknopf
  Menu.pages = mmax(1, math.ceil(#list / per))
  if Menu.page > Menu.pages then Menu.page = 1 end
  if Menu.pages > 1 then
    items[#items + 1] = { "button", string.format("Seite %d/%d  ▸", Menu.page, Menu.pages), function()
      Menu.page = Menu.page % Menu.pages + 1
      Menu.refresh(true)
    end }
  end
  local first = (Menu.page - 1) * per + 1
  for i = first, mmin(#list, first + per - 1) do items[#items + 1] = list[i] end
  return items
end

function Menu.build(s)
  Menu.scr = s
  local items = menuItems()
  Menu.total = #items
  for i, it in ipairs(items) do
    if i > Menu.reveal then break end
    if it[1] == "label" then pcall(s.label, s, { text = it[2], centered = true })
    else pcall(s.button, s, { text = it[2], onClick = it[3] }) end
  end
end

function Menu.refresh(animate)
  if animate then Menu.reveal = 0 else Menu.reveal = mmax(Menu.reveal, 999) end
  if Menu.scr then pcall(Menu.scr.rebuild, Menu.scr) end
end

-- Tastatur im Menü: 1–4 = Tab, ←/→ = Seite
local function menuKey(key)
  local raw = (type(key) == "table" or type(key) == "userdata") and (field(key, "key") or field(key, "name") or field(key, "code")) or key
  local k = tostring(raw):lower()
  local n = tonumber(k)
  -- GLFW-Tastencodes: 1-4 = 49-52, B = 66, rechts = 262, links = 263
  if n == 66 or k == "b" or k == "key.keyboard.b" then
    Menu.closedAt = tickNo
    Menu.close()
    return true
  end
  if n and n >= 49 and n <= 52 then n = n - 48 end
  if n == 262 then k = "right" elseif n == 263 then k = "left" end
  if n and n >= 1 and n <= #TABS then setTab(n); Menu.refresh(true) return true end
  if k == "right" or k == "arrowright" or k == "pagedown" then
    Menu.page = Menu.page % Menu.pages + 1; Menu.refresh(true) return true
  end
  if k == "left" or k == "arrowleft" or k == "pageup" then
    Menu.page = (Menu.page - 2) % Menu.pages + 1; Menu.refresh(true) return true
  end
  return false
end

function Menu.close()
  if Menu.scr then pcall(Menu.scr.close, Menu.scr) end
  Menu.scr = nil
end

function Menu.open(tab)
  if not ui then say("UI nicht verfügbar – nutze /create kit und /create setzen <teil>") return end
  if tab then Menu.tab = tab end
  Menu.detail = nil
  Menu.page = 1
  Menu.reveal = 0
  local ok, scr = pcall(ui.screen, {
    title = "Create  ·  Tasten 1–4: Tabs  ·  ← →: Seiten  ·  Esc: zu",
    closeOnEsc = true,
    onKey = function(key) return menuKey(key) end,
    init = function(s) Menu.build(s) end,
    onClose = function() Menu.scr = nil end,
  })
  if ok then call(ui, "open", scr) else say("Menü-Fehler: " .. tostring(scr)) end
end

-- Eingeblendet in Schritten (Animation) und live aktualisiert während einer Installation
function Menu.tick()
  if not Menu.scr then return end
  local okS, scr = call(game, "screen")
  if okS and scr == nil and tickNo > 2 then Menu.scr = nil return end
  local changed = false
  if Menu.reveal < Menu.total then Menu.reveal = Menu.reveal + 3; changed = true end
  if install and tickNo % 2 == 0 then changed = true end
  if Menu.wasInstalling and not install then changed = true end
  Menu.wasInstalling = install ~= nil
  if changed then pcall(Menu.scr.rebuild, Menu.scr) end
end

openMenu = function(tab) Menu.open(tab) end

---------------------------------------------------------------------------
-- Tasten
---------------------------------------------------------------------------
local function wrench()
  local c = targetComponent()
  if not c then say("Schau auf ein Create-Bauteil.") return end
  if c.type == "motor" or c.type == "electric_motor" then openMotorMenu(c) return end
  if TYPES[c.type].redstone then
    c.manualOn = not c.manualOn
    dirty, solveNeeded = true, true
    toast(TYPES[c.type].name .. (c.manualOn and ": geschaltet (wie mit Redstone)" or ": normal"))
    return
  end
  if c.type == "water_wheel" then
    c.rev = not c.rev
    dirty, solveNeeded = true, true
    toast("Wasserrad: Richtung umgekehrt")
    return
  end
  cycleAxis(c)
  toast(TYPES[c.type].name .. " gedreht")
end

local function pickUp(c)
  remove(c)
  for _, k in ipairs(KIT) do if k[1] == c.type then cmd(giveCmd(k, 1)) end end
  toast(TYPES[c.type].name .. " aufgehoben")
end

if keys then
  local function bind(spec) pcall(keys.bind, spec) end
  bind({ id = "menu", label = "Create: Menü (B = auf/zu)", default = "b", inScreens = true, onPress = function()
    if not active then return end
    if Menu.closedAt == tickNo then return end
    local okS, scr = call(game, "screen")
    local screenOpen = okS and scr ~= nil and scr ~= false
    if Menu.scr and screenOpen then Menu.close() return end
    if screenOpen then return end   -- Chat, Inventar usw.: nicht dazwischenfunken
    Menu.scr = nil
    openMenu()
  end })
  bind({ id = "place", label = "Create: Bauteil setzen", default = "r", onPress = function() if active then placeSelected() end end })
  bind({ id = "wrench", label = "Create: Schraubenschlüssel", default = "v", onPress = function() if active then wrench() end end })
  bind({ id = "remove", label = "Create: Bauteil abbauen", default = "x", onPress = function()
    if not active then return end
    local c = targetComponent()
    if c then remove(c); toast(TYPES[c.type].name .. " abgebaut") else say("Schau auf ein Create-Bauteil.") end
  end })
  bind({ id = "crank", label = "Create: Kurbeln (halten)", default = "g",
    onPress = function() crankHeld = true end, onRelease = function() crankHeld = false end })
end

local function updateCrank()
  local held = crankHeld
  if not held and keys then
    local ok, d = call(keys, "isDown", "g")
    held = ok and d == true
  end
  if not held then
    local ok, d = call(lib("mouse"), "isDown", "right")
    held = ok and d == true and heldPart() == nil
  end
  if not held then return end
  local c = targetComponent()
  if c and c.type == "crank" then
    local before = (c.crankUntil or -1) >= tickNo
    local okS, sneaking = call(player, "isSneaking")
    local dir = (okS and sneaking) and -1 or 1
    if not before or c.crankDir ~= dir then solveNeeded = true end
    c.crankDir = dir
    c.crankUntil = tickNo + 6
  end
end

---------------------------------------------------------------------------
-- HUD: Ingenieursbrille
---------------------------------------------------------------------------
local function argb(hex) return hex end
if hud then
  pcall(hud.add, "create_install", function(ctx)
    local hh = field(ctx, "height")
    if type(hh) == "number" and hh > 100 then guiHeight = hh end
    if not install then return end
    local w = field(ctx, "width") or 320
    local a = ADDON_BY_ID[install.queue[install.idx]]
    local bw, x = 182, floor(w / 2 - 91)
    pcall(ctx.rect, ctx, x - 2, 2, bw + 4, 22, 0xC0101018)
    pcall(ctx.rect, ctx, x, 14, bw, 6, 0xFF3A3A3A)
    pcall(ctx.rect, ctx, x, 14, floor(bw * mmin(100, install.progress) / 100), 6, 0xFFD6A04A)
    pcall(ctx.text, ctx, string.format("%s – %s %d%%", a.name, stageText(), floor(install.progress)), x, 4, "#FFFFFF")
  end)
  pcall(hud.add, "create_goggles", function(ctx)
    if not active or not setting("goggles") then return end
    local okS, scr = call(game, "screen")
    if okS and scr then return end
    local w, h = field(ctx, "width") or 320, field(ctx, "height") or 240
    -- Auswahl-Anzeige
    local label = "Create: " .. TYPES[selected].name .. "  ·  [B] Menü"
    pcall(ctx.text, ctx, label, 4, h - 12, argb("#FFD27F"))
    local c = targetComponent()
    if not c then return end
    local T = TYPES[c.type]
    local net = c.net and networks[c.net]
    local lines = { { T.name, "#FFFFFF" } }
    local s = c.speed or 0
    local dirTxt = s > 0 and "↻" or (s < 0 and "↺" or "")
    lines[#lines + 1] = { string.format("Drehzahl: %d RPM %s", floor(abs(s) + 0.5), dirTxt), abs(s) > 0 and "#7FFFD4" or "#AAAAAA" }
    if net then
      lines[#lines + 1] = { string.format("Stress: %d / %d SU", floor(net.impact + 0.5), floor(net.capacity + 0.5)), net.overstressed and "#FF5555" or "#FFD27F" }
      if net.overstressed then lines[#lines + 1] = { "Überlastet! Mehr Quellen anschließen.", "#FF5555" } end
      if net.conflict then lines[#lines + 1] = { "Konflikt: Drehrichtungen widersprechen sich.", "#FF5555" } end
      if net.overspeed then lines[#lines + 1] = { "Begrenzt auf 256 RPM.", "#FFAA00" } end
    end
    if T.addon == "elektrik" or T.addon == "kraftwerk" then
      lines[#lines + 1] = { string.format("Strom: %d / %d FE%s", floor(energy), ENERGY_MAX, (c.type == "electric_motor" and not c.powered) and " – zu wenig!" or ""),
        (c.type == "electric_motor" and not c.powered) and "#FF5555" or "#7FD4FF" }
    end
    if T.addon and not typeOn(c.type) then lines[#lines + 1] = { "Addon deaktiviert (B → Bestätigen)", "#FF5555" } end
    if T.redstone then
      local on = powered(c)
      local what = T.redstone == "clutch" and (on and "getrennt" or "verbunden") or (on and "umgekehrt" or "normal")
      lines[#lines + 1] = { "Redstone: " .. (on and "AN" or "AUS") .. " – " .. what, on and "#FF5555" or "#AAAAAA" }
      if not query.ok then lines[#lines + 1] = { "[Schraubenschlüssel] schaltet von Hand", "#CCCCCC" } end
    end
    if c.type == "windmill_bearing" then
      local n = c.sails or 0
      lines[#lines + 1] = { string.format("Segel: %d%s", n, n < 8 and " – mindestens 8 nötig" or ""), n < 8 and "#FF5555" or "#7FD4FF" }
    end
    if c.type == "water_wheel" and c.waterKnown and not c.water then
      lines[#lines + 1] = { "Kein Wasser am Rad – Wasser seitlich ranfließen lassen", "#FF5555" }
    end
    if c.type == "crushing_wheel" then lines[#lines + 1] = { "Paar nötig: zweites Brechrad daneben, gegenläufig", "#CCCCCC" } end
    if T.source and T.source.manual then lines[#lines + 1] = { "Rechtsklick oder [G] halten zum Kurbeln", "#CCCCCC" } end
    if c.type == "motor" then lines[#lines + 1] = { "[V] Drehzahl einstellen", "#CCCCCC" } end
    local tw = 0
    for _, l in ipairs(lines) do
      local ok, wv = pcall(ctx.textWidth, ctx, l[1])
      tw = mmax(tw, ok and wv or #l[1] * 6)
    end
    local x, y = floor(w / 2) + 12, floor(h / 2) - 6
    pcall(ctx.rect, ctx, x - 3, y - 3, tw + 6, #lines * 10 + 4, 0xA0101018)
    for i, l in ipairs(lines) do pcall(ctx.text, ctx, l[1], x, y + (i - 1) * 10, l[2]) end
  end)
end

---------------------------------------------------------------------------
-- Chatbefehle
---------------------------------------------------------------------------
local ALIASES = {
  welle = "shaft", zahnrad = "cog", grosseszahnrad = "large_cog", ["großeszahnrad"] = "large_cog", gross = "large_cog",
  getriebe = "gearbox", kurbel = "crank", handkurbel = "crank", wasserrad = "water_wheel", motor = "motor",
  bohrer = "drill", luefter = "fan", ["lüfter"] = "fan", presse = "press", mahlstein = "millstone",
  band = "belt", foerderband = "belt", ["förderband"] = "belt", tacho = "speedometer", stress = "stressometer",
  gehaeuste = "encased_shaft", kupplung = "clutch", gangschaltung = "gearshift", kette = "chain_drive",
  kettenantrieb = "chain_drive", saege = "saw", ["säge"] = "saw", brechrad = "crushing_wheel", windmuehle = "windmill_bearing",
  ["windmühle"] = "windmill_bearing", segel = "sail",
  kanone = "cannon", lichtmaschine = "alternator", elektromotor = "electric_motor", propeller = "propeller_bearing",
  verzauberer = "enchanter", abfluss = "xp_drain", solar = "solar_panel", solarpanel = "solar_panel", akku = "battery",
}

local function typeFromArg(a)
  if not a then return nil end
  a = a:lower()
  if TYPES[a] then return a end
  return ALIASES[a]
end

local function dumpApi()
  local names = {}
  for k, v in pairs(_G) do names[#names + 1] = k .. ":" .. type(v) end
  tsort(names, function(a, b) return a < b end)
  logMsg("Globals: " .. table.concat(names, ", "))
  for _, libname in ipairs({ "player", "world", "game", "chat", "hud", "ui", "keys", "settings", "storage" }) do
    local t = lib(libname)
    if type(t) == "table" then
      local fs = {}
      for k in pairs(t) do fs[#fs + 1] = tostring(k) end
      tsort(fs, function(a, b) return a < b end)
      logMsg(libname .. ": " .. table.concat(fs, ", "))
    end
  end
  local okH, held = call(player, "heldItem")
  if okH then
    if type(held) == "table" then
      local parts = {}
      for k, v in pairs(held) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
      logMsg("heldItem: {" .. table.concat(parts, ", ") .. "}")
    else
      logMsg("heldItem: " .. tostring(held))
    end
  end
  local okL, hit = call(player, "lookingAt")
  if okL then
    if type(hit) == "table" then
      local parts = {}
      for k, v in pairs(hit) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
      logMsg("lookingAt: {" .. table.concat(parts, ", ") .. "}")
    else
      logMsg("lookingAt: " .. tostring(hit))
    end
  end
  say("API-Liste steht im Mod-Log (Mods-Menü → Create → Log).")
end

local function help()
  say("§eBefehle:§r /create menü | kit | setzen <teil> | entfernen | liste | netz | motor <rpm> | addons | neubauen | zurücksetzen | api")
  say("Teile: welle, zahnrad, gross, getriebe, kurbel, wasserrad, motor, bohrer, lüfter, presse, mahlstein, band, tacho, stress")
  say("B öffnet das Menü (Bauteile, Addons). Teil in die Hand + Rechtsklick setzt es. Schraubenschlüssel: Rechtsklick dreht, Schleichen+Rechtsklick hebt auf. Welt braucht Cheats!")
end

if commands then
  pcall(commands.register, "create", function(args)
    if not active then say("Erst eine Einzelspieler-Welt betreten.") return end
    local sub = (args[1] or "hilfe"):lower()
    if sub == "hilfe" or sub == "help" then help()
    elseif sub == "menü" or sub == "menu" or sub == "menue" then openMenu()
    elseif sub == "kit" or sub == "teile" then giveKit()
    elseif sub == "addons" then openMenu("entdecken")
    elseif sub == "neubauen" or sub == "rebuild" then
      for _, c in pairs(comps) do
        unbuildComponent(c, true)
        c.mode = setting("models") and "model" or "parts"
        buildComponent(c)
      end
      say("Alle Bauteile neu aufgebaut (" .. (setting("models") and "3D-Modelle" or "Vanilla-Teile") .. ").")
    elseif sub == "setzen" or sub == "set" then
      local t = typeFromArg(args[2])
      if not t then say("Unbekanntes Teil. /create hilfe") return end
      selected = t
      placeSelected()
    elseif sub == "entfernen" or sub == "remove" then
      local c = targetComponent()
      if c then remove(c); say(TYPES[c.type].name .. " entfernt.") else say("Kein Bauteil im Blick.") end
    elseif sub == "liste" or sub == "list" then
      local count, byType = 0, {}
      for _, c in pairs(comps) do count = count + 1; byType[c.type] = (byType[c.type] or 0) + 1 end
      local parts = {}
      for _, n in ipairs(TYPE_ORDER) do if byType[n] then parts[#parts + 1] = TYPES[n].name .. " ×" .. byType[n] end end
      say(string.format("%d Bauteile: %s", count, #parts > 0 and table.concat(parts, ", ") or "keine"))
    elseif sub == "netz" or sub == "net" then
      local c = targetComponent()
      local net = c and c.net and networks[c.net]
      if not net then say("Schau auf ein angeschlossenes Bauteil.") return end
      say(string.format("Netz #%d: %d Teile, %d/%d SU%s%s", c.net, net.size, floor(net.impact), floor(net.capacity),
        net.overstressed and ", §cüberlastet§r" or "", net.conflict and ", §cKonflikt§r" or ""))
    elseif sub == "motor" then
      local c = targetComponent()
      local v = tonumber(args[2])
      if not c or c.type ~= "motor" then say("Schau auf einen Kreativmotor.") return end
      if not v then openMotorMenu(c) return end
      c.rev = v < 0
      c.rpm = mmax(1, mmin(256, floor(abs(v))))
      dirty, solveNeeded = true, true
      say("Motor: " .. c.rpm .. " RPM")
    elseif sub == "zurücksetzen" or sub == "zuruecksetzen" or sub == "reset" then
      for _, c in pairs(comps) do unbuildComponent(c) end
      cmd("kill @e[tag=cz]")
      comps, byId = {}, {}
      dirty, solveNeeded = true, true
      say("Alle Create-Bauteile entfernt.")
    elseif sub == "api" then dumpApi()
    else help() end
  end, "Create-Port: /create hilfe")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local pollRightClick, pollLeftClickFn, pollWorldFn, handleQueryFn   -- weiter unten definiert, im Tick benutzt

local function onJoin()
  worldKey = worldName()
  loadAddons()
  loadState()
  active = true
  solveNeeded = true
  tickNo = 0
  if setting("quiet") then cmd("gamerule send_command_feedback false") end
  updateNear()
  local n = 0
  for _ in pairs(comps) do n = n + 1 end
  logMsg(string.format("Welt '%s': %d Bauteile geladen (v%s)", worldKey, n, MOD_VERSION))
end

local function onLeave()
  if active and dirty then save() end
  active = false
  queue, qhead = {}, 1
end

on("world_join", onJoin)
on("world_leave", onLeave)
on("unload", onLeave)

on("tick", function()
  if not active then
    local ok, ex = call(player, "exists")
    if ok and ex then onJoin() else return end
  end
  tickNo = tickNo + 1
  stepInstall()
  Menu.tick()
  pollRightClick()
  if pollLeftClickFn then pollLeftClickFn() end
  if pollWorldFn and tickNo % 10 == 5 then pollWorldFn() end
  updateCrank()
  updateEnergy()
  if tickNo % 10 == 1 then updateNear(); countSails() end
  -- Kurbeln läuft aus
  for _, c in pairs(comps) do
    if c.type == "crank" and c.crankUntil and c.crankUntil == tickNo - 1 then solveNeeded = true end
  end
  if solveNeeded then solve(); emitStats() end
  if tickNo % 100 == 0 then emitStats() end
  if pending() < 200 then
    processMachines()
    animate()
  end
  flushQueue()
  if dirty and tickNo % 100 == 0 then save() end
end)

local function ask(tag, condition)
  cmd(string.format('execute %s run tellraw @s "czq %s"', condition, tag))
end

local function handleQuery(text)
  local tag = text:match("czq (.+)$")
  if not tag then return false end
  query.ok = true
  local kind, id = tag:match("^(%a+) (%d+)$")
  local c = id and byId[tonumber(id)]
  if c then
    if kind == "rs" then c.rsSeen = true elseif kind == "ww" then c.waterSeen = true end
  end
  return true
end

-- Alle 10 Ticks: Redstone an Kupplung/Gangschaltung, Wasser am Wasserrad
local function pollWorld()
  if not query.pinged then query.pinged = true; cmd('tellraw @s "czq ping"') end
  for _, c in pairs(comps) do
    if c.near then
      local T = TYPES[c.type]
      if T.redstone then
        if c.rsAsked then
          local now = c.rsSeen == true
          if query.ok and now ~= (c.rsPowered == true) then c.rsPowered = now; solveNeeded = true end
        end
        c.rsSeen, c.rsAsked = false, true
        ask("rs " .. c.id, string.format("if block %d %d %d minecraft:redstone_lamp[lit=true]", c.x, c.y, c.z))
      elseif c.type == "water_wheel" then
        if c.wwAsked and query.ok then
          local now = c.waterSeen == true
          if now ~= c.water or not c.waterKnown then c.water = now; c.waterKnown = true; solveNeeded = true end
        end
        c.waterSeen, c.wwAsked = false, true
        for _, ax in ipairs(PERP[c.axis or "y"]) do
          local v = AXIS_VEC[ax]
          for _, sg in ipairs({ 1, -1 }) do
            ask("ww " .. c.id, string.format("if block %d %d %d minecraft:water", c.x + v[1] * sg, c.y + v[2] * sg, c.z + v[3] * sg))
          end
        end
      end
    end
  end
end

-- Linksklick auf ein Create-Teil baut es ab (es kommt zurück ins Inventar)
local lastBreak = -100
local leftWasDown = false
local function breakTarget()
  if not active then return end
  local okS, scr = call(game, "screen")
  if okS and scr then return end
  local t = lookTarget()
  if not t then return end
  local c = at(t.x, t.y, t.z)
  if not c or tickNo - lastBreak < 4 then return end
  lastBreak = tickNo
  pickUp(c)
end
local function pollLeftClick()
  local ok, d = call(lib("mouse"), "isDown", "left")
  local down = ok and d == true
  if down and not leftWasDown then breakTarget() end
  leftWasDown = down
end

local lastUse = -100
local heldLogged = false

-- Rechtsklick mit einem Create-Teil (oder dem Schraubenschlüssel) in der Hand
local function useHeld()
  if not active then return false end
  local okS, scr = call(game, "screen")
  if okS and scr then return false end
  local part = heldPart()
  if not part then
    if not heldLogged then
      heldLogged = true
      local okH, h = call(player, "heldItem")
      local desc = tostring(h)
      if okH and (type(h) == "table") then
        local parts = {}
        for k, v in pairs(h) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        desc = "{" .. table.concat(parts, ", ") .. "}"
      end
      logMsg("Rechtsklick: Item in der Hand nicht erkannt: " .. desc)
    end
    return false
  end
  if tickNo - lastUse < 4 then return true end
  lastUse = tickNo
  if part == "wrench" then
    local c = targetComponent()
    if not c then return true end
    local okSn, sneaking = call(player, "isSneaking")
    if okSn and sneaking then pickUp(c) else wrench() end
  else
    selected = part
    placeSelected()
  end
  return true
end

-- Abfrage der rechten Maustaste in jedem Tick (funktioniert unabhängig vom Event-Format)
local rightWasDown = false
pollLeftClickFn, pollWorldFn, handleQueryFn = pollLeftClick, pollWorld, handleQuery

pollRightClick = function()
  local ok, d = call(lib("mouse"), "isDown", "right")
  local down = ok and d == true
  if down and not rightWasDown then useHeld() end
  rightWasDown = down
end

on("mouse_click", function(e)
  local action = field(e, "action") or field(e, "state")
  if action == "release" or action == "up" or field(e, "pressed") == false then return end
  local b = field(e, "button")
  local right = b == "right" or b == 1 or b == "1" or b == "secondary"
  if b == nil then
    local ok, d = call(lib("mouse"), "isDown", "right")
    right = ok and d == true
  end
  if right and useHeld() then pcall(function() e:cancel() end) end
end)

on("chat_receive", function(e)
  local raw = tostring(field(e, "message") or ""):gsub("§.", "")
  if handleQueryFn and raw:find("czq ", 1, true) and handleQueryFn(raw) then
    pcall(function() e:cancel() end)
    return
  end
  if not setting("quiet") then return end
  if tickNo - lastCmdTick > 40 then return end
  local msg = tostring(field(e, "message") or "")
  local plain = msg:gsub("§.", "")
  for _, p in ipairs(FEEDBACK) do
    if plain:find(p) then pcall(function() e:cancel() end) return end
  end
end)

loadAddons()
logMsg("Create-Port v" .. MOD_VERSION .. " geladen. B = Menü, /create hilfe")

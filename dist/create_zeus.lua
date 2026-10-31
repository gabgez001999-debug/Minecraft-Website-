-- name: Create (Eaglercraft-Port)
-- id: create_zeus
-- version: 0.1.0
-- author: Larpbase
-- description: Inoffizieller Create-Port für Eaglercraft 26.3 (Zeus-Lua). Wellen, Zahnräder, Motoren, Bohrer, Lüfter, Presse, Mahlstein, Förderband und Stress-System.
--
-- Funktionsweise
--   * Zeus-Lua-Mods laufen nur im Einzelspieler und können keine eigenen Blöcke registrieren.
--     Deshalb besteht jedes Bauteil aus einem Vanilla-Trägerblock plus Display-Entities,
--     die per Befehl gesetzt und animiert werden. Die Welt braucht dafür aktivierte Cheats.
--   * Das Kinetik-Netz (Drehzahl, Drehrichtung, Übersetzung, Stress) rechnet diese Mod in Lua,
--     angelehnt an Create (Code MIT, (c) simibubi & Create-Team). Es werden keine Create-Assets genutzt.

local MOD_VERSION = "0.1.0"

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
local defaults = { goggles = true, quiet = true, animate = true, slash = false, budget = 24 }
local function setting(name)
  local v = field(settings, name)
  if v == nil then return defaults[name] end
  return v
end
if settings then
  pcall(function()
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
}
local TYPE_ORDER = { "shaft", "cog", "large_cog", "gearbox", "crank", "water_wheel", "motor",
  "drill", "fan", "press", "millstone", "belt", "speedometer", "stressometer" }

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
      rpm = c.rpm, rev = c.rev, d = c.dim }
  end
  local data = json.encode({ v = 1, nextId = nextId, comps = list })
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
  for _, e in ipairs(data.comps or {}) do
    if TYPES[e.t] then
      local c = { id = e.id, type = e.t, x = e.x, y = e.y, z = e.z, axis = e.a, facing = e.f,
        rpm = e.rpm, rev = e.rev, dim = e.d or "overworld", angle = 0, speed = 0, progress = 0 }
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
  local b = "minecraft:" .. T.carrier
  if T.carrierAxis then b = b .. "[axis=" .. axisOf(c) .. "]" end
  return b
end

local function spinQuat(c)
  local base = BASE[axisOf(c)]
  return qmul(base, qaxis(0, 1, 0, c.angle or 0))
end

local function summonParts(c)
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
local function links(c)
  local out = {}
  local T = TYPES[c.type]
  if T.belt then return out end
  for _, face in ipairs(FACING_LIST) do
    if acceptsShaft(c, face) then
      local f = FACINGS[face]
      local n = at(c.x + f[1], c.y + f[2], c.z + f[3])
      if n and not TYPES[n.type].belt and acceptsShaft(n, OPPOSITE[face]) then
        local r = 1
        if T.gearbox then r = r * gearboxSign(c, face) end
        if TYPES[n.type].gearbox then r = r * gearboxSign(n, OPPOSITE[face]) end
        out[#out + 1] = { n, r }
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
  if not T.source then return nil end
  local sign = c.rev and -1 or 1
  if T.source.manual then
    if (c.crankUntil or -1) >= tickNo then return T.source.rpm * (c.crankDir or 1) end
    return nil
  end
  if T.source.creative then return (c.rpm or T.source.rpm) * sign end
  return T.source.rpm * sign
end

local function sourceCapacity(c, speed)
  local T = TYPES[c.type]
  if T.source.creative then return 16384 end
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
        if imp then impact = impact + imp * abs(rel[c] * k) end
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
  if at(x, y, z) then return false, "Da steht schon ein Bauteil" end
  local c = { id = nextId, type = typeName, x = x, y = y, z = z, dim = dimension(), angle = 0, speed = 0, progress = 0, near = true }
  nextId = nextId + 1
  local look = lookFacing()
  if T.directional then
    c.facing = look
  elseif T.belt then
    c.facing = horizontalFacing()
  elseif T.horizontal then
    local hf = horizontalFacing()
    c.axis = (FACINGS[hf][4] == "x") and "z" or "x"
  elseif T.gearbox then
    c.axis = "y"
  elseif T.millstone then
    c.axis = "y"
  else
    c.axis = face and FACINGS[face][4] or FACINGS[look][4]
  end
  if T.source and T.source.creative then c.rpm = T.source.rpm end
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
end

local function setPressHead(c, down)
  local y = down and -0.75 or 0
  cmd(string.format(
    "data merge entity @e[tag=c%dh,limit=1] {start_interpolation:0,interpolation_duration:4,transformation:{translation:[0f,%s,0f]}}",
    c.id, f3(y)))
end

local function processMachines()
  for _, c in pairs(comps) do
    local T = TYPES[c.type]
    if c.near and c.speed ~= 0 and (T.impact or T.belt) then
      local s = abs(c.speed)
      if c.type == "drill" then
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
          convertItems(c.x + 0.5, c.y - 1.8, c.z + 0.5, 0.8, PRESS)
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
    if #T.parts > 0 and c.near and c.speed ~= 0 then
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
    title = "Kreativmotor",
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

openMenu = function()
  if not ui then say("UI nicht verfügbar – nutze /create setzen <teil>") return end
  local ok, scr = pcall(ui.screen, {
    title = "Create – Baumenü",
    init = function(screen)
      screen:label({ text = "Ausgewählt: " .. TYPES[selected].name .. "   (R = setzen, V = drehen, X = abbauen)", centered = true })
      for _, name in ipairs(TYPE_ORDER) do
        local T = TYPES[name]
        local tag = ""
        if T.source then tag = "  [Quelle]" elseif T.impact then tag = string.format("  [%g SU/RPM]", T.impact) end
        screen:button({ text = (name == selected and "> " or "") .. T.name .. tag, onClick = function()
          selected = name
          screen:close()
          toast("Ausgewählt: " .. T.name)
        end })
      end
      screen:button({ text = "Schließen", onClick = function() screen:close() end })
    end,
  })
  if ok then call(ui, "open", scr) else say("Menü-Fehler: " .. tostring(scr)) end
end

---------------------------------------------------------------------------
-- Tasten
---------------------------------------------------------------------------
local function wrench()
  local c = targetComponent()
  if not c then say("Schau auf ein Create-Bauteil.") return end
  if c.type == "motor" then openMotorMenu(c) return end
  if c.type == "water_wheel" then
    c.rev = not c.rev
    dirty, solveNeeded = true, true
    toast("Wasserrad: Richtung umgekehrt")
    return
  end
  cycleAxis(c)
  toast(TYPES[c.type].name .. " gedreht")
end

if keys then
  local function bind(spec) pcall(keys.bind, spec) end
  bind({ id = "menu", label = "Create: Baumenü", default = "b", onPress = function() openMenu() end })
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
  pcall(hud.add, "create_goggles", function(ctx)
    if not active or not setting("goggles") then return end
    local okS, scr = call(game, "screen")
    if okS and scr then return end
    local w, h = field(ctx, "width") or 320, field(ctx, "height") or 240
    -- Auswahl-Anzeige
    local label = "Create: " .. TYPES[selected].name .. "  [B] Menü"
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
    if T.source and T.source.manual then lines[#lines + 1] = { "[G] halten zum Kurbeln (Schleichen = rückwärts)", "#CCCCCC" } end
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
  say("§eBefehle:§r /create menü | setzen <teil> | entfernen | liste | netz | motor <rpm> | zurücksetzen | api")
  say("Teile: welle, zahnrad, gross, getriebe, kurbel, wasserrad, motor, bohrer, lüfter, presse, mahlstein, band, tacho, stress")
  say("Tasten: B Menü · R setzen · V drehen/einstellen · X abbauen · G kurbeln. Welt braucht Cheats!")
end

if commands then
  pcall(commands.register, "create", function(args)
    if not active then say("Erst eine Einzelspieler-Welt betreten.") return end
    local sub = (args[1] or "hilfe"):lower()
    if sub == "hilfe" or sub == "help" then help()
    elseif sub == "menü" or sub == "menu" or sub == "menue" then openMenu()
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
local function onJoin()
  worldKey = worldName()
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
  updateCrank()
  if tickNo % 10 == 1 then updateNear() end
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

on("chat_receive", function(e)
  if not setting("quiet") then return end
  if tickNo - lastCmdTick > 40 then return end
  local msg = tostring(field(e, "message") or "")
  local plain = msg:gsub("§.", "")
  for _, p in ipairs(FEEDBACK) do
    if plain:find(p) then pcall(function() e:cancel() end) return end
  end
end)

logMsg("Create-Port v" .. MOD_VERSION .. " geladen. /create hilfe")

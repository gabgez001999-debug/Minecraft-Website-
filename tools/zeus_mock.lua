-- Nachbau der Zeus-Lua-API (Eaglercraft 26.2/26.3, API 1) zum Testen der Mods außerhalb des Spiels.
-- Nur die Teile, die die Mods benutzen. Verhalten nach den eingebauten Beispiel-Mods des Clients.

M = {
  handlers = {}, sent = {}, chatlog = {}, logs = {}, toasts = {}, hud = {}, binds = {}, cmds = {},
  store = {}, opened = {}, emitted = {}, sounds = {}, down = {},
  px = 0.5, py = 64, pz = 0.5, yaw = 270, pitch = 0, facing = "east", sneaking = false,
  vx = 0, vy = 0, vz = 0, hit = nil, screen = nil, time = 6000, day = 3,
}

function on(ev, fn)
  M.handlers[ev] = M.handlers[ev] or {}
  table.insert(M.handlers[ev], fn)
end

function M.fire(ev, data)
  for _, fn in ipairs(M.handlers[ev] or {}) do fn(data) end
end

function emit(ev, data)
  table.insert(M.emitted, { ev, data })
  M.fire(ev, data)
end

function log(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  table.insert(M.logs, table.concat(t, " "))
end
print = log

function notify(s) table.insert(M.toasts, s) end

M.world = {}   -- "x,y,z" -> Block-ID für "execute if block"

local function deliver(text)
  local e = { message = text, cancelled = false }
  function e:cancel() self.cancelled = true end
  M.fire("chat_receive", e)
  if not e.cancelled then table.insert(M.chatlog, text) end
end

-- Mini-Server: beantwortet tellraw und "execute if block … run tellraw"
local function simulate(cmd)
  local direct = cmd:match('^tellraw @s "(.-)"$')
  if direct then deliver(direct) return end
  local x, y, z, block, text = cmd:match('^execute if block (%-?%d+) (%-?%d+) (%-?%d+) (%S+) run tellraw @s "(.-)"$')
  if x and M.world[x .. "," .. y .. "," .. z] == block then deliver(text) end
end

chat = {
  print = function(s) table.insert(M.chatlog, s) end,
  command = function(s) table.insert(M.sent, s); simulate(s) end,
}

player = {
  exists = function() return true end,
  name = function() return "Larpbase" end,
  pos = function() return M.px, M.py, M.pz end,
  eyePos = function() return M.px, M.py + 1.62, M.pz end,
  blockPos = function() return math.floor(M.px), math.floor(M.py), math.floor(M.pz) end,
  facing = function() return M.facing end,
  yaw = function() return M.yaw end,
  pitch = function() return M.pitch end,
  isSneaking = function() return M.sneaking end,
  velocity = function() return M.vx, M.vy, M.vz end,
  setVelocity = function(x, y, z) M.vx, M.vy, M.vz = x, y, z end,
  lookingAt = function() return M.hit end,
  heldItem = function() return M.held end,
  dimension = function() return "minecraft:overworld" end,
  biome = function() return "minecraft:plains" end,
  health = function() return 18 end, maxHealth = function() return 20 end,
  food = function() return 17 end, saturation = function() return 3.5 end,
  armor = function() return 7 end, xpLevel = function() return 12 end, xpProgress = function() return 0.4 end,
  gamemode = function() return "creative" end,
}

game = {
  fps = function() return 60 end,
  screen = function() if M.current and not M.current.closed then return "zeus_screen" end return M.screen end,
  server = function() return nil end,
  isSingleplayer = function() return true end,
  inWorld = function() return true end,
}

world = {
  exists = function() return true end,
  day = function() return M.day end,
  timeOfDay = function() return M.time end,
  players = function() return { "Larpbase" } end,
}

keys = {
  bind = function(spec) M.binds[spec.id] = spec end,
  isDown = function(k) return M.down[k] == true end,
}
mouse = { isDown = function(b) return M.mouseDown[b] == true end }
M.mouseDown = {}

-- Rechtsklick in der Welt: Event mit cancel()
function M.rightClick()
  local e = { button = "right", cancelled = false }
  function e:cancel() self.cancelled = true end
  M.fire("mouse_click", e)
  return e
end

hud = {
  add = function(id, fn)
    if type(id) == "function" then fn, id = id, "hud" .. tostring(#M.hud + 1) end
    M.hud[id] = fn
  end,
}

-- UI: Bildschirme werden sofort "gerendert", Buttons landen in M.ui
local function makeScreen(spec)
  local s = { spec = spec, items = {}, closed = false }
  function s:label(o) table.insert(self.items, { kind = "label", text = o.text }) end
  function s:button(o) table.insert(self.items, { kind = "button", text = o.text, onClick = o.onClick }) end
  function s:textField(o) table.insert(self.items, { kind = "textField", spec = o }); return o end
  function s:rebuild() self.items = {}; spec.init(self) end
  function s:close()
    if self.closed then return end
    self.closed = true
    if M.current == self then M.current = nil end
    if spec.onClose then spec.onClose() end
  end
  return s
end
ui = {
  screen = function(spec) return makeScreen(spec) end,
  open = function(s) s.items = {}; s.spec.init(s); M.current = s; table.insert(M.opened, s) end,
}

function M.click(text)
  local s = M.current
  assert(s, "kein Bildschirm offen")
  for _, it in ipairs(s.items) do
    if it.kind == "button" and it.text:find(text, 1, true) then it.onClick(); return true end
  end
  local all = {}
  for _, it in ipairs(s.items) do all[#all + 1] = it.text or it.kind end
  error("Button nicht gefunden: " .. text .. " | vorhanden: " .. table.concat(all, " / "))
end

function M.screenKey(k)
  local s = M.current
  assert(s and s.spec.onKey, "kein onKey im Bildschirm")
  return s.spec.onKey(k)
end

function M.closeScreen()
  if M.current then M.current:close() end
end

function M.widgetCount()
  return M.current and #M.current.items or 0
end

function M.screenText()
  local s = M.current
  if not s then return "" end
  local t = { s.spec.title or "" }
  for _, it in ipairs(s.items) do t[#t + 1] = it.text or it.kind end
  return table.concat(t, "\n")
end

commands = { register = function(name, fn, desc) M.cmds[name] = fn end }

storage = {
  get = function(k) return M.store[k] end,
  set = function(k, v) M.store[k] = v end,
  has = function(k) return M.store[k] ~= nil end,
  remove = function(k) M.store[k] = nil end,
}

settings = {}
for _, kind in ipairs({ "toggle", "slider", "choice", "color", "key" }) do
  settings[kind] = function(name, spec) settings[name] = spec.default end
end

sound = { play = function(id, ...) table.insert(M.sounds, id) end }

function M.runCommand(name, ...)
  local fn = M.cmds[name]
  assert(fn, "Befehl fehlt: " .. name)
  return fn({ ... })
end

function M.ticks(n)
  for _ = 1, n do M.fire("tick") end
end

-- HUD rendern und Texte einsammeln
function M.renderHud()
  local out = {}
  local ctx = { width = 427, height = 240 }
  function ctx:text(s, x, y, c) out[#out + 1] = s end
  function ctx:centeredText(s, x, y, c) out[#out + 1] = s end
  function ctx:textWidth(s) return #s * 6 end
  function ctx:rect() end
  function ctx:fill() end
  function ctx:outline() end
  for _, fn in pairs(M.hud) do fn(ctx) end
  return table.concat(out, "\n")
end

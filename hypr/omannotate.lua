-- OmAnnotate: hold SUPER+CTRL and drag with the left mouse button to draw.
--
-- The OmAnnotate shell service loads this file into Hyprland with
-- `hyprctl eval` when it starts and after every config reload (a reload
-- starts a fresh Lua state and drops runtime binds). Hyprland only announces
-- the line on its event socket; the service draws it:
--   custom>>omannotate start X Y   the button went down
--   custom>>omannotate move X Y    the cursor moved (at most once per frame)
--   custom>>omannotate end         the button came up
--
-- Binds are created once and then only enabled or disabled, never unbound:
-- in Hyprland 0.56 unbinding removes every bind on the same key, and touching
-- a removed bind from Lua crashes Hyprland. tostring() is the one safe way to
-- see whether a bind was removed elsewhere.

local VERSION = 3

-- Already loaded into this Lua state.
if type(omannotate) == "table" and omannotate.version == VERSION then return end

local PEN = "SUPER + CTRL + mouse:272"
local BUTTON = "mouse:272"
local FRAME_MS = 16

-- A plugin update loads a newer copy into the same Lua state. It keeps the
-- older copy's binds, timer and state, and they run the new code because
-- every callback goes through the global `omannotate` table.
local previous = type(omannotate) == "table" and type(omannotate.state) == "table" and omannotate or nil
local state = previous and previous.state or { drawing = false, enabled = false }
local M = { version = VERSION, state = state }
if previous then M.pen, M.release, M.sampler = previous.pen, previous.release, previous.sampler end
omannotate = M

local function emit(text)
  hl.dispatch(hl.dsp.event("omannotate " .. text))
end

-- Cursor movement has no Lua event, so it is sampled only while a line is drawn.
function M.sample()
  if not state.drawing then return end
  local position = hl.get_cursor_pos()
  if position and (position.x ~= state.x or position.y ~= state.y) then
    state.x, state.y = position.x, position.y
    emit(string.format("move %.2f %.2f", position.x, position.y))
  end
end

function M.finish()
  if state.drawing then
    -- The button can come up after the cursor moved since the last sample, so
    -- the line ends where the button was released.
    M.sample()
    state.drawing = false
    M.sampler:set_enabled(false)
    emit("end")
  end
end

function M.press()
  local position = hl.get_cursor_pos()
  if position then
    state.drawing, state.x, state.y = true, position.x, position.y
    emit(string.format("start %.2f %.2f", position.x, position.y))
    M.sampler:set_enabled(true)
  end
end

local function alive(keybind)
  return keybind ~= nil and tostring(keybind) ~= "HL.Keybind(expired)"
end

-- Creates what is missing; a live bind is never replaced, and a bind removed
-- elsewhere is recreated without touching the removed one.
local function ensure()
  if not M.sampler then
    M.sampler = hl.timer(function() omannotate.sample() end, { timeout = FRAME_MS, type = "repeat" })
    M.sampler:set_enabled(false)
  end
  if not alive(M.pen) then
    M.pen = hl.bind(PEN, function() omannotate.press() end, { description = "OmAnnotate: draw on screen" })
  end
  if not alive(M.release) then
    -- Ends the line even if the keys are let go before the button. A release
    -- bind swallows every press unless it is non-consuming.
    M.release = hl.bind(BUTTON, function() omannotate.finish() end,
      { release = true, ignore_mods = true, non_consuming = true })
  end
end

local function apply()
  for _, keybind in ipairs({ M.pen, M.release }) do
    if alive(keybind) then keybind:set_enabled(state.enabled) end
  end
  if not state.enabled then M.finish() end
end

-- The newest shell service owns the shortcut. A replaced service shutting
-- down after a plugin reload must not switch the new one's shortcut off.
function M.activate(token)
  state.owner, state.enabled = token, true
  ensure()
  apply()
end

function M.deactivate(token)
  if token == state.owner then
    state.owner, state.enabled = nil, false
    apply()
  end
end

-- For checking the shortcut: hyprctl repl 'return omannotate.enabled()'
function M.enabled()
  return state.enabled
end

if not previous then
  hl.layer_rule({ match = { namespace = "omannotate" }, no_anim = true, animation = "none" })
end
ensure()
apply()  -- Off until a service activates it (unchanged when updating a running copy).

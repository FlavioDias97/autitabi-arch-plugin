-- Autitabi — minimize / restore helpers for the Hyprland Lua config.
--
-- SPDX-License-Identifier: GPL-3.0-only
-- SPDX-FileCopyrightText: 2026 FlavioDias97
--
-- A minimized window is parked in the native `special:minimized` workspace with
-- a window tag recording where it came from. The switcher (and SUPER+SHIFT+M,
-- if bound) restores it to that workspace. The tag lives on the window itself:
-- it is scoped to that window, shows up in `hyprctl clients -j`, survives
-- `hyprctl reload` and shell reloads, and is dropped automatically when the
-- window closes. No daemon, state file or address table.
--
-- Load this before autitabi-bindings.lua (that file loads it for you if it is
-- next to it).

local ORIGIN_TAG_PREFIX = "autitabi-origin-ws-"
-- The same string as a Lua pattern. Hyphens are magic in Lua patterns and must
-- be escaped, otherwise the origin never reads back.
local ORIGIN_TAG_PATTERN = "^autitabi%-origin%-ws%-(%d+)$"

local function read_origin_workspace(window)
  if window == nil or window.tags == nil then
    return nil
  end
  for _, tag in ipairs(window.tags) do
    local id = tostring(tag):match(ORIGIN_TAG_PATTERN)
    if id ~= nil then
      return tonumber(id)
    end
  end
  return nil
end

-- Record the active window's workspace, then park it in special:minimized
-- without following it there. Returns the move dispatcher for the caller.
function autitabi_minimize_window()
  local window = hl.get_active_window()
  if window == nil or window.workspace == nil then
    return
  end
  if window.workspace.name == "special:minimized" then
    return
  end
  local origin = window.workspace.id
  if type(origin) == "number" and origin > 0 then
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. ORIGIN_TAG_PREFIX .. origin, window = window }))
  end
  return hl.dsp.window.move({ workspace = "special:minimized", window = window, follow = false })
end

-- Restore a minimized window to its recorded origin workspace, never the
-- workspace the user is on now. `target` is an address string ("0x...") or nil
-- for the active window.
function autitabi_restore_minimized_window(target)
  local window
  if target == nil or target == "" then
    window = hl.get_active_window()
  else
    window = hl.get_window("address:" .. tostring(target))
  end
  if window == nil or window.workspace == nil then
    return
  end
  if window.workspace.name ~= "special:minimized" then
    return hl.dsp.focus({ window = window })
  end

  local origin = read_origin_workspace(window)
  if origin == nil then
    -- Minimized before this module was loaded, or the tag was lost: fall back
    -- to the active workspace so the window is never stranded.
    local monitor = hl.get_active_monitor()
    origin = (monitor and monitor.active_workspace and monitor.active_workspace.id) or 1
  end

  -- Order: move (follows the window to the origin workspace), then drop the
  -- tag, then focus the exact window.
  hl.dispatch(hl.dsp.window.move({ workspace = tostring(origin), window = window }))
  hl.dispatch(hl.dsp.window.tag({ tag = "-" .. ORIGIN_TAG_PREFIX .. origin, window = window }))
  return hl.dsp.focus({ window = window })
end

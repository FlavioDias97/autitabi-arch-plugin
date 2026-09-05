-- Autitabi — Alt+Tab bindings for the Hyprland Lua config (Hyprland >= 0.56).
--
-- SPDX-License-Identifier: GPL-3.0-only
-- SPDX-FileCopyrightText: 2026 FlavioDias97
--
-- dofile() this from ~/.config/hypr/bindings.lua (or customisation.lua). It
-- only touches ALT+TAB, ALT+SHIFT+TAB and the ALT release; nothing else.

-- Load the minimize/restore helpers from the file next to this one, unless the
-- user already loaded them. A failure here is raised, not swallowed, so it
-- shows up in `hyprctl configerrors`.
if type(autitabi_restore_minimized_window) ~= "function" then
  local dir = debug.getinfo(1, "S").source:match("^@(.*/)")
  if not dir then
    error("autitabi-bindings.lua: cannot locate its own directory; "
      .. "dofile hypr/autitabi.lua yourself before this file")
  end
  dofile(dir .. "autitabi.lua")
end

hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Autitabi: next", hl.dsp.global("autitabi:next"), { repeating = true })
o.bind("ALT + SHIFT + TAB", "Autitabi: prev", hl.dsp.global("autitabi:prev"), { repeating = true })

-- Commit the selection when either ALT is released. Done at the Hyprland level
-- so it is reliable even on a very fast tap, before the overlay grabs the
-- keyboard. Harmless while the overlay is closed.
hl.bind("ALT + ALT_L", hl.dsp.global("autitabi:commit"), { release = true, non_consuming = true })
hl.bind("ALT + ALT_R", hl.dsp.global("autitabi:commit"), { release = true, non_consuming = true })

-- No open/close animation for the overlay layer.
hl.layer_rule({ match = { namespace = "autitabi" }, no_anim = true, animation = "none" })

-- Optional: minimize / show / restore. autitabi.lua must be loaded (it is,
-- above). Bind autitabi_minimize_window() to a key or a hyprbars button.
--
-- o.bind("SUPER + M", "Minimize window", function()
--   hl.dispatch(autitabi_minimize_window())
-- end)
-- o.bind("SUPER + SHIFT + M", "Show minimized windows",
--   hl.dsp.workspace.toggle_special("minimized"))
-- o.bind("SUPER + CTRL + M", "Restore minimized window", function()
--   hl.dispatch(autitabi_restore_minimized_window())
-- end)

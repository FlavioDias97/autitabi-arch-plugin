// Pure list logic for the Autitabi window switcher. No Quickshell / QML imports
// so it can be unit-tested on its own; icon and name resolution stay in
// WindowSwitcher.qml because they need DesktopEntries.
//
// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 FlavioDias97
.pragma library

var SPECIAL_MINIMIZED = "special:minimized";

// Keep a client if it is a real mapped window on a normal workspace, or on
// special:minimized (windows parked there by autitabi_minimize_window). Every
// other special workspace is skipped. `hidden` windows are kept on purpose:
// on compositor versions that report inactive group tabs as hidden they must
// still show up. Pinned windows are kept.
function isSwitchable(client) {
  if (!client || client.mapped === false) return false;
  if (!client.address || String(client.address).length === 0) return false;
  var ws = client.workspace || {};
  return Number(ws.id) > 0 || String(ws.name || "") === SPECIAL_MINIMIZED;
}

function filterClients(clients) {
  var out = [];
  for (var i = 0; i < clients.length; i++)
    if (isSwitchable(clients[i])) out.push(clients[i]);
  return out;
}

// Most-recently-used order: ascending focusHistoryID (0 = focused window first),
// windows without a valid id last. Stable for equal ids.
function sortByMru(clients) {
  var keyed = clients.map(function (c, i) {
    var h = Number(c.focusHistoryID);
    if (!isFinite(h) || h < 0) h = 1e9;
    return { c: c, h: h, i: i };
  });
  keyed.sort(function (a, b) { return a.h !== b.h ? a.h - b.h : a.i - b.i; });
  return keyed.map(function (k) { return k.c; });
}

// 1-based position of this client's address inside its Hyprland group, or 0
// when it is not grouped. Address only — never title or class.
function groupIndexOf(client) {
  var g = client && client.grouped;
  if (!g || !g.length) return 0;
  var idx = g.indexOf(client.address);
  return idx >= 0 ? idx + 1 : 0;
}

// Badge text for a workspace. special:minimized -> "Minimized"; a named
// workspace shows its name; a numbered one -> "Workspace N".
function workspaceLabel(id, name) {
  var raw = String(name || "");
  if (raw === SPECIAL_MINIMIZED) return "Minimized";
  if (raw.length > 0 && !/^\d+$/.test(raw)) return raw;
  var numeric = /^\d+$/.test(raw) ? raw : (Number(id) > 0 ? String(Number(id)) : "");
  return numeric.length > 0 ? "Workspace " + numeric : "Workspace ?";
}

// Lowercase alnum token for matching a WM class against desktop-entry ids/names.
function normalizeClass(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]/g, "");
}

// Build the switcher's row list from `hyprctl clients -j`: filtered, MRU-sorted,
// with the derived fields the UI and the confirm action need. `nameFor(class)`
// returns the display name and is supplied by the QML.
function buildRows(rawClients, nameFor) {
  var rows = sortByMru(filterClients(rawClients || []));
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var c = rows[i];
    var ws = c.workspace || {};
    var wsId = Number(ws.id);
    var wsName = String(ws.name || "");
    out.push({
      address: String(c.address),
      appClass: String(c.class || "Application"),
      appName: nameFor ? nameFor(c.class) : String(c.class || "Application"),
      windowTitle: String(c.title || "Untitled window"),
      workspaceId: wsId > 0 ? wsId : 0,
      workspaceName: wsName,
      workspaceLabel: workspaceLabel(wsId, wsName),
      isMinimized: wsName === SPECIAL_MINIMIZED,
      isFloating: c.floating === true,
      isPinned: c.pinned === true,
      isGrouped: groupIndexOf(c) > 0,
      groupIndex: groupIndexOf(c)
    });
  }
  return out;
}

// Selected row when the overlay opens. `steps` is the accumulated direction of
// the key that opened it: +1 opens on the second-MRU window, -1 on the last.
function initialSelection(count, steps) {
  if (count <= 1) return 0;
  var s = Number(steps) || 0;
  return ((s % count) + count) % count;
}

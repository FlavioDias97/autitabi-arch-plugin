// Autitabi — visual Alt+Tab window switcher for Hyprland.
//
// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 FlavioDias97
//
// This file also contains portions adapted from c4software/hyprland-alttab
// (MIT, Copyright (c) 2026 Valentin Brosseau): the resolveIcon() cascade, the
// close -> timer -> dispatch teardown skeleton, the hover-arming MouseArea, and
// the Keys.onReleased modifier-still-held check. See THIRD_PARTY_NOTICES.md.
//
// Loaded as an Omarchy shell "overlay" plugin (keepLoaded), so this Item is
// always instantiated inside the omarchy-shell process and its GlobalShortcut
// objects stay registered. The overlay window itself only exists while open.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "WindowSwitcherLogic.js" as Logic

Item {
  id: root

  // Injected by omarchy-shell's plugin loader.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool initializing: false
  property int pendingSteps: 0
  property int selectedIndex: 0

  // Non-modifier keys currently held inside the overlay; a held key blocks the
  // in-overlay "release ALT -> commit" fallback.
  property var heldKeys: ({})

  // Selection captured at confirm time, dispatched only after the overlay
  // surface is gone (see commitTimer).
  property string pendingAddress: ""
  property int pendingWorkspaceId: 0
  property int pendingGroupIndex: 0
  property bool pendingMinimized: false
  property bool hasPendingAction: false
  // ALT was released before `hyprctl clients` returned: nothing to select yet,
  // so remember the intent and commit once the list is ready.
  property bool commitWhenReady: false

  // --- Omarchy theme adapter -------------------------------------------------
  // The only hard dependency on omarchy-shell's QML modules. A standalone build
  // would replace these with a local palette and swap BorderSurface for a
  // Rectangle. `shell.appLibrary` (used in iconForEntry) is the other one.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int rowHeight: Math.max(Style.space(72), Style.font.title + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int cardWidth: Math.min(Style.space(760), (panelLoader.item ? panelLoader.item.width : 1200) - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(520), Math.max(Style.space(150), windowModel.count * rowHeight + Style.spacing.panelPadding * 2 + Style.space(44)))
  // ------------------------------------------------------------------------

  function directionFromPayload(payloadJson) {
    try {
      var payload = JSON.parse(payloadJson || "{}")
      return Number(payload.direction) < 0 ? -1 : 1
    } catch (e) {
      return 1
    }
  }

  // Every open path lands here: the next/prev GlobalShortcuts and the
  // `omarchy-shell shell summon` IPC. Re-invoking while open just advances.
  function open(payloadJson) {
    var direction = directionFromPayload(payloadJson)
    if (root.opened) {
      if (root.initializing) root.pendingSteps += direction
      else root.select(direction)
      return
    }

    root.opened = true
    root.initializing = true
    root.pendingSteps = direction
    root.selectedIndex = 0
    root.heldKeys = ({})
    root.hasPendingAction = false
    root.commitWhenReady = false
    root.queryClients()
  }

  // Only an explicit true commits. Escape, click-outside and a bare IPC
  // `dismiss` just close the overlay.
  function dismiss(doFocus) {
    if (!root.opened) return "closed"
    var commit = doFocus === true || doFocus === "true"
    if (commit && root.initializing) {
      root.commitWhenReady = true
      return "deferred"
    }
    if (commit && windowModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < windowModel.count) {
      var row = windowModel.get(root.selectedIndex)
      root.pendingAddress = row.address
      root.pendingWorkspaceId = Number(row.workspaceId)
      root.pendingGroupIndex = Number(row.groupIndex)
      root.pendingMinimized = row.isMinimized === true
      root.hasPendingAction = true
    }
    root.opened = false
    root.initializing = false
    root.pendingSteps = 0
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "autitabi.window-switcher")
    if (root.hasPendingAction) commitTimer.restart()
    return "ok"
  }

  // Single confirmation path: click, Enter, ALT release and the `commit`
  // GlobalShortcut all route through here.
  function confirmSelection() {
    return root.dismiss(true)
  }

  // Runs after the overlay surface (and its exclusive keyboard grab) is gone.
  // Dispatching earlier loses a race: tearing down the grab briefly returns
  // focus to the previously active window.
  function commit() {
    if (!root.hasPendingAction) return
    root.hasPendingAction = false
    var address = root.pendingAddress
    if (!address) return

    if (root.pendingMinimized) {
      // Restore goes through the shared Lua helper (hypr/autitabi.lua): it reads
      // the window's origin tag, moves it back to that workspace, clears the tag
      // and focuses it. A hyprctl subprocess is used only here because
      // Hyprland.dispatch() cannot carry the anonymous-function wrapper the
      // Omarchy Lua eval needs; a normal Alt+Tab never spawns anything.
      Quickshell.execDetached([
        "hyprctl", "dispatch",
        '(function() return autitabi_restore_minimized_window("' + address + '") end)()'
      ])
      return
    }

    // Normal / grouped window: never moved between workspaces. Order matters —
    // switch workspace, then raise the correct group tab (a harmless warning
    // for ungrouped windows), then focus the exact window by address.
    if (root.pendingWorkspaceId > 0)
      Hyprland.dispatch('hl.dsp.focus({ workspace = "' + root.pendingWorkspaceId + '" })')
    if (root.pendingGroupIndex > 0)
      Hyprland.dispatch('hl.dsp.group.active({ window = "address:' + address + '", index = ' + root.pendingGroupIndex + ' })')
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  Timer {
    id: commitTimer
    // Smallest interval that reliably wins the teardown/focus race in testing.
    interval: 80
    repeat: false
    onTriggered: root.commit()
  }

  function modulo(value, count) {
    return ((value % count) + count) % count
  }

  function select(delta) {
    if (windowModel.count <= 1) {
      root.selectedIndex = 0
      return
    }
    root.selectedIndex = modulo(root.selectedIndex + delta, windowModel.count)
    if (panelLoader.item && panelLoader.item.windowList)
      panelLoader.item.windowList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function queryClients() {
    if (clientQuery.running) return
    clientQuery.running = true
  }

  function iconForEntry(entry) {
    if (entry && entry.icon && root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.iconSource(entry.icon)
    if (entry && entry.icon)
      return Quickshell.iconPath(entry.icon, "application-x-executable")
    return ""
  }

  // Icon cascade: desktop entry by id variants, then StartupWMClass, then an
  // app name found inside the window title (Chrome PWAs / Electron), then icon
  // theme name variants, then a generic fallback.
  function resolveIcon(appClass, title) {
    var cls = String(appClass || "")
    var clsLower = cls.toLowerCase()
    var variants = [cls, clsLower, cls.replace(/-/g, ""), cls.split(".")[0]]
    for (var i = 0; i < variants.length; i++) {
      if (!variants[i]) continue
      var e = DesktopEntries.byId(variants[i])
      if (e && e.icon) return iconForEntry(e)
    }
    var all = DesktopEntries.applications.values || []
    for (var j = 0; j < all.length; j++) {
      var sc = all[j].startupClass
      if (sc && String(sc).toLowerCase() === clsLower && all[j].icon)
        return iconForEntry(all[j])
    }
    var titleLower = String(title || "").toLowerCase()
    if (titleLower) {
      for (var k = 0; k < all.length; k++) {
        var n = String(all[k].name || "").toLowerCase()
        if (n && n.length > 2 && titleLower.indexOf(n) !== -1 && all[k].icon)
          return iconForEntry(all[k])
      }
    }
    var themeNames = [cls, clsLower, cls.split("-")[0], cls.split(".").pop()]
    for (var m = 0; m < themeNames.length; m++) {
      if (!themeNames[m]) continue
      var p = Quickshell.iconPath(themeNames[m], true)
      if (p) return p
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Display name: best fuzzy match of the WM class against desktop-entry
  // id/name, else the raw class.
  function appName(appClass) {
    var fallback = String(appClass || "Application")
    var needle = Logic.normalizeClass(appClass)
    if (!needle) return fallback
    var all = DesktopEntries.applications.values || []
    var best = null
    var bestScore = -1
    for (var i = 0; i < all.length; i++) {
      var id = Logic.normalizeClass(all[i].id)
      var name = Logic.normalizeClass(all[i].name)
      var score = -1
      if (id === needle) score = 4
      else if (name === needle) score = 3
      else if (id.indexOf(needle) !== -1 || needle.indexOf(id) !== -1) score = 2
      else if (name.indexOf(needle) !== -1 || needle.indexOf(name) !== -1) score = 1
      if (score > bestScore) { best = all[i]; bestScore = score }
    }
    return best ? String(best.name || fallback) : fallback
  }

  // The client list is queried once, when the overlay opens (initializing is
  // always true here — there is no live refresh).
  function applyClients(rawJson) {
    var clients
    try {
      clients = JSON.parse(rawJson || "[]")
    } catch (e) {
      console.warn("autitabi: invalid hyprctl clients JSON:", e)
      root.dismiss(false)
      return
    }

    var rows = Logic.buildRows(clients, function(c) { return root.appName(c) })

    windowModel.clear()
    for (var i = 0; i < rows.length; i++)
      windowModel.append(rows[i])

    if (windowModel.count === 0) {
      root.dismiss(false)
      return
    }

    root.selectedIndex = Logic.initialSelection(windowModel.count, root.pendingSteps)
    root.initializing = false
    root.pendingSteps = 0
    if (root.commitWhenReady) {
      root.commitWhenReady = false
      Qt.callLater(function() { root.dismiss(true) })
      return
    }

    Qt.callLater(function() {
      if (panelLoader.item && panelLoader.item.keyCatcher)
        panelLoader.item.keyCatcher.forceActiveFocus()
      if (panelLoader.item && panelLoader.item.windowList)
        panelLoader.item.windowList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // Read-only snapshot for troubleshooting:
  //   omarchy-shell shell call autitabi.window-switcher debugState x
  function debugState(unused) {
    var windows = []
    for (var i = 0; i < windowModel.count; i++) {
      var row = windowModel.get(i)
      windows.push({
        address: row.address,
        appClass: row.appClass,
        title: row.windowTitle,
        workspace: row.workspaceLabel,
        workspaceId: row.workspaceId,
        minimized: row.isMinimized,
        floating: row.isFloating,
        pinned: row.isPinned,
        grouped: row.isGrouped,
        groupIndex: row.groupIndex
      })
    }
    return JSON.stringify({
      opened: root.opened,
      initializing: root.initializing,
      selectedIndex: root.selectedIndex,
      windows: windows
    })
  }

  ListModel { id: windowModel }

  // Hyprland binds ALT+TAB / ALT+SHIFT+TAB to `global autitabi:{next,prev}` and
  // the ALT release to `autitabi:commit` — in-process, no subprocess per key.
  GlobalShortcut {
    appid: "autitabi"
    name: "next"
    onPressed: root.open('{"direction":1}')
  }
  GlobalShortcut {
    appid: "autitabi"
    name: "prev"
    onPressed: root.open('{"direction":-1}')
  }
  GlobalShortcut {
    appid: "autitabi"
    name: "commit"
    onPressed: root.confirmSelection()
  }

  Process {
    id: clientQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: clientOutput; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (!root.opened) return
      if (exitCode === 0) root.applyClients(clientOutput.text)
      else root.dismiss(false)
    }
  }

  // Created only while open and destroyed on close, so the exclusive keyboard
  // grab is really gone before commitTimer fires.
  LazyLoader {
    id: panelLoader
    active: root.opened

    PanelWindow {
      id: panel
      property alias keyCatcher: keyCatcher
      property alias windowList: windowList

      // Hover only takes over the selection after the pointer has actually
      // moved; otherwise a row scrolling under a stationary cursor would steal
      // the keyboard selection.
      property bool hoverArmed: false
      property point hoverOrigin: Qt.point(-1, -1)

      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "autitabi"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      Component.onCompleted: Qt.callLater(function() { keyCatcher.forceActiveFocus() })

      Rectangle {
        anchors.fill: parent
        color: root.scrim
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss(false)
      }

      BorderSurface {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        radius: root.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onPositionChanged: function(mouse) {
            if (panel.hoverArmed) return
            if (panel.hoverOrigin.x < 0) {
              panel.hoverOrigin = Qt.point(mouse.x, mouse.y)
              return
            }
            if (Math.abs(mouse.x - panel.hoverOrigin.x) + Math.abs(mouse.y - panel.hoverOrigin.y) > 4)
              panel.hoverArmed = true
          }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: {} }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          z: 2

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss(false)
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              root.select(event.modifiers & Qt.ShiftModifier ? -1 : 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
              root.select(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
              root.select(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
              root.select(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.confirmSelection()
              event.accepted = true
            } else if (event.key !== Qt.Key_Alt && event.key !== Qt.Key_Meta
                       && event.key !== Qt.Key_Shift && event.key !== Qt.Key_Control) {
              root.heldKeys[event.key] = true
            }
          }

          // Fallback for setups that did not bind autitabi:commit to the ALT
          // release: commit when the modifier is let go and nothing else is
          // held. The Hyprland release binding, when present, is race-free.
          Keys.onReleased: function(event) {
            delete root.heldKeys[event.key]
            var k = event.key
            var isMod = k === Qt.Key_Alt || k === Qt.Key_Meta
              || k === Qt.Key_Super_L || k === Qt.Key_Super_R
            if (!isMod) return
            var altHeld = (event.modifiers & Qt.AltModifier) && k !== Qt.Key_Alt
            var metaHeld = (event.modifiers & Qt.MetaModifier)
              && k !== Qt.Key_Meta && k !== Qt.Key_Super_L && k !== Qt.Key_Super_R
            var otherHeld = false
            for (var held in root.heldKeys) { otherHeld = true; break }
            if (!altHeld && !metaHeld && !otherHeld)
              root.confirmSelection()
          }
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.space(8)

          Text {
            width: parent.width
            height: Style.space(34)
            text: "Windows"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }

          ListView {
            id: windowList
            width: parent.width
            height: parent.height - Style.space(42)
            model: windowModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: windowRow
              required property int index
              required property string address
              required property string appClass
              required property string appName
              required property string windowTitle
              required property int workspaceId
              required property string workspaceName
              required property string workspaceLabel
              required property bool isMinimized
              required property bool isFloating
              required property bool isPinned
              required property bool isGrouped
              required property int groupIndex

              readonly property bool selected: index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: selected ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(12)

                Image {
                  width: parent.height
                  height: parent.height
                  source: root.resolveIcon(windowRow.appClass, windowRow.windowTitle)
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }

                Column {
                  width: parent.width - parent.height - workspaceBadge.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: windowRow.appName
                    color: windowRow.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: windowRow.windowTitle
                    color: windowRow.selected ? root.selectedText : root.foreground
                    opacity: windowRow.selected ? 0.86 : 0.62
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: workspaceBadge
                  anchors.verticalCenter: parent.verticalCenter
                  text: (windowRow.isFloating ? "󰉈  " : "") + windowRow.workspaceLabel
                  color: windowRow.selected ? root.selectedText : root.foreground
                  opacity: windowRow.selected ? 1 : 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: if (panel.hoverArmed) root.selectedIndex = windowRow.index
                onPositionChanged: if (panel.hoverArmed) root.selectedIndex = windowRow.index
                onClicked: {
                  root.selectedIndex = windowRow.index
                  root.confirmSelection()
                }
              }
            }
          }
        }
      }
    }
  }
}

# Changelog

All notable changes to this project are documented here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - Unreleased

Initial public release.

- Visual Alt+Tab overlay for Hyprland, hosted by the Omarchy shell.
- Lists windows from every normal workspace plus `special:minimized`.
- MRU ordering by `focusHistoryID`; opens on the second-MRU window.
- Per-row workspace label, app icon and title; windows identified by address.
- `ALT+TAB` / `ALT+SHIFT+TAB` via Hyprland GlobalShortcuts (in-process),
  `ALT+SHIFT+TAB` opens in reverse.
- Keyboard, mouse hover and click navigation; Enter activates, Escape cancels
  without changing focus, releasing ALT activates.
- Hyprland group tabs: shown, and activated by address + group index on select.
- Pinned windows are shown.
- Minimized windows restore to their original workspace via a native window
  tag; the tag is cleared on restore.
- Teardown-before-focus and a fast-tap guard.
- Theme follows the active Omarchy theme.

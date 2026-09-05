# Third-party notices

## c4software/hyprland-alttab

<https://github.com/c4software/hyprland-alttab> — MIT license,
Copyright (c) 2026 Valentin Brosseau.

Autitabi is an independent project. Some of its code is adapted from
`hyprland-alttab`; other parts only follow ideas seen there. This distinction is
recorded below.

### Adapted code (MIT origin, redistributed here under GPL-3.0-only)

- **`src/WindowSwitcher.qml`**
  - `resolveIcon()` — the icon-resolution cascade: the same five stages in the
    same order, and the same class-name variant arrays
    (`[cls, clsLower, cls.replace(/-/g, ""), cls.split(".")[0]]` for the desktop
    entry lookup, `[cls, clsLower, cls.split("-")[0], cls.split(".").pop()]` for
    the icon-theme probe). Reimplemented with plain `for` loops and an
    `iconForEntry()` helper.
  - The **close → `Timer` → dispatch** teardown skeleton: capturing the target
    (`pendingAddress` / `pendingGroupIndex`), closing the overlay first, then
    dispatching after a short delay, and issuing
    `hl.dsp.group.active({ window = "address:…", index = N })` before
    `hl.dsp.focus({ window = "address:…" })`. Autitabi extends this with a
    workspace switch, a minimized-restore branch and a fast-tap guard.
  - The **hover-arming `MouseArea`** (`hoverArmed` + a `Qt.point(-1, -1)` origin,
    `hoverEnabled` + `acceptedButtons: Qt.NoButton`, arm on Manhattan-distance
    threshold) — close to verbatim; renamed `initialPos` → `hoverOrigin` and
    changed the threshold from 3 to 4.
  - The **`Keys.onReleased` modifier-still-held check** and the `heldKeys` map:
    subtracting the key being released from `event.modifiers` to decide whether
    ALT/Meta is still down, plus "no other key held", before activating.

### Ideas followed (no code adapted)

- **`hypr/autitabi-bindings.lua`** is an independent implementation. Binding a
  key to `hl.dsp.global(name)` with `{ repeating = true }` and adding
  `hl.layer_rule({ match = { namespace = … }, no_anim = true })` for the overlay
  is idiomatic Omarchy/Hyprland API usage — the same `layer_rule` shape appears
  in Omarchy's own shipped config. The self-loading guard, the separate
  `next` / `prev` / `commit` shortcuts and the ALT-release binding are Autitabi's.
- **`src/WindowSwitcherLogic.js`** — the "pure logic, no Quickshell imports so it
  stays testable" header note and the `grouped.indexOf(address) + 1` shape for a
  1-based group index follow `logic.js`. The rest (workspace filter, flat
  MRU list model, `workspaceLabel`, `initialSelection`, `normalizeClass`,
  `buildRows`) is original. `initialSelection` in particular is a
  `modulo(steps, count)` of the accumulated key direction and is unrelated to
  `logic.js`'s focus-history scan.

### MIT compliance

`omarchy plugin add` clones this whole repository, so every user receives this
file. It reproduces the upstream MIT license text in full, with Valentin
Brosseau's copyright notice, the permission notice and the warranty disclaimer
intact. **For the current (git-clone) distribution this file is sufficient to
satisfy the MIT "include in all copies or substantial portions" requirement.**
A future binary/tarball release must ship this file and `LICENSE` alongside the
code. The short SPDX header in `src/WindowSwitcher.qml` points a reader of that
file alone back here.

The original upstream code stays available under the MIT license from
`c4software/hyprland-alttab`. Autitabi, as a combined and partly derived work,
is distributed as a whole under GPL-3.0-only, which the MIT terms permit. The
upstream copyright (`Copyright (c) 2026 Valentin Brosseau`) and the MIT
permission notice reproduced above are preserved and unaffected.

### Upstream MIT license text

```
MIT License

Copyright (c) 2026 Valentin Brosseau

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Runtime dependencies

Hyprland, Quickshell, Qt and the Omarchy shell are required at runtime but no
code from them is redistributed in this repository, so no notice is included for
them here.

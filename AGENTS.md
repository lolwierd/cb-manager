# AGENTS.md

Guidance for coding agents working on **CBManager**.

## Project summary

CBManager is a native macOS menu bar clipboard manager with a Spotlight-style overlay.

Core loop:
1. Capture clipboard entries (text, links, code, paths, images).
2. Search quickly (instant fuzzy) and augment with QMD keyword/semantic retrieval.
3. Confirm selection and paste back into previous app.

## Tech stack

- Swift + SwiftUI + AppKit (menu bar utility, custom panels)
- Minimum deployment target: macOS 26
- Carbon hotkeys
- SQLite (`sqlite3`) for persistence
- Vision for OCR on images
- QMD CLI (`qmd search`, `qmd vsearch`, `qmd update`, `qmd embed`) for retrieval/indexing

## Important paths

- Main sources: `Sources/CBManager`
- Tests: `Tests/CBManagerTests`
- User data:
  - SQLite DB: `~/Library/Application Support/CBManager/clipboard.sqlite`
  - Images: `~/Library/Application Support/CBManager/images/`
  - QMD docs: `~/Library/Application Support/CBManager/qmd-docs/`

## Commands

```bash
swift build
swift run
swift test
./scripts/reload-dev.sh
./scripts/install.sh
```

## Architecture map

- `AppModel.swift` — app coordinator, status item actions, hotkey setup.
- `StatusBarController.swift` — menu bar icon behavior.
- `OverlayPanelController.swift` — main overlay panel, focus restore, paste flow, preview toggle.
- `SearchOverlayView.swift` — overlay UI, keyboard interaction, list/preview panes.
- `ClipboardStore.swift` — clipboard capture, filtering/search merge, delete/undo, OCR updates.
- `ClipboardSearch.swift` — pure ranking/search helpers (fuzzy + QMD threshold logic).
- `ClipboardDatabase.swift` — SQLite CRUD.
- `QMDSearchEngine.swift` — write docs + run qmd keyword/semantic/index/embed.
- `EntryPreviewPanelController.swift` — in-app preview panel (toggle via ⌘Y).

## Behavioral invariants (do not break)

1. **Overlay open defaults**
   - Search bar is focused on open.
   - Latest/newest visible entry is selected.

2. **Keyboard semantics**
   - `⌘⇧V`: open/toggle overlay (global shortcut; user-customizable).
   - `↑/↓`: move selection.
   - `Return`: paste selected entry into previous app.
   - `⌘D`: delete selected entry.
   - `⌘Z`: undo delete (restore and focus restored row).
   - `⌘Y`: toggle in-app preview panel.
   - `Esc`: closes current panel (preview first, then overlay).

3. **Focus behavior**
   - Closing overlay should restore previous frontmost app.
   - Paste flow temporarily hides overlay, re-activates previous app, then sends `⌘V`.

4. **Search behavior**
   - Fuzzy search must be instant.
   - QMD keyword + semantic results augment fuzzy.
   - QMD keyword threshold: 3+ chars.
   - QMD semantic threshold: 3+ chars.

5. **Layout stability**
   - Avoid row height jitter / implicit list animation regressions.
   - Keep image previews visually balanced with metadata area.

## Known fragile areas

- **Keyboard monitors**: overlay and preview each use local key monitors. If you add/change shortcuts, ensure monitors do not conflict across hidden/visible panels.
- **Focus restoration**: changes to hide/show order can easily break app handoff.
- **QMD latency**: keep UI responsive by never blocking on QMD calls.

## Testing expectations

When touching search, keyboard handling, preview, or persistence:

1. Run unit tests: `swift test`
2. Manually verify:
   - open overlay, type search, arrow select, return paste
   - `⌘D` delete + `⌘Z` restore + restored-row selection
   - `⌘Y` open/close preview, `Esc` close preview
   - closing overlay returns focus to previous app

## Releases & packaging

- Build app bundle: `./scripts/build-app.sh <version>`
- Build DMG: `./scripts/build-dmg.sh <version>`
- Install locally: `./scripts/install.sh`
- Tag-based GitHub release workflow: `.github/workflows/release.yml`
  - Push tag `vX.Y.Z` to trigger DMG + checksum asset upload.

## Changelog policy

- Keep `CHANGELOG.md` updated.
- Add new changes under `## [Unreleased]`.
- Do not rewrite historical released sections.

## If you add/modify features

- Update tests under `Tests/CBManagerTests`.
- Keep `README.md` in sync with shortcuts/behavior.
- Keep `CHANGELOG.md` updated (Unreleased section).
- Prefer small, isolated changes to keyboard/focus code.

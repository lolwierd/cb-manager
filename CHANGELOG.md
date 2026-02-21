# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

## [0.4.0] - 2026-02-21

### Added

- **Open at Login** toggle in Settings → General (uses `SMAppService`).
- Existing clipboard entries are bumped to the top (with updated timestamp) when pasted or re-copied.

### Fixed

- Pasting an entry no longer re-captures it as a new clipboard item — the existing entry is moved to the top instead.
- Duplicate clipboard content detected anywhere in history (not just the latest entry) is moved to top rather than re-inserted.
- Overlay now opens instantly even when the previous session had a search query (stale query and filter are cleared on open).
- Search input is no longer sluggish: filtered results are now cached and recomputed once per change instead of 4× per render cycle.
- Removed expensive `filteredEntries.map(\.id)` comparison that ran on every SwiftUI body evaluation.
- QMD binary is now detected when installed via nvm/fnm (shell PATH resolution uses interactive login shell).
- Closing the preview panel no longer clears the active search query.

### Performance

- `searchableText` is now precomputed once at entry creation and cached, eliminating per-keystroke string allocations.
- Content truncated to 500 chars for fuzzy search indexing — matching deep into multi-MB entries was the main typing bottleneck.
- Query input debounced by 35ms so fast typing batches into a single search pass instead of one per keystroke.

## [0.3.0] - 2026-02-20

### Changed

- Clipboard history is now unlimited (removed the hard 300-entry cap). Entries accumulate indefinitely; use the auto-prune setting to manage size by age.

### Added

- Architecture documentation: `docs/architecture.html` — interactive visual explainer covering the full system.

## [0.2.0] - 2026-02-20

### Added

- AI-powered image titles: clipboard images now get automatic one-sentence descriptions generated via the `pi` CLI (default model: `openai-codex/gpt-5.1-codex-mini`).
- Settings screen accessible from the menu bar (⌘, or right-click → Settings…) with two sections: AI Image Titles and History auto-pruning.
- AI title shown in the image preview "Information" section alongside source, dimensions, and timestamp.
- AI titles are preferred over OCR text in the overlay list for cleaner, more descriptive image entries.
- AI titles are indexed by QMD for better search relevance on image entries.
- Auto-prune setting: optionally delete entries older than N days (default 90, off by default). Pruning runs on each app launch.
- `⌘,` opens settings from the overlay panel.
- `⌘W` closes the settings window.

### Changed

- Replaced SwiftUI `App`/`Scene` entry point with a pure AppKit `NSApplication` + `AppDelegate` bootstrap. Eliminates ghost settings window and SwiftUI scene conflicts for this menu-bar-only app.
- Image title fallback no longer shows OCR text — instead shows compact summary with dimensions and source app (e.g. "Image (1920×1080) · Preview").
- While AI title is generating, image entries show the compact summary instead of "generating title…".
- Moved entry type badge and timestamp from the preview pane header into the Information metadata section for a cleaner content-first preview layout.
- Renamed "Content type" to "Type" in the metadata section for brevity.

## [0.1.7] - 2026-02-20

### Changed

- Made search bar flush with the top of the overlay panel, removing the nested rounded-rect border for a cleaner Spotlight-like look.
- Bumped search icon (16pt) and text field (16pt) for a more confident search presence.
- Softened panel and preview border strokes (0.10 opacity, 0.5pt) for less visible chrome.
- Enabled native window shadow on the overlay panel for better depth and separation.

### Fixed

- `install.sh` now reliably kills a running CBManager instance before reinstalling, with graceful shutdown + force-kill fallback.

### Added

- Added overlay screenshot to README.

## [0.1.6] - 2026-02-20

### Changed

- Improved clipboard text classification so plain multiline text is less likely to be mislabeled as code.
- QMD bootstrap now skips writing documents that already exist on disk and skips `qmd update` when nothing changed, eliminating ~460ms of redundant I/O per launch.
- Shell PATH resolution for QMD now uses non-interactive login shell (`-lc` instead of `-ilc`), ~15× faster.
- Image thumbnails in the clipboard list now use `CGImageSource` to generate small thumbnails without decoding the full image, avoiding multi-MB PNG loads for 30×30 icons.
- Image dimensions in the preview metadata are now read from file headers via ImageIO instead of loading the full image.

### Fixed

- Fixed duplicate image capture handling to remove redundant image files and avoid extra storage growth.
- Improved duplicate image detection by short-circuiting on file-size mismatch before byte comparison.
- Fixed overlay list row interactions so double-click confirm works reliably alongside single-click selection.
- Hardened `qmd` execution by avoiding stdout pipe deadlocks and only marking collection setup as complete after success.

## [0.1.5] - 2026-02-20

### Added

- Added startup prewarming of the overlay panel to make first open feel instant.

### Changed

- Increased semantic QMD trigger threshold to 5+ characters to reduce noisy early semantic calls.
- Tuned deferred QMD search timing to prioritize responsive fuzzy results (`keyword`: 400ms, `semantic`: 1200ms).
- Updated preview details pane to scroll as a whole, keep shortcuts footer pinned, and improve image sizing balance.
- Simplified the filter control label in the search bar for cleaner header layout.

### Fixed

- Improved `qmd` binary discovery in GUI launches by resolving the login-shell `PATH` at runtime.
- Added cooperative cancellation for QMD subprocesses so cancelled searches terminate promptly.

## [0.1.4] - 2026-02-20

### Added

- Added release-note generation script from changelog sections: `scripts/release-notes-from-changelog.sh`.

### Changed

- Updated release workflow to publish changelog-derived release notes (`body_path`).
- Search bar now uses flush material styling for consistent light/dark appearance.
- QMD badge/spinner now appears only when `qmd` is available in `PATH`.
- Image preview now uses adaptive fixed bounds with `scaledToFit()` to avoid vertical oversizing and screenshot cropping.

## [0.1.3] - 2026-02-20

### Added

- Added release automation workflow for tag-based GitHub releases with DMG artifacts.
- Added packaging scripts for app bundle and DMG creation:
  - `scripts/build-app.sh`
  - `scripts/build-dmg.sh`
  - `scripts/generate-icon.sh`
- Added app icon generation and bundling (`Resources/AppIcon.icns`).
- Added README instructions for Gatekeeper quarantine removal (`xattr`) for unsigned builds.
- Added troubleshooting and release workflow documentation.

### Changed

- Updated release workflow to run on `macos-26` and pinned latest action versions.
- Raised project/package minimum target to macOS 26 (`swift-tools-version: 6.2`, `.macOS(.v26)`).
- Updated app bundle packaging scripts to set `LSMinimumSystemVersion` to `26.0`.
- Updated `scripts/install.sh` to reuse the shared app bundle build script.
- Status bar left-click now toggles overlay instead of only opening.
- Global shortcut persistence now uses app-support settings file to survive reinstall.

## [0.1.0] - 2026-02-20

### Added

- Initial public release of CBManager.
- Native macOS menu bar clipboard manager overlay.
- Global shortcut support and keyboard-first navigation.
- Persistent SQLite clipboard history.
- Image OCR indexing with on-device Vision.
- Fast fuzzy search augmented by QMD keyword + semantic retrieval.
- In-app preview toggle (`⌘Y`).
- Delete/undo workflow (`⌘D` / `⌘Z`).

[Unreleased]: https://github.com/lolwierd/cb-manager/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/lolwierd/cb-manager/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/lolwierd/cb-manager/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lolwierd/cb-manager/compare/v0.1.7...v0.2.0
[0.1.7]: https://github.com/lolwierd/cb-manager/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/lolwierd/cb-manager/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.5
[0.1.4]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.4
[0.1.3]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.3
[0.1.0]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.0

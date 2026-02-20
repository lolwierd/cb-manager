# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

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

[Unreleased]: https://github.com/lolwierd/cb-manager/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.5
[0.1.4]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.4
[0.1.3]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.3
[0.1.0]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.0

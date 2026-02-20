# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- Added release automation workflow for tag-based GitHub releases with DMG artifacts.
- Added packaging scripts for app bundle and DMG creation:
  - `scripts/build-app.sh`
  - `scripts/build-dmg.sh`
- Added README instructions for Gatekeeper quarantine removal (`xattr`) for unsigned builds.
- Added troubleshooting and release workflow documentation.

### Changed

- Updated `scripts/install.sh` to reuse the shared app bundle build script.

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

[Unreleased]: https://github.com/lolwierd/cb-manager/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lolwierd/cb-manager/releases/tag/v0.1.0

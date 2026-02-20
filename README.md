# CBManager

Native macOS menu bar clipboard manager with a Spotlight-style overlay.

> Minimum supported OS: **macOS 26**.

## Features

- Menu bar utility (no regular Dock app window)
- Global open shortcut (default: `⌘⇧V`, configurable)
- Captures clipboard history for text, links, code, paths, and images
- Fast search pipeline:
  1. instant fuzzy local ranking
  2. QMD keyword augmentation (`qmd search`)
  3. QMD semantic augmentation (`qmd vsearch`)
- Image OCR (Vision) for searchable image text
- In-app preview panel toggle with `⌘Y`

## Keyboard shortcuts

### Overlay

- `↑ / ↓` — move selection
- `Return` — paste selected entry into previous app
- `⌘Y` — open/close in-app preview for selected entry
- `⌘D` — delete selected entry
- `⌘Z` — undo delete
- `Esc` — close overlay

### Preview panel

- `⌘Y` — close preview
- `Esc` — close preview

## Development

```bash
swift build
swift test
swift run
```

Fast local reload script (build + kill old process + run):

```bash
./scripts/reload-dev.sh
```

Logs:

```bash
tail -f /tmp/cbmanager-dev.log
```

## Build, package, install

Build release app bundle into `dist/CBManager.app`:

```bash
./scripts/build-app.sh 1.0.0
```

Build DMG into `dist/CBManager-<version>.dmg`:

```bash
./scripts/build-dmg.sh 1.0.0
```

Install app to `/Applications`:

```bash
./scripts/install.sh
```

## Releases (GitHub)

This repo includes a GitHub Actions workflow: `.github/workflows/release.yml`.

- Trigger: push a tag like `v1.0.0`
- Workflow builds release DMG and uploads assets to the matching GitHub Release:
  - `CBManager-<version>.dmg`
  - `CBManager-<version>.dmg.sha256`

### Typical flow

```bash
git tag -a v1.0.0 -m "v1.0.0"
git push origin main --tags
```

If the release does not exist yet, create it first:

```bash
gh release create v1.0.0 --title "v1.0.0" --notes "See CHANGELOG.md"
```

## Gatekeeper / unsigned app note (`xattr`)

This project is unsigned (no paid Apple Developer cert/notarization).
Downloaded apps may be quarantined by macOS.

After dragging app to `/Applications`, clear quarantine:

```bash
xattr -dr com.apple.quarantine "/Applications/CBManager.app"
```

You can also right-click the app and choose **Open** once to allow launch.

## Data locations

- SQLite DB: `~/Library/Application Support/CBManager/clipboard.sqlite`
- Images: `~/Library/Application Support/CBManager/images/`
- QMD docs: `~/Library/Application Support/CBManager/qmd-docs/`

## QMD integration

Current usage:

- `qmd update` keeps index synced
- `qmd embed` runs in background to keep vectors fresh
- `qmd search` + `qmd vsearch` augment fuzzy results

QMD must be available in `PATH`.

## Troubleshooting

- **qmd not found**
  - Ensure `qmd` is installed and available: `which qmd`
- **Paste doesn’t work**
  - Grant Accessibility permission to app/terminal running CBManager
- **App won’t open after download**
  - Use the `xattr` command above to remove quarantine
- **Focus not returning to previous app**
  - Reopen once with global shortcut so previous-app reference is refreshed
- **Want a clean slate**
  - Quit app, then remove:
    - `~/Library/Application Support/CBManager/clipboard.sqlite`
    - `~/Library/Application Support/CBManager/images/`
    - `~/Library/Application Support/CBManager/qmd-docs/`

## Project docs

- Contributor/agent guidance: [`AGENTS.md`](./AGENTS.md)
- Release notes/history: [`CHANGELOG.md`](./CHANGELOG.md)

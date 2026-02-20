# CBManager

Native macOS menu bar clipboard manager with a Spotlight-style overlay.

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

## Install to /Applications (production-style)

Builds release binary, creates `CBManager.app`, installs to `/Applications`, then launches it:

```bash
./scripts/install.sh
```

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
- **Focus not returning to previous app**
  - Reopen once with global shortcut so previous-app reference is refreshed
- **Want a clean slate**
  - Quit app, then remove:
    - `~/Library/Application Support/CBManager/clipboard.sqlite`
    - `~/Library/Application Support/CBManager/images/`
    - `~/Library/Application Support/CBManager/qmd-docs/`

## Agent/contributor notes

See [`AGENTS.md`](./AGENTS.md) for architecture and invariants.

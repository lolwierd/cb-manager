#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version-without-v> [changelog-path] [output-path]}"
CHANGELOG_PATH="${2:-CHANGELOG.md}"
OUTPUT_PATH="${3:-/tmp/release-notes.md}"

if [[ ! -f "$CHANGELOG_PATH" ]]; then
  echo "Changelog not found: $CHANGELOG_PATH" >&2
  exit 1
fi

extract_section() {
  local section="$1"
  awk -v section="$section" '
    $0 ~ "^## \\[" section "\\]" {in_section=1; found=1; next}
    $0 ~ "^## \\[" && in_section {exit}
    in_section {print}
    END { if (!found) exit 1 }
  ' "$CHANGELOG_PATH"
}

notes=""
source_section="$VERSION"
if notes="$(extract_section "$VERSION" 2>/dev/null)"; then
  :
else
  source_section="Unreleased"
  notes="$(extract_section "Unreleased")"
fi

{
  echo "## v$VERSION"
  echo
  if [[ "$source_section" == "Unreleased" ]]; then
    echo "_Auto-generated from CHANGELOG Unreleased section._"
    echo
  fi
  echo "$notes"
} > "$OUTPUT_PATH"

echo "Generated release notes: $OUTPUT_PATH (from [$source_section])"

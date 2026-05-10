#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Generate OpenEmu app icon assets from a single square PNG.

Usage:
  Scripts/generate-appicon.sh /path/to/source.png [appiconset-path]

Arguments:
  source.png        Required. A square PNG (recommended 1024x1024 or larger).
  appiconset-path   Optional. Defaults to OpenEmu/Graphics.xcassets/OpenEmu.appiconset

Notes:
  - Generates both *-srgb.png and *-p3.png variants used by this project.
  - Existing icon files with matching names will be overwritten.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

SRC="$1"
DEST="${2:-OpenEmu/Graphics.xcassets/OpenEmu.appiconset}"

if [[ ! -f "$SRC" ]]; then
  echo "Source PNG not found: $SRC" >&2
  exit 1
fi

if [[ ! -d "$DEST" ]]; then
  echo "App iconset directory not found: $DEST" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "sips not found. This script requires macOS sips." >&2
  exit 1
fi

# Verify source is square.
WIDTH=$(sips -g pixelWidth "$SRC" 2>/dev/null | awk '/pixelWidth:/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelHeight:/ {print $2}')
if [[ -z "$WIDTH" || -z "$HEIGHT" || "$WIDTH" != "$HEIGHT" ]]; then
  echo "Source image must be square. Got ${WIDTH:-unknown}x${HEIGHT:-unknown}." >&2
  exit 1
fi

for size in 16 32 64 128 256 512 1024; do
  SRGB="$DEST/icon-${size}-srgb.png"
  P3="$DEST/icon-${size}-p3.png"

  sips -z "$size" "$size" "$SRC" --out "$SRGB" >/dev/null
  cp "$SRGB" "$P3"
done

echo "Generated app icons in: $DEST"

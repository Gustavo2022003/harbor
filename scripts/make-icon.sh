#!/bin/bash
# Regera Resources/AppIcon.icns a partir de scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swiftc -O scripts/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon_1024.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon_1024.png" docs/icon.png
rm -rf "$TMP"
echo "✅ Resources/AppIcon.icns"

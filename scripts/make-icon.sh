#!/bin/bash
# Regenerates Resources/AppIcon.icns from the design named in make-icon.swift.
# To compare all designs first: ./scripts/make-icon.sh preview
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
if [ "${1:-}" = "preview" ]; then
  cat scripts/IconDesigns.swift scripts/preview-icons.swift > "$tmp/main.swift"
  swift "$tmp/main.swift" "$tmp/icon-preview.png" && open -a Preview "$tmp/icon-preview.png"
else
  cat scripts/IconDesigns.swift scripts/make-icon.swift > "$tmp/main.swift"
  swift "$tmp/main.swift" Resources/AppIcon.icns
fi

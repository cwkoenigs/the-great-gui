#!/bin/sh
# Rebuild assets/AppIcon.icns (the app's icon) and assets/icon.png (the README's) from make-icon.swift.
# Only whoever changes the artwork runs this; scripts/bundle.sh copies the committed AppIcon.icns.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "${WORK:?}"' EXIT
swift "$HERE/make-icon.swift" "$WORK/1024.png"
SET="$WORK/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z "$d" "$d" "$WORK/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$HERE/AppIcon.icns"
sips -z 256 256 "$WORK/1024.png" --out "$HERE/icon.png" >/dev/null
echo "wrote $HERE/AppIcon.icns and $HERE/icon.png"

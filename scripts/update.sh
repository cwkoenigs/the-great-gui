#!/bin/sh
# Update this checkout: pull, rebuild the app and relink the command and the skills (make install), then quit
# and reopen the app if it was running. `make update` runs it; so does the app menu's Update…, in the embedded
# terminal, with GREAT_GUI_UPDATE_FROM_APP set: then the app reopens itself once this script exits 0, because an
# Apple event sent from inside the app's own shell does not reach it.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
APP="$ROOT/build/the-great-gui.app"
BIN="$APP/Contents/MacOS/the-great-gui"

was_running=0
# -a: count ancestors too; from the app's own terminal the app is one, and macOS pgrep skips them by default
if pgrep -af "$BIN" >/dev/null 2>&1; then was_running=1; fi

printf '› pull  %s\n' "$ROOT"
before="$(git rev-parse HEAD)"
if ! git fetch || ! python3 scripts/update_checkout.py; then
  printf '✗ update stopped · review the Git error in %s, then run Update again\n' "$ROOT" >&2
  exit 1
fi
after="$(git rev-parse HEAD)"
if [ "$before" = "$after" ]; then
  printf '  already at %s · rebuilding anyway\n' "$(git rev-parse --short HEAD)"
else
  git log --oneline "$before..$after" | sed 's/^/  /'
fi

printf '› build  %s\n' "$(git rev-parse --short HEAD)"
make install

if [ -n "${GREAT_GUI_UPDATE_FROM_APP:-}" ]; then
  printf '✓ updated to %s · the window closes and comes back on the new build\n' "$(git rev-parse --short HEAD)"
elif [ "$was_running" = 1 ]; then
  printf '› reopen\n'
  osascript -e 'tell application id "com.cwkoenigs.the-great-gui" to quit' >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -af "$BIN" >/dev/null 2>&1 || break; sleep 0.5; done
  if pgrep -af "$BIN" >/dev/null 2>&1; then pkill -af "$BIN" >/dev/null 2>&1 || true; sleep 1; fi
  open "$APP"
  printf '✓ updated to %s · reopened\n' "$(git rev-parse --short HEAD)"
else
  printf '✓ updated to %s · make run opens it\n' "$(git rev-parse --short HEAD)"
fi

#!/bin/sh
# Install the-great-gui on this Mac from source, with no Apple account: Apple's free command-line tools, a
# clone of the repository, a release build, `great-gui` in ~/.local/bin, the skills linked into whichever
# agents are here, the app linked into ~/Applications so Spotlight finds it, and a registry folder that is a
# git repository. Run it again any time: it pulls and rebuilds. Afterwards the app updates itself from its
# own menu (the-great-gui › Update…), so the terminal is needed once.
#
#   git clone ADDRESS ~/Developer/the-great-gui && ~/Developer/the-great-gui/scripts/install.sh
#
# ADDRESS is wherever you were told to get it: this script names no git host (DECISIONS local-034).
#
#   GREAT_GUI_HOME   where the checkout lives when this script is not run from one (~/Developer/the-great-gui)
#   GREAT_GUI_REPO   the address to clone when this script is not run from a checkout and none is there yet;
#                    HTTPS is the safer choice, because port 22 is often closed on office networks
#   GREAT_GUI_REGISTRY, GREAT_GUI_TEAM   honoured here as in the app, so a test install stays apart
#   GREAT_GUI_TEAM_REPO  the team's tooling repository, joined at the end when given (any git address);
#                    later: great-gui team join ADDRESS, or Settings › Team
set -e

say()  { printf '› %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# macOS 26 or newer
version="$(sw_vers -productVersion)"
major="${version%%.*}"
[ "$major" -ge 26 ] 2>/dev/null || fail "macOS 26 or newer is needed; this Mac runs $version"

# Apple's command-line tools (or Xcode): swift, git and make. Free; no Apple ID.
if ! xcode-select -p >/dev/null 2>&1; then
  say "tools  installing Apple's command-line tools · approve the dialog, then wait here"
  xcode-select --install >/dev/null 2>&1 || true
  # Twenty minutes, not for ever: the dialog may have been cancelled, or blocked by device management.
  waited=0
  until xcode-select -p >/dev/null 2>&1; do
    [ "$waited" -lt 1200 ] || fail "the command-line tools are still not installed · install them (xcode-select --install, or ask whoever manages this Mac), then run this again"
    sleep 5; waited=$((waited + 5))
  done
fi
command -v swift >/dev/null 2>&1 || fail "swift is not on PATH; open a new terminal and run this again"
ok "tools  $(swift --version 2>/dev/null | head -1 | sed 's/ (.*//')"

# the checkout: the one this script lives in, else GREAT_GUI_HOME, cloned when absent
here="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P || true)"
if [ -n "$here" ] && [ -f "$here/Package.swift" ] && [ -f "$here/Makefile" ] && [ -f "$here/scripts/install.sh" ]; then
  ROOT="$here"
else
  ROOT="${GREAT_GUI_HOME:-$HOME/Developer/the-great-gui}"
  REPO="${GREAT_GUI_REPO:-}"
  if [ ! -d "$ROOT/.git" ]; then
    [ -n "$REPO" ] || fail "nothing at $ROOT and no address to clone · run it as: GREAT_GUI_REPO=ADDRESS $0, with the address you were given"
    say "clone  $REPO → $ROOT"
    mkdir -p "$(dirname "$ROOT")"
    git clone "$REPO" "$ROOT" || fail "could not clone $REPO · check that you have read access to it and are signed in to that git host, then run this again"
  fi
fi
cd "$ROOT"
say "pull   $ROOT"
if ! pulled="$(git pull -q --ff-only 2>&1)"; then
  note "could not pull, so this builds what is here · git said: $(printf '%s' "$pulled" | tail -1)"
fi

# the design's typeface, through Homebrew when it is here; the app falls back to SF Mono without it
if command -v brew >/dev/null 2>&1; then
  if brew list --cask font-jetbrains-mono >/dev/null 2>&1; then
    ok "font   JetBrains Mono"
  else
    say "font   JetBrains Mono, through Homebrew"
    brew install --cask --quiet font-jetbrains-mono || note "the font did not install; the app uses SF Mono"
  fi
else
  note "no Homebrew, so the app uses SF Mono; for the design's face later: brew install --cask font-jetbrains-mono"
fi

# the app, the command, the skills, the Applications link
say "build  release · a minute or two the first time"
make install

# the registry folder as a git repository: every change made in the window becomes a commit, never pushed
REG="$HOME/.great-gui"
[ -z "${GREAT_GUI_REGISTRY:-}" ] || REG="$(dirname "$GREAT_GUI_REGISTRY")"
TEAM="${GREAT_GUI_TEAM:-$HOME/.great-gui-team}"
if [ ! -d "$REG/.git" ]; then
  mkdir -p "$REG"
  git -C "$REG" init -q
  ok "registry  $REG · the app writes an example commands.toml there on first launch"
fi

# the team's registry, when its address was given: shared commands and skills, followed daily, read-only here
if [ -n "${GREAT_GUI_TEAM_REPO:-}" ] && [ ! -e "$TEAM" ]; then
  say "team   $GREAT_GUI_TEAM_REPO"
  "$ROOT/bin/great-gui" team join "$GREAT_GUI_TEAM_REPO" || note "could not join the team registry; later: great-gui team join ADDRESS"
fi

# great-gui on PATH: the agents' skills call it by name. Asked, never assumed; one line in ~/.zprofile.
line='export PATH="$HOME/.local/bin:$PATH"'
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    if grep -qsF "$line" "$HOME/.zprofile"; then
      note "great-gui is in ~/.local/bin, which ~/.zprofile already adds to PATH · open a new terminal"
    elif [ -t 0 ]; then
      printf '? ~/.local/bin is not on PATH, so great-gui is not found in a terminal. Add it in ~/.zprofile? [y/N] '
      read -r answer
      case "$answer" in
        y|Y|yes) printf '\n# the-great-gui: the great-gui command\n%s\n' "$line" >> "$HOME/.zprofile"; ok "path   added to ~/.zprofile · open a new terminal" ;;
        *) note "not added · for the great-gui command, add to your shell profile:  $line" ;;
      esac
    else
      note "for the great-gui command in a terminal, add to your shell profile:  $line"
    fi ;;
esac

ok "installed · open the-great-gui from Spotlight · it updates itself from its menu (Update…)"
open "$ROOT/build/the-great-gui.app"

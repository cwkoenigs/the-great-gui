#!/bin/sh
# Copy this checkout's history to a second git host, so teammates who cannot (or should not) reach the
# repository it came from install and update from their own. It pulls from where this checkout came from,
# then pushes the same branch and tags to the mirror. Nothing is rewritten: a push that is not a
# fast-forward is refused by git and reported.
#
#   scripts/mirror.sh ADDRESS   the first time: remembers ADDRESS as the remote named "mirror", then pushes
#   scripts/mirror.sh           afterwards: pull, then push to the remembered mirror
#   scripts/mirror.sh --where   print the mirror's address and whether it is behind; changes nothing
#
# The address is kept only in this checkout's git config. No host is named anywhere in the app.
set -e

say()  { printf '› %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."
git rev-parse --git-dir >/dev/null 2>&1 || fail "this folder is not a git checkout"
branch="$(git symbolic-ref --quiet --short HEAD)" || fail "this checkout is on no branch"
have="$(git remote get-url mirror 2>/dev/null || true)"

if [ "$1" = "--where" ]; then
  [ -n "$have" ] || fail "no mirror yet · scripts/mirror.sh ADDRESS sets one"
  echo "$have"
  theirs="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$have" "refs/heads/$branch" 2>/dev/null | cut -f1)"
  if [ -z "$theirs" ]; then note "could not read $branch there (no access, or never pushed)"
  elif [ "$theirs" = "$(git rev-parse HEAD)" ]; then note "it has what this checkout has"
  else note "it differs from this checkout · scripts/mirror.sh brings it up"; fi
  exit 0
fi

case "$1" in -*) fail "unknown option $1 · scripts/mirror.sh [ADDRESS | --where]";; esac
if [ -n "$1" ]; then
  [ "$1" != "$(git remote get-url origin 2>/dev/null || true)" ] || fail "that is where this checkout already comes from"
  if [ -n "$have" ]; then git remote set-url mirror "$1"; else git remote add mirror "$1"; fi
  have="$1"
fi
[ -n "$have" ] || fail "no mirror yet · scripts/mirror.sh ADDRESS (an empty repository you created on your git host)"

# what is here must be committed: a mirror of half a change helps nobody
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "this checkout has uncommitted changes; commit or stash them first"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  say "pull   from $(git remote get-url origin 2>/dev/null || echo 'its remote')"
  git pull -q --ff-only || note "could not fast-forward; mirroring what is here"
fi

say "push   $branch and tags → $have"
git push -q mirror "$branch" --tags || fail "the push was refused · check that the repository exists there, that you may write to it, and that nobody pushed to it directly"
ok "mirror $(git rev-parse --short HEAD) · $(git log -1 --format=%s | cut -c1-60)"
note "a teammate installs with:"
note "git clone $have ~/Developer/the-great-gui && ~/Developer/the-great-gui/scripts/install.sh"

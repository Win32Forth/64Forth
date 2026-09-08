#!/bin/bash
# sync-shipped.sh — Documents/64Forth ↔ Xcode Resources for Library + AutoLoad.
#
# Preferred setup (default after `link`):
#   Documents/64Forth/{Library,AutoLoad}  →  symlinks to
#   XCodeProjects/64Forth/64Forth/Resources/{Library,AutoLoad}
# So the project and the running app share one tree. Edit either path.
#
# Usage:
#   ./sync-shipped.sh status
#   ./sync-shipped.sh link      # (re)create symlinks LIVE → SHIP
#   ./sync-shipped.sh push      # copy LIVE → SHIP (no-op if already linked)
#   ./sync-shipped.sh restore   # copy SHIP → LIVE (no-op if already linked)
set -euo pipefail

LIVE="/Users/thomaszimmer/Documents/64Forth"
SHIP="/Users/thomaszimmer/Documents/XCodeProjects/64Forth/64Forth/Resources"

is_linked() {
  local name="$1"
  [ -L "$LIVE/$name" ] || return 1
  local target
  target=$(readlink "$LIVE/$name")
  [ "$target" = "$SHIP/$name" ]
}

push_one() {
  local name="$1"
  if is_linked "$name"; then
    echo "OK  $name already linked LIVE → SHIP (push not needed)"
    return 0
  fi
  mkdir -p "$SHIP/$name"
  ditto --norsrc "$LIVE/$name" "$SHIP/$name"
  echo "Pushed $name: LIVE → SHIP"
}

restore_one() {
  local name="$1"
  if is_linked "$name"; then
    echo "OK  $name already linked LIVE → SHIP (restore not needed)"
    return 0
  fi
  mkdir -p "$LIVE/$name"
  ditto --norsrc "$SHIP/$name" "$LIVE/$name"
  echo "Restored $name: SHIP → LIVE"
}

link_one() {
  local name="$1"
  local dest="$LIVE/$name"
  mkdir -p "$SHIP/$name"
  if is_linked "$name"; then
    echo "OK  $name already linked → $SHIP/$name"
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local ts bak
    ts=$(date +%Y%m%d-%H%M%S)
    bak="$LIVE/${name}.pre-link-$ts"
    # Preserve any LIVE-only content into SHIP before replacing
    if [ -d "$dest" ] && [ ! -L "$dest" ]; then
      ditto --norsrc "$dest" "$SHIP/$name"
    fi
    mv "$dest" "$bak"
    echo "Backed up $dest → $bak"
  fi
  ln -s "$SHIP/$name" "$dest"
  echo "Linked $name → $SHIP/$name"
}

status_one() {
  local name="$1"
  if is_linked "$name"; then
    echo "LINK $name → $SHIP/$name"
    return 0
  fi
  if [ ! -e "$LIVE/$name" ]; then
    echo "MISSING LIVE $name"
    return 0
  fi
  if diff -qr "$LIVE/$name" "$SHIP/$name" >/dev/null 2>&1; then
    echo "COPY $name (LIVE == SHIP, not linked)"
  else
    echo "DIFF $name (separate trees)"
    diff -qr "$LIVE/$name" "$SHIP/$name" 2>/dev/null | head -40 || true
  fi
}

cmd="${1:-status}"
case "$cmd" in
  push)
    push_one Library
    push_one AutoLoad
    ;;
  restore)
    restore_one Library
    restore_one AutoLoad
    ;;
  link)
    mkdir -p "$LIVE"
    link_one Library
    link_one AutoLoad
    ;;
  status)
    status_one Library
    status_one AutoLoad
    ;;
  *)
    echo "Usage: $0 {status|link|push|restore}" >&2
    exit 2
    ;;
esac

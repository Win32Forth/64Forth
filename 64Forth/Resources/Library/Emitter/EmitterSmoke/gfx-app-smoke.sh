#!/bin/sh
# Phase 2b.3: package gfx.img as Gfx.app and run headless.
# Lives under Library/Emitter/EmitterSmoke.
set -e
SMOKE="$(cd "$(dirname "$0")" && pwd)"
EMITTER="$(cd "$SMOKE/.." && pwd)"
IMG="$SMOKE/gfx.img"
OUT="$SMOKE"
if [ ! -f "$IMG" ]; then
  echo "gfx-app-smoke: missing $IMG (run persist-save-gfx.fth first)" >&2
  exit 1
fi
"$EMITTER/app-build.sh" Gfx "$IMG" "$OUT"
APP="$OUT/Gfx.app"
echo "=== headless MacOS binary (bundle default app.img) ==="
EMIT_HEADLESS=1 "$APP/Contents/MacOS/Gfx"
echo "gfx-app-smoke: OK"

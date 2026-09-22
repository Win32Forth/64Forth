Emitter stand-alone runner (emit-run)
====================================

What this folder is
-------------------
Thin AppKit host that loads a 64EMIT02 image, binds HOST-APP slots, and
runs the ITC. `app-build.sh` copies `emit-run` into MacOS/<AppName> inside
each emitted .app.

Files
-----
  emit-run.m      main / image load / ITC (tracked)
  emit-host.inc   host_app_* slot implementations (tracked)
  emit-bi.inc     big-integer helpers used by host slots (tracked)
  build-run.sh    builds ./emit-run
  emit-run        built binary — gitignored (do not commit)

Rebuild
-------
The binary is not in git. After pulling, or after changing emit-host.inc /
HOST-APP slots (reloc.fth #HOST-APP, new (APP-*) words), rebuild before
EMIT-WINDOW-APP or app-build.sh:

  ./build-run.sh

from this directory (needs cc + AppKit). An stale emit-run means new
slots are missing at launch (e.g. (APP-FILE-*) / (APP-IMG-*)).

Manual test
-----------
  ./emit-run [--headless] /path/to/64EMIT02.img

See also ../APPKIT.md (and Resources/Docs/APPKIT.md — keep copies in sync).

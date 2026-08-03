64Forth tools
=============

build_hyper_index.py
--------------------
  Offline hypertext index builder (Phase 1).

  Reads:  64Forth/Resources/Config/HYPER.CFG
  Writes: 64Forth/Resources/Config/HYPER.NDX

  From the repository root:

    python3 tools/build_hyper_index.py
    python3 tools/build_hyper_index.py -q
    python3 tools/build_hyper_index.py --help

  Requires Python 3.9+ (stdlib only).

  SPECS paths in HYPER.CFG are relative to --src-root (default: ./64Forth).
  BOOT_WORD entries are mapped to Kernel/forth.s code labels when present.

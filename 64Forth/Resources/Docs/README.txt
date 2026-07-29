64Forth — Swift host + PickleForth ARM64 kernel
================================================

Version 0.6.0 (2026-07-29)

Hybrid macOS app: ARM64 ITC kernel (assembly) + SwiftUI console/host
(TZForth-style FileHost, AutoLoad, Library, FROMLIB).

Quick start (in the console)
----------------------------
  FROMLIB FLOAD BigInteger/big-int.fth
  FROMLIB FLOAD PI/pi-test.fth
  FROMLIB FLOAD HayesTest/HayesTest.fth

  ALSO FP          \ floating-point word set (vocabulary FP)
  1.5e0 2e0 F+ F.

ANS word sets (v0.6)
--------------------
  Core / Core Ext, Double, String, Exception, File-Access, Locals,
  Memory-Allocation, Programming-Tools, Search-Order, Facility,
  Block (file volume via OPEN-BLOCK-FILE; Harness/prepare-blocks),
  Floating-point (VOCABULARY FP; host FloatHost IEEE-64 stack).

Hayes suite
-----------
  FROMLIB FLOAD HayesTest/HayesTest.fth
  (driver: src/Harness/prepare-blocks.fth + src/Harness/runfptests.fth;
   stock tests under src/ and src/fp/)
  Expect: all *ERRORS counters 0, "FP tests finished", paranoia Excellent,
  "=== 64Forth Hayes subset complete ==="

Still optional / not full TZForth parity
----------------------------------------
  Extended Character (XChar), SZ-EDITOR productization,
  line-at-a-time INCLUDE via fileid, App Sandbox for store builds.

See DESIGN.md and README.md in the project root.

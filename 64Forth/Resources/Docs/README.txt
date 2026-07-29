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

  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth

ANS word sets (v0.6)
--------------------
  Core / Core Ext, Double, String (+ String Ext), Exception, File-Access,
  Locals (+ (LOCAL) / LOCALS|), Memory-Allocation, Programming-Tools,
  Search-Order, Facility + Facility Ext (structures, EKEY>FKEY, K-*),
  Block (file volume; LOAD restores BLK), Floating-point (VOCABULARY FP),
  Extended Character (UTF-8 XChar in kernel).

  ENVIRONMENT? reports presence and selected parameters (value then true for
  boolean word-set queries), including FACILITY-EXT. This is not a formal
  ANS System certificate.

Library paths
-------------
  Project sources: 64Forth/Resources/Library/ — copied into the app bundle on
  build. FROMLIB always resolves under Contents/Resources/Library/, independent
  of session cwd. Rebuild after editing Library .fth files.

Hayes suite
-----------
  FROMLIB FLOAD HayesTest/HayesTest.fth
  (driver: src/Harness/prepare-blocks.fth + src/Harness/runfptests.fth;
   stock tests under src/ and src/fp/)
  Expect: all *ERRORS counters 0, "FP tests finished", paranoia Excellent,
  "=== 64Forth Hayes subset complete ==="

ANS-VALIDATE - Library Forth spot-checks
----------------------------------------
  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
  Modules: tester, core, core-ext, search, string, facility, exception,
  memory, double, locals, tools, file, block, xchar, float.
  Expect: ANS-VALIDATE: N passed, 0 failed. ALL PASS  (about 351 / 0)

Still optional / not full TZForth parity
----------------------------------------
  SZ-EDITOR productization, line-at-a-time INCLUDE via fileid,
  App Sandbox for store builds.

See DESIGN.md and README.md in the project root.
  Also ANS_COMPLIANCE.rtf and THROW_CODES.rtf in this Docs folder.

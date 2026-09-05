64Forth Library — sources under 64Forth/Resources/Library/

Build (TZForth-style Run Script "Copy Library") wipes and re-copies this
folder into the app bundle as Contents/Resources/Library/ on every build
so FROMLIB never sees a stale tree. Same for AutoLoad and Docs.

FROMLIB resolves relative paths under the bundle Library - no machine-specific
absolute paths.

Examples
--------
  FROMLIB FLOAD HayesTest/HayesTest.fth
  FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
  FROMLIB FLOAD BigInteger/big-int.fth
  FROMLIB FLOAD PI/pi-test.fth
  FROMLIB FLOAD xchar-smoke.fth
  FROMLIB FLOAD Editor/SZ-EDITOR.fth
  FROMLIB SZEDIT Editor/SZ-EDITOR-README.txt
  FROMLIB FLOAD Assembler/asmarm64.fth     \ AArch64 host toolkit (not used by TCOM)
  FROMLIB FLOAD Assembler/ASSEMBLER.fth    \ interactive CODE / END-CODE (64Forth only)
  FROMLIB FLOAD Assembler/ASMARMTESTS.fth \ then: ASM-TESTS
  FROMLIB FLOAD Emitter/emitter.fth        \ turnkey slicer (IN PROGRESS)

Assembler (ASMARM64)
--------------------
  Full source: Library/Assembler/asmarm64.fth
  Interactive: Library/Assembler/ASSEMBLER.fth  →  CODE / END-CODE / C; / NEXT,
               (64Forth ITC only; not loaded by 64TCOM; does not redefine ASSEMBLER)
  Tests:       Library/Assembler/ASMARMTESTS.fth  →  ASM-TESTS
  Twin copies: Documents/64TCOM/64TCOMARM64/ASMARM64.fth + ASMARMTESTS.fth
  Last synced: Aug 23, 2026 3:16 PM (see header stamp in both .fth files)
  TCOM loads only the pack assembler via TARGETARM64.
  Monitor: Docs/STATUSASM64.md (twin of 64TCOM/STATUSASM64.md)
  After load: .ASMARM64  ASM-TESTS  ASMARM64-DISCARD
  CODE words:  FROMLIB FLOAD Assembler/ASSEMBLER.fth  then  CODE name … END-CODE

Emitter (IN PROGRESS)
---------------------
  Experimental space-optimizing / turnkey slicer toward stand-alone apps.
  Load:   FROMLIB FLOAD Emitter/emitter.fth
  Pieces: reach.fth (reachable xts), target.fth (target image),
          reloc.fth (PC-rel retarget / veneers), run.fth (trampoline + CALL-NATIVE)
  Kernel CODE words carry _END labels so primitive sizes can be measured for copy.
  Not finished — do not treat as a shipping compiler yet.
  Status: Docs/STATUS.md § v1.3.2

User data (Documents/64Forth)
-----------------------------
  First launch copies Library / AutoLoad / Docs into Documents/64Forth.
  FROMLIB prefers that tree. Tools menu: Update User Data / Restore Shipped Files.

After editing Library .fth files, rebuild/run so the bundle copy updates
(or use Tools → Update / Restore for the Documents/64Forth tree).

See ANSValidate/README.txt, Editor/SZ-EDITOR-README.txt, and Docs/README.txt.

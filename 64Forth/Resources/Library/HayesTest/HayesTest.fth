\ HayesTest.fth — 64Forth in-app Hayes / forth2012 driver
\
\ Canonical run:
\   FROMLIB FLOAD HayesTest/HayesTest.fth
\
\ Named FLOAD chdirs to this file's folder (HayesTest/), so nested loads
\ use bare subpaths under that folder (src/…).
\
\ 64Forth notes (vs full TZForth baseline):
\   - No floating-point engine → FP suite is skipped (fperrors left 0 with message).
\   - No File-Access / block-file volume yet → prepare-blocks is best-effort;
\     blocktest may report errors until host block files exist.
\   - Pass criteria for this port: core/double/string/search/facility counters
\     at 0; ignore FPERRORS unless you add FP later.
\
\ Full suite source remains under src/ for comparison with HAYES-RESULTS.txt.

FLOAD src/debug-bootstrap.fth
TRUE VERBOSE !

\ Optional block volume prep (no-op / soft fail without OPEN-BLOCK-FILE)
\ Note: .( parses to the first ')' only — do not nest parentheses in the text.
[UNDEFINED] OPEN-BLOCK-FILE [IF]
  .( prepare-blocks: skipped - no OPEN-BLOCK-FILE ) CR
[ELSE]
  FLOAD src/prepare-blocks.fth
[THEN]

VARIABLE cperrors  0 #ERRORS ! fload src/coreplustest.fth  .( #ERRORS @ = ) #ERRORS @  cperrors !
VARIABLE cerrors  0 #ERRORS ! fload src/coreexttest.fth .( #ERRORS @ = ) #ERRORS @  cerrors !
VARIABLE derrors  0 #ERRORS ! fload src/doubletest.fth .( #ERRORS @ = ) #ERRORS @  derrors !
VARIABLE eerrors  0 #ERRORS ! fload src/exceptiontest.fth .( #ERRORS @ = ) #ERRORS @  eerrors !

VARIABLE ferrors  0 #ERRORS ! fload src/filetest.fth .( #ERRORS @ = ) #ERRORS @  ferrors !

VARIABLE lerrors  0 #ERRORS ! fload src/localstest.fth .( #ERRORS @ = ) #ERRORS @  lerrors !
VARIABLE merrors  0 #ERRORS ! fload src/memorytest.fth .( #ERRORS @ = ) #ERRORS @  merrors !
VARIABLE terrors  0 #ERRORS ! fload src/toolstest.fth .( #ERRORS @ = ) #ERRORS @  terrors !
VARIABLE soerrors  0 #ERRORS ! fload src/searchordertest.fth .( #ERRORS @ = ) #ERRORS @  soerrors !
VARIABLE serrors  0 #ERRORS ! fload src/stringtest.fth .( #ERRORS @ = ) #ERRORS @  serrors !
VARIABLE faerrors  0 #ERRORS ! fload src/facilitytest.fth .( #ERRORS @ = ) #ERRORS @  faerrors !

[UNDEFINED] OPEN-BLOCK-FILE [IF]
  VARIABLE berrors  0 berrors !
  .( blocktest: skipped - no block-file host ) CR
[ELSE]
  VARIABLE berrors  0 #ERRORS ! fload src/blocktest.fth .( #ERRORS @ = ) #ERRORS @  berrors !
[THEN]

\ FP not implemented in 64Forth kernel
VARIABLE fperrors  0 fperrors !
.( fp/runfptests: skipped - no floating-point ) CR

.( CPERRORS @ = ) cperrors @ .
.( CERRORS @ = ) cerrors @ .
.( DERRORS @ = ) derrors @ .
.( EERRORS @ = ) eerrors @ .
.( FERRORS @ = ) ferrors @ .
.( LERRORS @ = ) lerrors @ .
.( MERRORS @ = ) merrors @ .
.( TERRORS @ = ) terrors @ .
.( SOERRORS @ = ) soerrors @ .
.( SERRORS @ = ) serrors @ .
.( FAERRORS @ = ) faerrors @ .
.( BERRORS @ = ) berrors @ .
.( FPERRORS @ = ) fperrors @ .
.( #ERRORS @ = ) #ERRORS @ .
CR .( === 64Forth Hayes subset complete ===) CR

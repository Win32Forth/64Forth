\ HayesTest.fth — 64Forth in-app Hayes / forth2012 driver
\
\ Canonical run:
\   FROMLIB FLOAD HayesTest/HayesTest.fth
\
\ INCLUDED pushes load-cwd to this file's folder for the duration of the load,
\ so nested FLOAD src/… and FLOAD prelimtest.fth inside src/ resolve correctly.
\ FILE-ECHO ON is fine for debugging but is not required.
\
\ 64Forth notes:
\   - Floating-point words live in vocabulary FLOATING. The harness does
\     ONLY FORTH ALSO FLOATING (searchordertest can leave a weird order).
\   - FP *tests* live in src/fp/; the FP *driver* is src/Harness/runfptests.fth
\
\ Full suite source remains under src/ for comparison with HAYES-RESULTS.txt.

\ Cleaner transcripts: FILE-ECHO ON dumps every source line (and ERROR + SOURCE
\ TYPE would re-dump whole INCLUDE buffers). Leave OFF unless debugging.

FLOAD src/debug-bootstrap.fth
TRUE VERBOSE !

\ Optional block volume prep (no-op / soft fail without OPEN-BLOCK-FILE)
\ Note: .( parses to the first ')' only — do not nest parentheses in the text.
[UNDEFINED] OPEN-BLOCK-FILE [IF]
  .( prepare-blocks: skipped - no OPEN-BLOCK-FILE ) CR
[ELSE]
  FLOAD src/Harness/prepare-blocks.fth
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

VARIABLE fperrors  0 fperrors !
0 #ERRORS !
FLOAD src/Harness/runfptests.fth
#ERRORS @ fperrors !
PREVIOUS

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
CR
\ Sum of per-suite counters (each file resets #ERRORS before its run).
cperrors @ cerrors @ + derrors @ + eerrors @ + ferrors @ +
lerrors @ + merrors @ + terrors @ + soerrors @ + serrors @ +
faerrors @ + berrors @ + fperrors @ +
?DUP
[IF]
  .( *** HAYES: ) . .(  FAILURES DETECTED — search log for HAYES FAIL *** ) CR
[ELSE]
  .( *** HAYES: ALL COUNTS ZERO — PASS *** ) CR
[THEN]
CR .( === 64Forth Hayes subset complete ===) CR

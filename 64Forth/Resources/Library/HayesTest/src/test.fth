\ TZForth Hayes / forth2012-test-suite driver (full word sets + fp/ suite).
\
\ Preferred (app-bundled Library — no CHDIR required):
\   FROMLIB FLOAD HayesTest/HayesTest.fth
\     → loads this file via Resources/Library/HayesTest/src/test.fth
\
\ Manual (cwd = this folder):
\   FROMLIB CHDIR HayesTest/src   \ or CHDIR after VIEW-LIBRARY
\   FLOAD test
\
\ Pass criteria:
\   - Each per-suite line shows #ERRORS @ = 0
\   - Final summary: CPERRORS … FPERRORS @ = 0 and #ERRORS @ = 0
\   - FP paranoia ends with "Excellent!" and "END OF TEST."
\   - Console ends with: File-echo on, then \s, then OK
\
\ Results baseline: HAYES-RESULTS.txt (this folder).
\ Note: HAYES=1 swift … (TestTZForth.swift) runs a smaller non-FP subset;
\ this file is the canonical full-suite driver for in-app validation.

fload debug-bootstrap.fth
TRUE VERBOSE !
VARIABLE cperrors  0 #ERRORS ! fload coreplustest.fth  .( #ERRORS @ = ) #ERRORS @  cperrors !
VARIABLE cerrors  0 #ERRORS ! fload coreexttest.fth .( #ERRORS @ = ) #ERRORS @  cerrors !
VARIABLE derrors  0 #ERRORS ! fload doubletest.fth .( #ERRORS @ = ) #ERRORS @  derrors !
VARIABLE eerrors  0 #ERRORS ! fload exceptiontest.fth .( #ERRORS @ = ) #ERRORS @  eerrors !
VARIABLE ferrors  0 #ERRORS ! fload filetest.fth .( #ERRORS @ = ) #ERRORS @  ferrors !
VARIABLE lerrors  0 #ERRORS ! fload localstest.fth .( #ERRORS @ = ) #ERRORS @  lerrors !
VARIABLE merrors  0 #ERRORS ! fload memorytest.fth .( #ERRORS @ = ) #ERRORS @  merrors !
VARIABLE terrors  0 #ERRORS ! fload toolstest.fth .( #ERRORS @ = ) #ERRORS @  terrors !
VARIABLE soerrors  0 #ERRORS ! fload searchordertest.fth .( #ERRORS @ = ) #ERRORS @  soerrors !
VARIABLE serrors  0 #ERRORS ! fload stringtest.fth .( #ERRORS @ = ) #ERRORS @  serrors !
VARIABLE faerrors  0 #ERRORS ! fload facilitytest.fth .( #ERRORS @ = ) #ERRORS @  faerrors !
VARIABLE berrors  0 #ERRORS ! fload blocktest.fth .( #ERRORS @ = ) #ERRORS @  berrors !
VARIABLE fperrors  0 #ERRORS ! fload fp/runfptests.fth .( #ERRORS @ = ) #ERRORS @  fperrors !

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
 
File-echo on
 
\s
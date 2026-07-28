\ One-shot Hayes harness bootstrap for TZForth UI console.
\ 1) bare FLOAD or CHDIR to this folder in the UI (pick any file here once)
\ 2) FLOAD debug-bootstrap.fth

FILE-ECHO OFF
.( debug-bootstrap: loading Hayes harness... ) CR
FLOAD prelimtest.fth
FLOAD tester.fr
FLOAD core.fr
FLOAD utilities.fth
FLOAD errorreport.fth
.( debug-bootstrap ready — try: T{ 1 2 + -> 3 }T  then  #ERRORS @ . ) CR
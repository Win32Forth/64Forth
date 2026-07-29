\ xchar-smoke.fth — alias for ANSValidate XChar module
FILE-ECHO OFF
DECIMAL
FROMLIB FLOAD ANSValidate/tester.fth
FROMLIB FLOAD ANSValidate/xchar.fth
S" XChar smoke" .TEST-SUMMARY

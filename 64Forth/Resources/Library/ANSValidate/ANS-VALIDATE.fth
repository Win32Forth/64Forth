\ ANS-VALIDATE.fth — 64Forth Library validation driver (pure Forth)
\
\ Port of TZForth ANS-VALIDATE / FTEST spot-checks, one word set at a time.
\ Not a formal ANS certificate. Hayes stock suites stay under HayesTest/.
\
\ Canonical run - same pattern as HayesTest (bundle Resources/Library):
\   FROMLIB FLOAD ANSValidate/ANS-VALIDATE.fth
\
\ Named FLOAD/INCLUDE chdirs to this file's folder - ANSValidate/ - for the
\ duration of its SOURCE, so nested FLOAD of sibling modules needs no absolute
\ path and works in Debug or Release after an Xcode build copies Library/.
\
\ Modules - load order:
\   1) tester.fth     harness
\   2) core.fth       Core
\   3) core-ext.fth   Core Ext
\   4) search.fth     Search-Order
\   5) string.fth     String
\   6) facility.fth   Facility structures
\   7) exception.fth  Exception CATCH/THROW
\   8) memory.fth     Memory-Allocation
\   9) double.fth     Double-Number
\  10) locals.fth     Locals
\  11) tools.fth      Programming-Tools
\  12) file.fth       File-Access
\  13) block.fth      Block
\  14) xchar.fth      Extended Character
\  15) float.fth      Float Tier A/B
\  16) host.fth       TZForth FTEST high-ROI port wave (FIND, POSTPONE, …)
\
\ CRITICAL: no interpret-time IF/ELSE/THEN/BEGIN.
\ CRITICAL: .( stops at first ) — no nested parentheses in messages.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === 64Forth ANS-VALIDATE ===) CR
CR .( Library Forth - not a formal ANS certificate.) CR
CR .( Modules: tester, core, core-ext, search, string, facility, exception, memory, double, locals, tools, file, block, xchar, float, host ) CR

\ Relative to this file's directory - ANSValidate/ under Resources/Library.
\ FILE-ECHO ON
FLOAD tester.fth
FLOAD core.fth
FLOAD core-ext.fth
FLOAD search.fth
FLOAD string.fth
FLOAD facility.fth
FLOAD exception.fth
FLOAD memory.fth
FLOAD double.fth
FLOAD locals.fth
FLOAD tools.fth
FLOAD file.fth
FLOAD block.fth
FLOAD xchar.fth
FLOAD float.fth
FLOAD host.fth

S" ANS-VALIDATE" .TEST-SUMMARY
.( === ANS-VALIDATE driver done ===) .STACK-DEPTH CR
\ Leave a clean data stack for subsequent work (e.g. Hayes).
EMPTY-DATA

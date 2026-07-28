\ TZForth runner for the Hayes / forth2012-test-suite
\ Omits word sets TZForth does not implement (Block).

CR .( Running ANS Forth tests for TZForth ) CR

S" prelimtest.fth" INCLUDED
S" tester.fr" INCLUDED

S" core.fr" INCLUDED
S" coreplustest.fth" INCLUDED
S" utilities.fth" INCLUDED
S" errorreport.fth" INCLUDED
S" coreexttest.fth" INCLUDED
S" blocktest.fth" INCLUDED
S" doubletest.fth" INCLUDED
S" exceptiontest.fth" INCLUDED
S" facilitytest.fth" INCLUDED
S" filetest.fth" INCLUDED
S" localstest.fth" INCLUDED
S" memorytest.fth" INCLUDED
S" toolstest.fth" INCLUDED
S" searchordertest.fth" INCLUDED
S" stringtest.fth" INCLUDED
REPORT-ERRORS

CR .( TZForth Hayes tests completed ) CR CR
\ To run Floating Point tests (64Forth driver)
\
\ Loaded from HayesTest.fth with ALSO FP and cwd = this fp/ folder.
\ Prefer FLOAD (named file) over S" … INCLUDED for clearer host paths.

CR .( Running FP Tests) CR

0 WARNING !

\ Ensure [UNDEFINED] exists (kernel has it; this is a portable fallback)
[UNDEFINED] [UNDEFINED] [IF]
  : [UNDEFINED]  ( "name" -- flag )  BL WORD FIND NIP 0= ; IMMEDIATE
[THEN]

\ ttester.fs provides T{ }T with floating-stack awareness (ERROR-XT, etc.)
[UNDEFINED] ERROR-XT [IF]
  .( FP: loading ttester.fs ) CR
  FLOAD ttester.fs
[ELSE]
  .( FP: ttester already present ) CR
[THEN]

.( FP: fatan2-test.fs ) CR
FLOAD fatan2-test.fs
.( FP: ieee-arith-test.fs ) CR
FLOAD ieee-arith-test.fs
.( FP: ieee-fprox-test.fs ) CR
FLOAD ieee-fprox-test.fs
.( FP: fpzero-test.4th ) CR
FLOAD fpzero-test.4th
.( FP: fpio-test.4th ) CR
FLOAD fpio-test.4th
.( FP: to-float-test.4th ) CR
FLOAD to-float-test.4th

\ Drain any floats left on the F stack before paranoia / ak-fp.
: ZAP-FPSTACK  BEGIN FDEPTH WHILE FDROP REPEAT ;
ZAP-FPSTACK

\ paranoia needs engine F= (IEEE equality); ak-fp-test.fth redefines F= as bitwise F~.
: TRY-PARANOIA
  S" paranoia.4th" ['] INCLUDED CATCH DUP IF
    CR .( FP: paranoia skipped, throw code ) . CR
  ELSE DROP THEN ;
TRY-PARANOIA

ZAP-FPSTACK
.( FP: ak-fp-test.fth ) CR
FLOAD ak-fp-test.fth

-1 WARNING !

CR CR
.( FP tests finished) CR CR

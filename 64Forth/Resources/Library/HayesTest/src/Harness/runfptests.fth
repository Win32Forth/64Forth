\ runfptests.fth — 64Forth / vendor FP suite driver (HARNESs, not a test)
\
\ Location: HayesTest/src/Harness/   (kept out of fp/ so suite sources stay clean)
\ Actual FP tests live in:          HayesTest/src/fp/
\
\ Loaded from HayesTest.fth with ALSO FP. Named FLOAD sets cwd to this
\ Harness/ folder, so test paths are relative: ../fp/<file>
\
\ Note: inside colon definitions use ." or S" TYPE — not .(
\ .( is immediate and prints at compile time (causes false "noise" messages).

CR .( Running FP Tests) CR

0 WARNING !

[UNDEFINED] [UNDEFINED] [IF]
  : [UNDEFINED]  ( "name" -- flag )  BL WORD FIND NIP 0= ; IMMEDIATE
[THEN]

: ZAP-FPSTACK  BEGIN FDEPTH WHILE FDROP REPEAT ;

[UNDEFINED] ERROR-XT [IF]
  .( FP: loading ttester.fs ) CR
  S" ../fp/ttester.fs" INCLUDED
[ELSE]
  .( FP: ttester already present ) CR
[THEN]

\ Compact error report (whole-file SOURCE would dump the entire .fs).
\ FP files install ERROR-XT that does  1 #ERRORS +! ERROR1  — do not +! here.
: ERROR1  ( c-addr u -- )
   CR TYPE SPACE ." [>IN=" >IN @ 0 .R ." of " SOURCE NIP 0 .R ." ]" CR
   EMPTY-STACK
;
' ERROR1 ERROR-XT !

0 VALUE FP-ERR-TOTAL
: ACCUM-FP-ERR  ( -- )
   #ERRORS @ DUP IF
      ." FP: file #ERRORS = " DUP . CR
   THEN
   FP-ERR-TOTAL + TO FP-ERR-TOTAL
   0 #ERRORS !
;

\ c-addr u is a path relative to this Harness/ directory (../fp/…).
: FP-LOAD  ( c-addr u -- )
   ZAP-FPSTACK
   0 #ERRORS !
   ." FP: " 2DUP TYPE CR
   INCLUDED
   ACCUM-FP-ERR
;

S" ../fp/fatan2-test.fs"     FP-LOAD
S" ../fp/ieee-arith-test.fs" FP-LOAD
S" ../fp/ieee-fprox-test.fs" FP-LOAD
S" ../fp/fpzero-test.4th"    FP-LOAD
S" ../fp/fpio-test.4th"      FP-LOAD
S" ../fp/to-float-test.4th"  FP-LOAD

ZAP-FPSTACK

\ paranoia: full load (host buffer is 256 KiB). ? is a kernel tools word.
: TRY-PARANOIA
   ZAP-FPSTACK
   0 #ERRORS !
   ." FP: ../fp/paranoia.4th" CR
   S" ../fp/paranoia.4th" ['] INCLUDED CATCH ?DUP IF
      CR ." FP: paranoia THROW " . CR
   ELSE
      ACCUM-FP-ERR
   THEN
;
TRY-PARANOIA

ZAP-FPSTACK
0 #ERRORS !
.( FP: ../fp/ak-fp-test.fth ) CR
S" ../fp/ak-fp-test.fth" INCLUDED
ACCUM-FP-ERR

\ Publish accumulated count for HayesTest.fth (FPERRORS).
FP-ERR-TOTAL #ERRORS !

-1 WARNING !

CR CR
.( FP tests finished) CR
.( FP-ERR-TOTAL = ) FP-ERR-TOTAL . CR CR

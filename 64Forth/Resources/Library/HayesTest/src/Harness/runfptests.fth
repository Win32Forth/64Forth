\ runfptests.fth — 64Forth / vendor FP suite driver (HARNESs, not a test)
\
\ Location: HayesTest/src/Harness/   (kept out of fp/ so suite sources stay clean)
\ Actual FP tests live in:          HayesTest/src/fp/
\
\ Named FLOAD sets cwd to this Harness/ folder, so test paths are
\ relative: ../fp/<file>
\
\ Note: inside colon definitions use ." or S" TYPE — not .(
\ .( is immediate and prints at compile time (causes false "noise" messages).

CR .( Running FP Tests) CR

\ searchordertest can leave a odd order. FLOATING is the vocabulary;
\ filetest's CREATE FP is a buffer and is left alone.
ONLY FORTH ALSO FLOATING

0 WARNING !

[UNDEFINED] [UNDEFINED] [IF]
  : [UNDEFINED]  ( "name" -- flag )  BL WORD FIND NIP 0= ; IMMEDIATE
[THEN]
order
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
\ Each FP file may do  VARIABLE #errors  and count into that new word.
\ Resolve the name when the file returns so the latest counter is the one added.
\ FIND takes a counted string. Copy the name to PAD so a file's own
\ VARIABLE #errors is the one we read, not the counter compiled earlier.
: FP-ERR-FIND  ( -- xt|0 )
   S" #ERRORS" DUP PAD C! PAD 1+ SWAP CMOVE PAD FIND
   IF EXIT THEN DROP 0 ;
: FP-ERR@  ( -- n )
   FP-ERR-FIND ?DUP IF >BODY @ ELSE 0 THEN ;
: FP-ERR-CLEAR  ( -- )
   FP-ERR-FIND ?DUP IF >BODY 0 SWAP ! THEN ;
: ACCUM-FP-ERR  ( -- )
   FP-ERR@ DUP IF
      ." FP: file #ERRORS = " DUP . CR
   THEN
   FP-ERR-TOTAL + TO FP-ERR-TOTAL
   FP-ERR-CLEAR
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

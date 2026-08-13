\ host.fth — high-ROI TZForth FTEST / ANS-VALIDATE spots not covered elsewhere
\
\ Port of selected TestTZForth.swift TEST6 checks as pure Forth EXPECT cases.
\ Requires: tester.fth already loaded (and kernel with fixed ABORT" / SLITERAL).
\
\ CRITICAL: no interpret-time IF/ELSE/THEN/BEGIN.
\ NOT a formal ANS certificate. Prefer Hayes for deep coverage.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Host port wave ===) CR

\ Counted string at PAD for FIND (ANS FIND wants counted c-addr).
: (H-PADCS)  ( c-addr u -- ca )
   DUP PAD C!
   PAD 1+ SWAP CMOVE
   PAD ;

\ --- FIND ---
S" DUP" (H-PADCS) FIND NIP 0= 0= S" FIND" EXPECT
\ miss: ( c-addr 0 ) → flag true, drop c-addr
: (H-FMISS)  FIND 0= NIP ;
S" ZZNOPE99QQ" (H-PADCS) (H-FMISS) S" FIND-miss" EXPECT

\ --- SOURCE ---
SOURCE NIP 0= 0= S" SOURCE" EXPECT
SOURCE DROP 0= 0= S" SOURCE-addr" EXPECT

\ --- POSTPONE (immediate action deferred to runtime of outer word) ---
VARIABLE H-PV
: H-TIMP  99 H-PV ! ; IMMEDIATE
0 H-PV !
: H-TPO  POSTPONE H-TIMP 42 ;
H-PV @ 0= S" POSTPONE-def" EXPECT
H-TPO 42 = S" POSTPONE-run" EXPECT
H-PV @ 99 = S" POSTPONE-side" EXPECT

\ --- SLITERAL (c-addr u from interpret [ S" …" ], then compile while STATE<>0) ---
\ ANS pattern: [ S" text" ] SLITERAL  — SLITERAL is outside ], not inside [ … ]
: H-SLIT  [ S" hi" ] SLITERAL ;
H-SLIT S" hi" COMPARE 0= S" SLITERAL" EXPECT

\ --- 2! 2@ ---
CREATE H-2A  2 CELLS ALLOT
1111 2222 H-2A 2!
H-2A 2@ 2222 = SWAP 1111 = AND S" 2!2@" EXPECT

\ --- SIGN (pictured numeric) ---
: (H-PIC)  ( n -- c-addr u )
   DUP ABS S>D <# #S ROT SIGN #> ;
: (H-SIGN-)  -5 (H-PIC) DROP C@ [CHAR] - = ;
(H-SIGN-) S" SIGN-neg" EXPECT
: (H-SIGN+)  5 (H-PIC) NIP 1 = ;
(H-SIGN+) S" SIGN-pos" EXPECT

\ --- Double trailing-dot literals ---
1234. DROP 1234 = S" dbl-lit-lo" EXPECT
1234. NIP 0= S" dbl-lit-hi" EXPECT

\ --- {: argument order (NOS then TOS) ---
: H-BR  {: a b -- n :} a b - ;
3 4 H-BR -1 = S" brace-order" EXPECT

\ --- EMIT? / EKEY? (console host; no key inject) ---
EMIT? S" EMIT?" EXPECT
EKEY? 0= S" EKEY?-empty" EXPECT

\ --- compile + run ABORT" (v0.8.1 path: -2 POSTPONE LITERAL) ---
: H-AB0  0 ABORT" should-not-show" 77 ;
H-AB0 77 = S" ABORT-quote-0" EXPECT
: H-AB1  1 ABORT" boom" ;
: (H-ABT)  ['] H-AB1 CATCH -2 = ;
(H-ABT) S" ABORT-quote-1" EXPECT

\ --- INCLUDED / REQUIRED via /tmp ---
VARIABLE H-RQ
VARIABLE H-RFID
0 H-RQ !
S" /tmp/64forth-ansval-host-req.fth" R/W CREATE-FILE
0= S" REQ-create" XEXPECT
H-RFID !
S" 1 H-RQ +! " H-RFID @ WRITE-FILE 0= S" REQ-write" EXPECT
H-RFID @ CLOSE-FILE DROP

S" /tmp/64forth-ansval-host-req.fth" REQUIRED
H-RQ @ 1 = S" REQUIRED-1" EXPECT
S" /tmp/64forth-ansval-host-req.fth" REQUIRED
H-RQ @ 1 = S" REQUIRED-once" EXPECT
S" /tmp/64forth-ansval-host-req.fth" INCLUDED
H-RQ @ 2 = S" INCLUDED-reload" EXPECT
S" /tmp/64forth-ansval-host-req.fth" DELETE-FILE DROP

\ --- GD8-style +LOOP orbits (Hayes GD8 subset; 64-bit) ---
VARIABLE H-BUMP
0 INVERT CONSTANT H-MAXU
H-MAXU 8 RSHIFT 1+ CONSTANT H-USTEP
H-USTEP NEGATE CONSTANT H-MUSTEP
: H-GD8  H-BUMP ! DO 1+ H-BUMP @ +LOOP ;
0 H-MAXU 0 H-USTEP H-GD8 256 = S" GD8-ustep" EXPECT
0 0 H-MAXU H-MUSTEP H-GD8 256 = S" GD8-mustep" EXPECT

\ --- Float: FALIGNED FATAN2 FLITERAL (FP vocabulary) ---
\ 64Forth/TZForth FALIGNED is a *flag* "addr already float-aligned?"
\ (not ANS "round addr up to alignment" — that is closer to host op FALIGN).
ALSO FP
: (H-FCLEAR)  BEGIN FDEPTH WHILE FDROP REPEAT ;
(H-FCLEAR)
0 FALIGNED S" FALIGNED-0" EXPECT
8 FALIGNED S" FALIGNED-8" EXPECT
1 FALIGNED 0= S" FALIGNED-1" EXPECT
0e0 1e0 FATAN2 F0= S" FATAN2-0" EXPECT
: H-FLIT  [ 3e0 FLITERAL ] ;
H-FLIT F>S 3 = S" FLITERAL" EXPECT
(H-FCLEAR)
ONLY FORTH DEFINITIONS

\ --- MARKER last so it does not strip earlier host helpers mid-suite ---
MARKER H-MRK
: H-TEMP  11 ;
H-TEMP 11 = S" MARKER-before" EXPECT
H-MRK
S" H-TEMP" (H-PADCS) (H-FMISS) S" MARKER-gone" EXPECT

ONLY FORTH DEFINITIONS

.( --- Host port wave done ---) .STACK-DEPTH CR

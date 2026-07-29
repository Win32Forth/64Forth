\ exception.fth — ANS Exception spot-checks (CATCH / THROW)
\
\ Requires: tester.fth already loaded
\ All throws must be inside CATCH. No interpret-time IF/BEGIN.
\ ABORT" covered by Hayes exceptiontest.fth.
\
\ NOT a formal ANS certificate.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Exception ===) CR

: (EX-CLEAR)  BEGIN DEPTH WHILE DROP REPEAT ;

(EX-CLEAR)

\ --- CATCH, no THROW ---
: EX-OK  42 ;
: (EX-T-OK)  ['] EX-OK CATCH 0= SWAP 42 = AND ;
(EX-T-OK) S" CATCH-ok" EXPECT

\ --- THROW non-zero ---
: EX-T1  123 THROW ;
: (EX-T-1)  ['] EX-T1 CATCH 123 = ;
(EX-T-1) S" THROW-catch" EXPECT

\ --- stack under THROW ---
: EX-T2  99 THROW ;
: (EX-T-2)  10 20 ['] EX-T2 CATCH 99 = SWAP 20 = AND SWAP 10 = AND ;
(EX-T-2) S" THROW-stack" EXPECT

\ --- 0 THROW is no-op ---
: EX-T0  0 THROW 77 ;
: (EX-T-0)  ['] EX-T0 CATCH 0= SWAP 77 = AND ;
(EX-T-0) S" THROW-0" EXPECT

\ --- negative code ---
: EX-NEG  -2 THROW ;
: (EX-T-NEG)  ['] EX-NEG CATCH -2 = ;
(EX-T-NEG) S" THROW-neg" EXPECT

\ --- nested CATCH ---
: EX-IN  55 THROW ;
: EX-OUT  ['] EX-IN CATCH ;
: (EX-T-NEST)  ['] EX-OUT CATCH 0= SWAP 55 = AND ;
(EX-T-NEST) S" nested-catch" EXPECT

\ --- nested rethrow ---
: EX-IN2  66 THROW ;
: EX-OUT2  ['] EX-IN2 CATCH THROW ;
: (EX-T-RE)  ['] EX-OUT2 CATCH 66 = ;
(EX-T-RE) S" nested-rethrow" EXPECT

\ --- tick + CATCH ---
: EX-E  7 THROW ;
: (EX-T-EX)  ['] EX-E CATCH 7 = ;
(EX-T-EX) S" TICK-CATCH" EXPECT

\ --- EVALUATE + THROW ---
: EX-EV  S" 88 THROW" EVALUATE ;
: (EX-T-EV)  ['] EX-EV CATCH 88 = ;
(EX-T-EV) S" EVAL-THROW" EXPECT

\ --- EVALUATE success ---
: EX-EVOK  S" 3 4 +" EVALUATE ;
: (EX-T-EVOK)
  ['] EX-EVOK CATCH
  DUP 0= IF DROP THEN
  7 = ;
(EX-T-EVOK) S" EVAL-ok" EXPECT

\ --- two-cell body ---
: EX-2  1 2 ;
: (EX-T-2C)  ['] EX-2 CATCH 0= SWAP 2 = AND SWAP 1 = AND ;
(EX-T-2C) S" CATCH-2cell" EXPECT

\ --- ENVIRONMENT? ---
S" EXCEPTION" ENVIRONMENT? NIP S" ENV-EXCEPTION" EXPECT

(EX-CLEAR)
ONLY FORTH

CR .( --- Exception batch done ---) CR

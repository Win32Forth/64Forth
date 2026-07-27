\ =============================================================================
\ bi-test.fth — BIG-INTEGER unit tests for TZForth (not ANS / not Hayes)
\ =============================================================================
\
\ Run:  FROMLIB FLOAD BigInteger/bi-test.fth
\
\ Loads BigInteger/big-int and PI/pi-chudnovsky via FROMLIB from Resources/Library.
\ Leaves search order as ONLY FORTH ALSO DEFINITIONS.
\ =============================================================================

DECIMAL

VARIABLE #BI-PASS
VARIABLE #BI-FAIL
0 #BI-PASS !
0 #BI-FAIL !

: BI-OK   ( -- )  1 #BI-PASS +! ;
: BI-BAD  ( c-addr u -- )
  1 #BI-FAIL +!
  ." FAIL: " TYPE CR ;

\ flag true → pass; false → fail with message
: BI-ASSERT  ( flag c-addr u -- )
  ROT IF  2DROP BI-OK  ELSE  BI-BAD  THEN ;

\ ---- load library ------------------------------------------------------------

FROMLIB REQUIRE BigInteger/big-int.fth
ALSO BIG-INTEGER

.( === BIG-INTEGER unit tests ===) CR

\ ---- buffers -----------------------------------------------------------------

VARIABLE A   VARIABLE B   VARIABLE C
VARIABLE Q   VARIABLE R   VARIABLE W
VARIABLE T1  VARIABLE T2

: BI-MAKE  ( digits var -- )
  OVER BI-NEW                    ( digits var bi ior )
  IF  DROP 2DROP  0 SWAP !  1 #BI-FAIL +!  ." FAIL: BI-NEW" CR  EXIT  THEN
  NIP SWAP ! ;

80 A  BI-MAKE
80 B  BI-MAKE
80 C  BI-MAKE
80 Q  BI-MAKE
80 R  BI-MAKE
80 W  BI-MAKE
80 T1 BI-MAKE
80 T2 BI-MAKE

\ ---- tests -------------------------------------------------------------------

\ zero / set
A @ BI-CLEAR
A @ BI-ZERO?  S" BI-CLEAR / BI-ZERO?" BI-ASSERT

123456789 A @ BI!U
A @ BI-ZERO? 0=  S" BI!U non-zero" BI-ASSERT
A @ 0 BI-LIMB @ 123456789 =  S" BI!U limb0" BI-ASSERT

-42 B @ BI!N
B @ BI-SGN -1 =  S" BI!N sign" BI-ASSERT

\ compare
10 A @ BI!U
10 B @ BI!U
A @ B @ BI=  S" BI= equal" BI-ASSERT
11 B @ BI!U
A @ B @ BI<  S" BI< " BI-ASSERT
B @ A @ BI>  S" BI> " BI-ASSERT

\ add / sub
100 A @ BI!U
23  B @ BI!U
A @ B @ C @ BI+
C @ 0 BI-LIMB @ 123 =  S" BI+ 100+23" BI-ASSERT

A @ B @ C @ BI-
C @ 0 BI-LIMB @ 77 =  S" BI- 100-23" BI-ASSERT

\ single-limb mul
999999999 A @ BI!U
A @ 2 C @ BI*U
C @ BI-LEN 2 =  S" BI*U carry limb" BI-ASSERT

\ multi-limb mul (host BI-MUL via BI*)
\ 10^9 in base 10^9 is limbs [0,1]; product 10^18 is [0,0,1] (three limbs).
9 A @ BI-POWER10              \ 10^9
A @ A @ C @ BI*               \ 10^18
C @ BI-LEN 3 =  S" BI* 10^9 * 10^9 limbs" BI-ASSERT
C @ 0 BI-LIMB @ 0=  S" BI* 10^18 limb0" BI-ASSERT
C @ 1 BI-LIMB @ 0=  S" BI* 10^18 limb1" BI-ASSERT
C @ 2 BI-LIMB @ 1 =  S" BI* 10^18 limb2" BI-ASSERT

\ divmod
100 A @ BI!U
7   B @ BI!U
A @ B @ Q @ R @ W @ BI-DIVMOD
Q @ 0 BI-LIMB @ 14 =  S" BI-DIVMOD quot 100/7" BI-ASSERT
R @ 0 BI-LIMB @ 2 =   S" BI-DIVMOD rem 100/7" BI-ASSERT

\ isqrt
144 A @ BI!U
A @ B @ Q @ R @ W @ T1 @ T2 @ BI-ISQRT
B @ 0 BI-LIMB @ 12 =  S" BI-ISQRT 144" BI-ASSERT

\ power10 + multi-limb div round-trip: (10^20) / (10^5) = 10^15
20 A @ BI-POWER10
5  B @ BI-POWER10
A @ B @ Q @ R @ W @ BI-DIVMOD
15 C @ BI-POWER10
Q @ C @ BI=  S" BI-DIVMOD 10^20/10^5" BI-ASSERT
R @ BI-ZERO?  S" BI-DIVMOD rem0" BI-ASSERT

\ signs
-12 A @ BI!N
5   B @ BI!U
A @ B @ C @ BI*
C @ BI-SGN -1 =  S" BI* sign" BI-ASSERT

\ π to 20 places (loads Chudnovsky)
.( --- pi 20 places ---) CR
FROMLIB REQUIRE PI/pi-chudnovsky.fth
0 STEP-LIMIT !
20 PI. CR
\ Cannot easily capture TYPE output; smoke-test only that PI. completed.
TRUE S" PI. 20 completed" BI-ASSERT

\ ---- cleanup -----------------------------------------------------------------

A @ BI-FREE  B @ BI-FREE  C @ BI-FREE
Q @ BI-FREE  R @ BI-FREE  W @ BI-FREE
T1 @ BI-FREE T2 @ BI-FREE

.( === BI-TEST summary: ) #BI-PASS @ . .( passed, ) #BI-FAIL @ . .( failed ===) CR
\ Interpret-time conditionals: use [IF] not IF (IF is compile-only).
#BI-FAIL @ 0=
[IF]
  .( === BI-TEST: ALL PASSED ===) CR
[ELSE]
  .( === BI-TEST: FAILED ===) CR
[THEN]

ONLY FORTH ALSO DEFINITIONS

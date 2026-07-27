\ =============================================================================
\ pi-chudnovsky.fth — High-precision π via the Chudnovsky algorithm
\ =============================================================================
\
\ Requires: BigInteger/big-int.fth (BIG-INTEGER vocabulary; ALSO BIG-INTEGER before use)
\
\ Formula (Chudnovsky series, fixed-point integer form):
\
\   Let D = 10^prec
\   S = Σ_{k=0}^{N-1}  (M_k * L_k * D) / X_k
\
\   with M_0=1, L_0=13591409, X_0=1, K=6 and
\     M <- M * (K^3 - 16*K) / k^3
\     L <- L + 545140134
\     X <- X * (-640320^3)
\     K <- K + 12
\
\   sqrt10005 = isqrt(10005 * D^2)
\   π_scaled  = (426880 * sqrt10005 * D) / S     ≈ π * 10^prec
\
\ Each term contributes ~14.18 correct decimal digits, so
\   N = prec/14 + 10  is ample.
\
\ Usage:
\   FROMLIB FLOAD BigInteger/big-int.fth
\   ALSO BIG-INTEGER
\   FROMLIB FLOAD PI/pi-chudnovsky.fth
\   100 PI.          \ print π to 100 decimal places
\
\ Or:  FROMLIB FLOAD PI/pi-test.fth
\
\ =============================================================================

DECIMAL

\ BI words live in vocabulary BIG-INTEGER (not on FORTH alone after library load).
ALSO BIG-INTEGER

\ ---- working big-int pool (allocated on first use) ---------------------------

VARIABLE PI-DIGITS          \ requested decimal places after the point
VARIABLE PI-PREC            \ working precision (digits + guard)
VARIABLE PI-POOL-OK         \ true once buffers are allocated

\ Big-int handles (0 until allocated)
VARIABLE BI-M
VARIABLE BI-L
VARIABLE BI-X
VARIABLE BI-S
VARIABLE BI-D               \ 10^prec
VARIABLE BI-TERM
VARIABLE BI-TMP
VARIABLE BI-TMP2
VARIABLE BI-QUOT
VARIABLE BI-REM
VARIABLE BI-WORK
VARIABLE BI-T1
VARIABLE BI-T2
VARIABLE BI-PI              \ final scaled π
VARIABLE BI-SQ              \ isqrt(10005 * D^2)
VARIABLE BI-C3              \ 640320^3

\ Free everything (safe if never allocated).
: PI-FREE  ( -- )
  BI-M @ ?DUP IF BI-FREE THEN  0 BI-M !
  BI-L @ ?DUP IF BI-FREE THEN  0 BI-L !
  BI-X @ ?DUP IF BI-FREE THEN  0 BI-X !
  BI-S @ ?DUP IF BI-FREE THEN  0 BI-S !
  BI-D @ ?DUP IF BI-FREE THEN  0 BI-D !
  BI-TERM @ ?DUP IF BI-FREE THEN  0 BI-TERM !
  BI-TMP @ ?DUP IF BI-FREE THEN  0 BI-TMP !
  BI-TMP2 @ ?DUP IF BI-FREE THEN  0 BI-TMP2 !
  BI-QUOT @ ?DUP IF BI-FREE THEN  0 BI-QUOT !
  BI-REM @ ?DUP IF BI-FREE THEN  0 BI-REM !
  BI-WORK @ ?DUP IF BI-FREE THEN  0 BI-WORK !
  BI-T1 @ ?DUP IF BI-FREE THEN  0 BI-T1 !
  BI-T2 @ ?DUP IF BI-FREE THEN  0 BI-T2 !
  BI-PI @ ?DUP IF BI-FREE THEN  0 BI-PI !
  BI-SQ @ ?DUP IF BI-FREE THEN  0 BI-SQ !
  BI-C3 @ ?DUP IF BI-FREE THEN  0 BI-C3 !
  FALSE PI-POOL-OK ! ;

\ Allocate one buffer for `digits` decimal digits; abort on failure.
: PI-ALLOC1  ( digits var -- )
  {: digs var | bi ior :}
  digs BI-NEW TO ior TO bi
  ior IF  ." PI: ALLOCATE failed" CR  ABORT  THEN
  bi var ! ;

\ ( digits -- )  size the pool for a computation of that many places.
\ Capacity must cover the largest intermediate (mainly X ≈ 18·terms digits
\ and products like M*L*D).  We over-allocate so BI-ENSURE never aborts.
: PI-POOL  ( digits -- )
  {: digs | bud prec terms :}
  PI-FREE
  digs 6 + TO prec
  prec 14 / 2 + TO terms
  \ X digits ≈ terms * log10(640320^3) ≈ terms * 17.4; products a bit larger.
  \ Generous capacity so BI-DIV-STEP can double work without capacity abort.
  terms 30 *  digs 8 *  MAX  320 +  TO bud
  bud BI-M    PI-ALLOC1
  bud BI-L    PI-ALLOC1
  bud BI-X    PI-ALLOC1
  bud BI-S    PI-ALLOC1
  bud BI-D    PI-ALLOC1
  bud BI-TERM PI-ALLOC1
  bud BI-TMP  PI-ALLOC1
  bud BI-TMP2 PI-ALLOC1
  bud BI-QUOT PI-ALLOC1
  bud BI-REM  PI-ALLOC1
  bud BI-WORK PI-ALLOC1
  bud BI-T1   PI-ALLOC1
  bud BI-T2   PI-ALLOC1
  bud BI-PI   PI-ALLOC1
  bud BI-SQ   PI-ALLOC1
  32  BI-C3   PI-ALLOC1          \ 640320^3 fits in 2 limbs
  TRUE PI-POOL-OK ! ;

\ ---- Chudnovsky core ---------------------------------------------------------

\ term_factor = K^3 - 16*K   (always positive for K = 6,18,30,...)
: PI-K-FACTOR  ( k -- u )
  DUP DUP * OVER *              \ ( k  k^3 )   via k,k → k,k^2 → k,k^2,k → k,k^3
  SWAP 16 * - ;                 \ k^3 - 16*k

\ Compute scaled π into BI-PI.  prec = digits + guard.
\ Stack: ( digits -- )
: PI-COMPUTE  ( digits -- )
  {: digits | prec maxk k kk factor :}
  digits 1 < IF  ." PI-COMPUTE: digits must be > 0" CR  ABORT  THEN
  digits PI-DIGITS !
  digits 6 + TO prec              \ guard digits (modest for pure-Forth multiprecision)
  prec PI-PREC !
  \ Size pool from the *working* precision (not the short digit count).
  prec PI-POOL

  \ D = 10^prec
  prec BI-D @ BI-POWER10

  \ C3 = 640320^3  (build via multiplies so we stay in single cells until split)
  640320 BI-C3 @ BI!U
  BI-C3 @ 640320 BI-C3 @ BI*U
  BI-C3 @ 640320 BI-C3 @ BI*U

  \ M=1, L=13591409, X=1, S = L * D
  1 BI-M @ BI!U
  13591409 BI-L @ BI!U
  1 BI-X @ BI!U
  BI-L @ BI-D @ BI-S @ BI*          \ S = L * D

  6 TO k
  prec 14 / 2 + TO maxk            \ series terms after k=0 (~14 digits/term)

  maxk 0 ?DO
    I 1+ TO kk                      \ kk = 1..maxk

    \ M = M * (K^3-16K) / kk^3
    k PI-K-FACTOR TO factor
    BI-M @ factor BI-M @ BI*U
    kk DUP DUP * * TO factor        \ kk^3 = kk * kk * kk
    factor BI-BASE < IF
      BI-M @ factor BI/U DROP
    ELSE
      factor BI-TMP @ BI!U
      BI-M @ BI-TMP @ BI-QUOT @ BI-REM @ BI-WORK @ BI-DIVMOD
      BI-QUOT @ BI-M @ BI-COPY
    THEN

    \ L = L + 545140134
    545140134 BI-TMP @ BI!U
    BI-L @ BI-TMP @ BI-L @ BI+

    \ X = X * (-C3)
    BI-X @ BI-C3 @ BI-TMP @ BI*
    BI-TMP @ BI-X @ BI-COPY
    BI-X @ BI-NEGATE

    \ term = (M * L * D) / X
    BI-M @ BI-L @ BI-TMP @ BI*
    BI-TMP @ BI-D @ BI-TERM @ BI*
    BI-TERM @ BI-X @ BI-QUOT @ BI-REM @ BI-WORK @ BI-DIVMOD
    BI-QUOT @ BI-TERM @ BI-COPY

    \ S = S + term
    BI-S @ BI-TERM @ BI-S @ BI+

    k 12 + TO k
  LOOP

  \ abs(S) — series sum is positive; guard against sign of last term
  BI-S @ BI-SGN 0< IF  BI-S @ BI-NEGATE  THEN

  \ sq = isqrt(10005 * D * D)
  10005 BI-TMP @ BI!U
  BI-TMP @ BI-D @ BI-TMP2 @ BI*
  BI-TMP2 @ BI-D @ BI-TMP @ BI*
  BI-TMP @ BI-SQ @ BI-QUOT @ BI-REM @ BI-WORK @ BI-T1 @ BI-T2 @ BI-ISQRT

  \ pi_scaled = 426880 * sq * D  /  S
  426880 BI-TMP @ BI!U
  BI-TMP @ BI-SQ @ BI-TMP2 @ BI*
  BI-TMP2 @ BI-D @ BI-TMP @ BI*
  BI-TMP @ BI-S @ BI-PI @ BI-REM @ BI-WORK @ BI-DIVMOD
  \ Drop any transient stack noise from helpers
;

\ ---- Pretty-printer ----------------------------------------------------------

\ Print π to `digits` places:  3.14159...
: PI.  ( digits -- )
  {: digits | n depth0 :}
  DEPTH TO depth0
  digits PI-COMPUTE
  BI-PI @ BI-ZERO? IF  ." 0"  DEPTH depth0 - 0 MAX 0 ?DO DROP LOOP  EXIT  THEN
  BI-PI @ BI-ABS!

  \ Trim guard digits: BI-PI := floor(π * 10^digits)
  digits PI-PREC @ = IF
  ELSE
    PI-PREC @ digits -
    BI-TMP @ BI-POWER10
    BI-PI @ BI-TMP @ BI-QUOT @ BI-REM @ BI-WORK @ BI-DIVMOD
    BI-QUOT @ BI-PI @ BI-COPY
  THEN

  \ Split integer / fraction at the decimal point
  digits BI-TMP @ BI-POWER10
  BI-PI @ BI-TMP @ BI-QUOT @ BI-REM @ BI-WORK @ BI-DIVMOD
  BI-QUOT @ BI.
  [CHAR] . EMIT

  BI-REM @ BI-ZERO? IF
    digits 0 ?DO  [CHAR] 0 EMIT  LOOP
    DEPTH depth0 - 0 MAX 0 ?DO DROP LOOP
    EXIT
  THEN

  \ Leading zeros so the fraction has exactly `digits` places
  BI-REM @ BI-TMP2 @ BI-COPY
  0 TO n
  BEGIN  BI-TMP2 @ BI-ZERO? 0=  WHILE
    BI-TMP2 @ 10 BI/U DROP
    n 1+ TO n
  REPEAT
  digits n -  0 MAX  0 ?DO  [CHAR] 0 EMIT  LOOP
  BI-REM @ BI.
  DEPTH depth0 - 0 MAX 0 ?DO DROP LOOP
;

\ Compute and print with a banner.
: PI-DEMO  ( digits -- )
  CR ." Computing π to " DUP . ." decimal places..." CR
  DUP PI.
  CR ." done." CR ;

.( pi-chudnovsky.fth loaded.) CR
.( Try:  50 PI.   or   100 PI-DEMO ) CR

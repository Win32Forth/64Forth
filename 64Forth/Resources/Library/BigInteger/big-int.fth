\ =============================================================================
\ big-int.fth — BIG-INTEGER word set for TZForth (not ANS)
\ =============================================================================
\
\ Extends the kernel vocabulary BIG-INTEGER (host BI-MUL, BI-DIVMOD, BI-ISQRT)
\ with allocation, add/sub, single-limb ops, and decimal I/O.
\
\ Representation
\   Base BI-BASE = 1_000_000_000  (exactly 9 decimal digits per limb).
\   Limb × limb fits in a signed 64-bit TZForth cell:
\       (BI-BASE-1)^2 = 999999998000000001 < 2^63.
\
\   Each big integer is an ALLOCATE'd cell-aligned block:
\
\     cell 0   capacity   maximum number of limbs
\     cell 1   length     used limbs (0 ⇒ value is zero)
\     cell 2   sign       +1 or −1 (ignored when length = 0)
\     cell 3+  limbs      little-endian; limb 0 is least-significant
\
\ Public arithmetic takes an explicit destination.  Multi-limb mul/div/isqrt
\ use host words in BIG-INTEGER (same layout).  BI-DIVMOD's work and
\ BI-ISQRT's scratch args are accepted for source compatibility and ignored
\ by the host path.
\
\ Load via FROMLIB (Resources/Library):
\   FROMLIB FLOAD BigInteger/big-int.fth
\ Use:  ALSO BIG-INTEGER   (or execute BIG-INTEGER) so BI words are visible.
\       ONLY FORTH ALSO BIG-INTEGER WORDS   — list this word set only
\
\ Search order for this load:
\   start: ONLY FORTH ALSO BIG-INTEGER DEFINITIONS
\   end:   ONLY FORTH ALSO DEFINITIONS
\
\ Demos:
\   FROMLIB FLOAD PI/pi-test.fth           — π demo 20/50/100
\   FROMLIB FLOAD BigInteger/bi-test.fth   — unit tests
\   

\
\ Word set (summary)
\   Layout / alloc:  BI-CAP BI-LEN BI-LEN! BI-SGN BI-SGN! BI-DATA BI-LIMB
\                    BI-BYTES BI-CAP-FOR BI-ALLOCATE BI-NEW BI-FREE BI-ENSURE
\   Value:           BI-ZERO? BI-NORM BI-CLEAR BI!U BI!N BI-COPY BI-NEGATE BI-ABS!
\   Compare:         BI-ABS-CMP BI-CMP BI= BI< BI>
\   Add/sub:         BI-ADD-ABS BI-SUB-ABS BI+ BI-
\   Mul:             BI*U  BI* (= host BI-MUL)
\   Div:             BI/U BI/U-TO  BI-DIVMOD (host)  BI/  BI-ISQRT (host)
\   Host only:       BI-MUL BI-DIVMOD BI-ISQRT  (kernel; same layout)
\   I/O / util:      BI-U.9 BI. BI.S BI-POWER10
\   Constant:        BI-BASE  BI-DIGITS/LIMB
\ =============================================================================

DECIMAL

\ Compile new library words into BIG-INTEGER; keep FORTH visible for Core words.
ONLY FORTH ALSO BIG-INTEGER DEFINITIONS

1000000000 CONSTANT BI-BASE
9          CONSTANT BI-DIGITS/LIMB

\ -----------------------------------------------------------------------------
\ Accessors
\ -----------------------------------------------------------------------------

: BI-CAP    ( bi -- n )  @ ;
: BI-LEN    ( bi -- n )  CELL+ @ ;
: BI-LEN!   ( n bi -- )  CELL+ ! ;
: BI-SGN    ( bi -- n )  [ 2 CELLS ] LITERAL + @ ;
: BI-SGN!   ( n bi -- )  [ 2 CELLS ] LITERAL + ! ;
: BI-DATA   ( bi -- addr )  [ 3 CELLS ] LITERAL + ;
: BI-LIMB   ( bi i -- addr )  CELLS SWAP BI-DATA + ;

: BI-BYTES    ( cap -- u )  3 + CELLS ;
: BI-CAP-FOR  ( digits -- cap )
  BI-DIGITS/LIMB /MOD SWAP IF 1+ THEN  4 + ;

\ -----------------------------------------------------------------------------
\ Allocation
\ -----------------------------------------------------------------------------

: BI-ALLOCATE  ( cap -- bi ior )
  DUP 1 MAX
  DUP BI-BYTES ALLOCATE              ( cap addr ior )
  DUP IF  NIP NIP 0 SWAP EXIT  THEN DROP
  2DUP !                             \ store capacity
  0 OVER BI-LEN!
  1 OVER BI-SGN!
  DUP BI-DATA  2 PICK CELLS  ERASE
  NIP 0 ;

: BI-NEW   ( digits -- bi ior )  BI-CAP-FOR BI-ALLOCATE ;
: BI-FREE  ( bi -- )  FREE DROP ;

\ Ensure capacity.  We intentionally do *not* RESIZE here: callers often hold
\ BI addresses in VARIABLEs, and a moved block would leave stale pointers.
\ Pre-allocate generously with BI-NEW / BI-ALLOCATE instead.
: BI-ENSURE  ( bi need -- bi )
  {: bi need :}
  bi BI-CAP need < 0= IF  bi EXIT  THEN
  ." BI-ENSURE: capacity " bi BI-CAP . ." need " need . CR
  ."   (pre-allocate a larger BI; RESIZE is not used because VARIABLEs would dangle)" CR
  ABORT" BI capacity exceeded" ;

\ -----------------------------------------------------------------------------
\ Normalise / set / copy
\ -----------------------------------------------------------------------------

: BI-ZERO?  ( bi -- flag )  BI-LEN 0= ;

: BI-NORM  ( bi -- )
  {: bi | n :}
  bi BI-LEN TO n
  BEGIN
    n 0=
    IF  TRUE
    ELSE  bi n 1- BI-LIMB @ 0= 0=  IF  TRUE  ELSE  n 1- TO n  FALSE  THEN
    THEN
  UNTIL
  n bi BI-LEN!
  n 0= IF  1 bi BI-SGN!  THEN ;

: BI-CLEAR  ( bi -- )
  {: bi :}
  0 bi BI-LEN!
  1 bi BI-SGN!
  bi BI-DATA  bi BI-CAP CELLS  ERASE ;

\ Set magnitude from an unsigned single cell (split across limbs).
: BI!U  ( u bi -- )
  {: u bi | i t :}
  bi BI-CLEAR
  u 0= IF  EXIT  THEN
  0 TO i
  BEGIN  u 0<>  WHILE
    bi i 1+ BI-ENSURE TO bi
    u 0 BI-BASE UM/MOD TO u TO t     \ ( lo=u hi=0 base -- rem quot )
    t bi i BI-LIMB !
    i 1+ TO i
  REPEAT
  i bi BI-LEN!
  1 bi BI-SGN! ;

: BI!N  ( n bi -- )
  {: n bi :}
  n 0= IF  bi BI-CLEAR EXIT  THEN
  n 0< IF  n NEGATE bi BI!U  -1 bi BI-SGN!
  ELSE     n bi BI!U
  THEN ;

: BI-COPY  ( src dst -- )
  {: src dst | n :}
  src BI-LEN TO n
  dst n BI-ENSURE TO dst
  n dst BI-LEN!
  src BI-SGN dst BI-SGN!
  n 0 ?DO  src I BI-LIMB @  dst I BI-LIMB !  LOOP ;

: BI-NEGATE  ( bi -- )
  DUP BI-ZERO? IF DROP EXIT THEN
  DUP BI-SGN NEGATE SWAP BI-SGN! ;

: BI-ABS!  ( bi -- )  1 SWAP BI-SGN! ;

\ -----------------------------------------------------------------------------
\ Comparison
\ -----------------------------------------------------------------------------

: BI-ABS-CMP  ( a b -- n )
  {: a b | la lb i :}
  a BI-LEN TO la   b BI-LEN TO lb
  la lb < IF -1 EXIT THEN
  la lb > IF  1 EXIT THEN
  la 0= IF 0 EXIT THEN
  la 1- TO i
  BEGIN
    a i BI-LIMB @  b i BI-LIMB @
    2DUP = IF
      2DROP  i 0= IF 0 EXIT THEN  i 1- TO i
    ELSE
      < IF -1 ELSE 1 THEN EXIT
    THEN
  AGAIN ;

: BI-CMP  ( a b -- n )
  {: a b | sa sb c :}
  a BI-ZERO? IF
    b BI-ZERO? IF 0 EXIT THEN
    b BI-SGN 0< IF 1 ELSE -1 THEN EXIT
  THEN
  b BI-ZERO? IF
    a BI-SGN 0< IF -1 ELSE 1 THEN EXIT
  THEN
  a BI-SGN TO sa  b BI-SGN TO sb
  sa sb < IF -1 EXIT THEN
  sa sb > IF  1 EXIT THEN
  a b BI-ABS-CMP TO c
  sa 0< IF c NEGATE ELSE c THEN ;

: BI=  ( a b -- flag )  BI-CMP 0= ;
: BI<  ( a b -- flag )  BI-CMP 0< ;
: BI>  ( a b -- flag )  BI-CMP 0> ;

\ -----------------------------------------------------------------------------
\ Absolute add / sub
\ -----------------------------------------------------------------------------

: BI-ADD-ABS  ( a b r -- )
  {: a b r | n carry s t :}
  a BI-LEN b BI-LEN MAX 1+ TO n
  r n BI-ENSURE TO r
  0 TO carry
  n 0 ?DO
    0 TO s
    I a BI-LEN < IF  a I BI-LIMB @ s + TO s  THEN
    I b BI-LEN < IF  b I BI-LIMB @ s + TO s  THEN
    s carry + TO s
    s BI-BASE /MOD TO carry TO t
    t r I BI-LIMB !
  LOOP
  carry IF
    r n 1+ BI-ENSURE TO r
    carry r n BI-LIMB !
    n 1+ TO n
  THEN
  n r BI-LEN!  1 r BI-SGN!  r BI-NORM ;

: BI-SUB-ABS  ( a b r -- )
  {: a b r | n borrow s :}
  a BI-LEN TO n
  r n BI-ENSURE TO r
  0 TO borrow
  n 0 ?DO
    a I BI-LIMB @ TO s
    I b BI-LEN < IF  s b I BI-LIMB @ - TO s  THEN
    s borrow - TO s
    s 0< IF  s BI-BASE + TO s  1 TO borrow  ELSE  0 TO borrow  THEN
    s r I BI-LIMB !
  LOOP
  n r BI-LEN!  1 r BI-SGN!  r BI-NORM ;

\ -----------------------------------------------------------------------------
\ Signed add / sub
\ -----------------------------------------------------------------------------

: BI+  ( a b r -- )
  {: a b r | sa sb :}
  a BI-ZERO? IF b r BI-COPY EXIT THEN
  b BI-ZERO? IF a r BI-COPY EXIT THEN
  a BI-SGN TO sa  b BI-SGN TO sb
  sa sb = IF
    a b r BI-ADD-ABS  sa r BI-SGN!
  ELSE
    a b BI-ABS-CMP DUP 0= IF  DROP r BI-CLEAR EXIT  THEN
    0< IF  b a r BI-SUB-ABS  sb r BI-SGN!
    ELSE   a b r BI-SUB-ABS  sa r BI-SGN!
    THEN
  THEN ;

: BI-  ( a b r -- )
  {: a b r :}
  a BI-ZERO? IF  b r BI-COPY  r BI-NEGATE EXIT  THEN
  b BI-ZERO? IF  a r BI-COPY EXIT  THEN
  a BI-SGN b BI-SGN = IF
    a b BI-ABS-CMP DUP 0= IF  DROP r BI-CLEAR EXIT  THEN
    0< IF  b a r BI-SUB-ABS  a BI-SGN NEGATE r BI-SGN!
    ELSE   a b r BI-SUB-ABS  a BI-SGN r BI-SGN!
    THEN
  ELSE
    a b r BI-ADD-ABS  a BI-SGN r BI-SGN!
  THEN ;

\ -----------------------------------------------------------------------------
\ Multiplication
\ -----------------------------------------------------------------------------

\ r = a * u   with 0 ≤ u < BI-BASE  (r may alias a)
: BI*U  ( a u r -- )
  {: a u r | carry p t :}
  u 0= a BI-ZERO? OR IF  r BI-CLEAR EXIT  THEN
  r a BI-LEN 1+ BI-ENSURE TO r
  0 TO carry
  a BI-LEN 0 ?DO
    a I BI-LIMB @ u * carry + TO p
    p BI-BASE /MOD TO carry TO t
    t r I BI-LIMB !
  LOOP
  carry IF
    carry r a BI-LEN BI-LIMB !
    a BI-LEN 1+ r BI-LEN!
  ELSE
    a BI-LEN r BI-LEN!
  THEN
  a BI-SGN r BI-SGN!
  r BI-NORM ;

\ Multi-limb multiply: host BI-MUL (kernel BIG-INTEGER).  Same stack as classic BI*.
: BI*  ( a b r -- )  BI-MUL ;

\ -----------------------------------------------------------------------------
\ Division by single limb (1 ≤ u < BI-BASE) — pure Forth (small/fast)
\ -----------------------------------------------------------------------------

: BI/U  ( bi u -- rem )
  {: bi u | i r p t :}
  u 0= IF  ." BI/U divide by zero" CR 0 EXIT  THEN
  bi BI-ZERO? IF 0 EXIT  THEN
  0 TO r
  bi BI-LEN 1- TO i
  BEGIN  i 0< 0=  WHILE
    r BI-BASE * bi i BI-LIMB @ + TO p
    p u /MOD TO t TO r
    t bi i BI-LIMB !
    i 1- TO i
  REPEAT
  bi BI-NORM
  r ;

: BI/U-TO  ( bi u dest -- rem )
  {: bi u dest :}
  bi dest BI-COPY
  dest u BI/U ;

\ Multi-limb BI-DIVMOD and BI-ISQRT are host primitives in vocabulary BIG-INTEGER
\ (installed by TZForth).  Stack effects match the former pure-Forth words;
\ work / scratch arguments are ignored by the host implementation.

: BI/  ( num den quot rem work -- )  BI-DIVMOD ;

\ -----------------------------------------------------------------------------
\ Decimal I/O
\ -----------------------------------------------------------------------------

: BI-U.9  ( u -- )
  BASE @ >R DECIMAL
  0 <# # # # # # # # # # #> TYPE
  R> BASE ! ;

: BI.  ( bi -- )
  {: bi | n :}
  bi BI-ZERO? IF  [CHAR] 0 EMIT EXIT  THEN
  bi BI-SGN 0< IF  [CHAR] - EMIT  THEN
  bi BI-LEN TO n
  BASE @ >R DECIMAL
  bi n 1- BI-LIMB @  0 <# #S #> TYPE
  R> BASE !
  n 1- 0 ?DO
    bi n 2 - I - BI-LIMB @ BI-U.9
  LOOP ;

: BI.S  ( bi -- )  BI. SPACE ;

\ r = 10^n  (n ≥ 0)
: BI-POWER10  ( n r -- )
  {: n r | q m i :}
  n 0= IF  1 r BI!U EXIT  THEN
  n BI-DIGITS/LIMB /MOD TO q TO m
  1 r BI!U
  m 0 ?DO  r 10 r BI*U  LOOP
  q 0= IF  EXIT  THEN
  \ Shift left by q limbs: new_len = old_len + q
  r BI-LEN q +  r SWAP BI-ENSURE TO r
  r BI-LEN TO i
  BEGIN  i 0>  WHILE
    i 1- TO i
    r i BI-LIMB @  r i q + BI-LIMB !
  REPEAT
  q 0 ?DO  0 r I BI-LIMB !  LOOP
  r BI-LEN q + r BI-LEN!
  r BI-NORM ;

.( big-int.fth loaded.  Use: ALSO BIG-INTEGER ) CR

\ Restore: FORTH first (and current), with ALSO depth for further ALSO <vocab>.
ONLY FORTH ALSO DEFINITIONS

\ =============================================================================
\ End of big-int.fth — host notes
\ =============================================================================
\
\ Kernel (TZForthBigInt.swift) provides in vocabulary BIG-INTEGER:
\   BI-MUL     ( a b r -- )
\   BI-DIVMOD  ( num den quot rem work -- )   work ignored
\   BI-ISQRT   ( a r quot rem work t1 t2 -- ) scratch ignored
\
\ This file adds allocation, add/sub, BI*U, BI/U, BI., etc. into BIG-INTEGER.
\ =============================================================================

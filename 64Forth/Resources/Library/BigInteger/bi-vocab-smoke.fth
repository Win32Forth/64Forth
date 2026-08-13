\ bi-vocab-smoke.fth — vocab + ALLOCATE + BI-MUL
\ Run: FROMLIB FLOAD BigInteger/bi-vocab-smoke.fth
\
\ Important:
\   .( text)  prints NOW (even while compiling a definition)
\   ." text"  prints at RUN time (what you want inside : … ;)

ONLY FORTH ALSO BIG-INTEGER DEFINITIONS

\ 56 bytes = 7 cells (cap, len, sign, 4 limbs)
: BI-MK  ( -- bi )
  56 ALLOCATE 0=
  IF
    DUP 4 SWAP !
    DUP 8 + 0 SWAP !
    DUP 16 + 1 SWAP !
  ELSE
    DROP 0
  THEN ;

: BI!1  ( u bi -- )
  DUP 8 + 1 SWAP !
  DUP 16 + 1 SWAP !
  24 + ! ;

: BI@1  ( bi -- u )  24 + @ ;

VARIABLE SMA
VARIABLE SMB
VARIABLE SMR

: BI-SMOKE  ( -- )
  BI-MK SMA !
  BI-MK SMB !
  BI-MK SMR !
  SMA @ 0= IF ." BI-MK failed" CR EXIT THEN
  123 SMA @ BI!1
  456 SMB @ BI!1
  SMA @ SMB @ SMR @ BI-MUL
  ." A*B limb0 = " SMR @ BI@1 . CR
  ." expected      56088" CR
  ;

ALSO BIG-INTEGER
BI-SMOKE

ONLY FORTH DEFINITIONS
.( bi-vocab-smoke done) CR

\ .( Loading Matrix Multiplication benchmark...) cr
\ NOTE: This version needs 0.5MB data space

\ A classical benchmark of an O(n**3) algorithm; Matrix Multiplication
\
\ Part of the programs gathered by John Hennessy for the MIPS
\ RISC project at Stanford. Translated to forth by  Marty Fraeman,
\ Johns Hopkins University/Applied Physics Laboratory.

[DEFINED] GROWMEMORYMB [IF] UNUSED 2000000 < [IF] 2 GROWMEMORYMB [THEN] [THEN]

\ MM forth2c doesn't have it !
: mybounds  over + swap ;

\ 1 cells constant cell

variable seed

: initiate-seed ( -- )  74755 seed ! ;
: random  ( -- n )  seed @ 1309 * 13849 + 65535 and dup seed ! ;

200 constant row-size
row-size cells constant row-byte-size

row-size row-size * constant mat-size
mat-size cells constant mat-byte-size

align create ima mat-byte-size allot
align create imb mat-byte-size allot
align create imr mat-byte-size allot

: initiate-matrix ( m[row-size][row-size] -- )
  mat-byte-size mybounds do
    random dup 120 / 120 * - 60 - i !
  1 cells +loop
;

: innerproduct ( a[row][*] b[*][column] -- int)
  0 row-size 0 do
    >r over @ over @ * r> + >r
    swap cell+ swap row-byte-size +
    r>
  loop
  >r 2drop r>
;

: mainx  ( -- )
  initiate-seed
  ima initiate-matrix
  imb initiate-matrix
  imr ima mat-byte-size mybounds do
    imb row-byte-size mybounds do
      j i innerproduct over ! cell+
    cell +loop
  row-size cells +loop
  drop
;

: main 10 0 do mainx loop ;

ELAPSED main

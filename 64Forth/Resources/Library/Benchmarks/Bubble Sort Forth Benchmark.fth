\ .( Loading Bubble Sort benchmark...) cr

\ A classical benchmark of an O(n**2) algorithm; Bubble sort
\
\ Part of the programs gathered by John Hennessy for the MIPS
\ RISC project at Stanford. Translated to forth by Marty Fraeman
\ Johns Hopkins University/Applied Physics Laboratory.

\ MM forth2c doesn't have it !
: mybounds  over + swap ;

\ 1 cells constant cell

variable seed ( -- addr)

: initiate-seed ( -- )  74755 seed ! ;
: random  ( -- n )  seed @ 1309 * 13849 + 65535 and dup seed ! ;

6000 constant elements ( -- int)

align create thelist elements cells allot

: initiate-list ( -- )
  thelist elements cells + thelist do random i ! 1 cells +loop
;

: dump-list ( -- )
  thelist elements cells + thelist do i @ . 1 cells +loop cr
;

: verify-list ( -- )
  thelist elements 1- cells mybounds do
    i 2@ > abort" bubble-sort: not sorted"
  1 cells +loop
;

: bubble ( -- )
\ ." bubbling..." cr
  1 elements 1 do
    thelist elements i - cells mybounds do
      i 2@ > if i 2@ swap i 2! then
    1 cells +loop
  loop
;

: bubble-sort ( -- )
  initiate-seed
  initiate-list
  bubble
  verify-list
;

: bubble-with-flag ( -- )
  1 elements 1 do
    -1 thelist elements i - cells mybounds do
      i 2@ > if i 2@ swap i 2! drop 0 then
    1 cells +loop
    if leave then
  loop
;

: bubble-sort-with-flag ( -- )
  initiate-seed
  initiate-list
  bubble-with-flag
  verify-list
;

: main	( -- )
	5 0 do bubble-sort loop
\	bubble-sort-with-flag
;

ELAPSED main

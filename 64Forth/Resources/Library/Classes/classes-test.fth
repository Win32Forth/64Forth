\ Smoke test for classes.fth. Run with the Classes directory as the working directory.
\ IF has no interpretation semantics in Forth-2012, so the checks are colon words.

S" classes.fth" REQUIRED

[DEFINED] ANEW [IF] ANEW CLASSES-TEST_MODULE [THEN]

: FAIL ( n -- ) CR ." FAIL " . CR ABORT ;
: MUST ( actual expected id -- )
    >R <> IF R> FAIL ELSE R> DROP THEN ;

:CLASS POINT <SUPER OBJECT
    INT X
    INT Y
    :M SET: ( x y -- ) TO Y TO X ;M
    :M GETX: ( -- x ) X ;M
    :M GETY: ( -- y ) Y ;M
    :M PRINT: ( -- ) GETX: SELF . GETY: SELF . ;M
;CLASS

POINT P
10 20 SET: P
GETX: P 10 1 MUST
GETY: P 20 2 MUST

:CLASS POINT3 <SUPER POINT
    INT Z
    :M SET: ( x y z -- ) TO Z SET: SUPER ;M
    :M GETZ: ( -- z ) Z ;M
;CLASS

POINT3 Q
1 2 3 SET: Q
GETX: Q 1 3 MUST
GETY: Q 2 4 MUST
GETZ: Q 3 5 MUST

:CLASS HOLDER <SUPER OBJECT
    POINT A
    INT N
    :M CLASSINIT: ( -- ) CLASSINIT: SUPER 7 TO N ;M
    :M PUTA: ( x y -- ) SET: A ;M
    :M AX: ( -- x ) GETX: A ;M
    :M GETN: ( -- n ) N ;M
;CLASS

HOLDER H
8 9 PUTA: H
AX: H 8 6 MUST
GETN: H 7 7 MUST

:OBJECT SINGLE <SUPER OBJECT
    INT V
    :M SET: ( n -- ) TO V ;M
    :M GET: ( -- n ) V ;M
;OBJECT

40 SET: SINGLE
GET: SINGLE 40 8 MUST

NEW> POINT VALUE HP
11 12 HP SET: [ ]
HP GETX: [ ] 11 9 MUST
HP DISPOSE

' P CLONE P2
GETX: P2 10 10 MUST

:CLASS FLAGS <SUPER OBJECT
    INT RAW
    3 BITS LOW
    5 BITS MID
    :M SETLOW: ( n -- ) TO LOW ;M
    :M GETLOW: ( -- n ) LOW ;M
    :M SETMID: ( n -- ) TO MID ;M
    :M GETMID: ( -- n ) MID ;M
;CLASS

FLAGS F
6 SETMID: F
5 SETLOW: F
GETLOW: F 5 11 MUST
GETMID: F 6 12 MUST

:CLASS RECTANGLE <SUPER OBJECT
    RECORD:
        INT LEFT
        INT TOP
        INT RIGHT
        INT BOTTOM
    ;RECORD
    ;RECORDSIZE: RECT-BYTES
    :M SETRECT: ( l t r b -- ) TO BOTTOM TO RIGHT TO TOP TO LEFT ;M
    :M GETL: ( -- n ) LEFT ;M
;CLASS

RECT-BYTES 4 CELLS 13 MUST
RECTANGLE R
1 2 3 4 SETRECT: R
GETL: R 1 14 MUST

: GO ( -- n ) GETX: P ;
GO 10 15 MUST

ADDR: [ P ]
ADDR: P 16 MUST

CR .( classes-test passed) CR

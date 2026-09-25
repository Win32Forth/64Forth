\ MIDNIGHT.SEQ  (C) Copyright 1979, 1989 Peter Midnight

\\

   I first wrote this graphic presentation of the ancient Towers of Hanoi
puzzle in Pascal.  The class assignment was to use recursion to produce a
list of the moves required to solve the puzzle.  But I wanted to see the
rings move.  That version was published in the Jan/Feb 1980 Newsletter of
the Homebrew Computer Club.

   Next I translated this program into FIG Forth.  In order to compare the
two languages, I resisted the temptation to improve the program in the
process of translation.  That version is published in FORTH Dimensions
Volume 2 Number 2 and in The Best of FORTH Dimensions.

   Now I have transported the same program into F-PC, again without
improvement.  This is my first machine readable publication of this program.

   This program is my claim to fame.  As long as its popularity continues,
I may never need another.   Peter Midnight

{
ANEW MIDNIGHT_MODULE
ONLY FORTH ALSO DEFINITIONS ALSO GRAPHICS    DECIMAL

[UNDEFINED] ARRAY [IF] : ARRAY ( n1 -- ) CREATE ALLOT DOES> ; [THEN]
[UNDEFINED] COL   [IF] 80 CONSTANT COLS     [THEN]
[UNDEFINED] 4DUP  [IF] : 4DUP ( n1 n2 n3 n4 -- n1 n2 n3 n4 n1 n2 n3 n4 )
                                2>R 2DUP 2R> 2SWAP 2OVER ; [THEN]

\ TONE — F-PC / TCOM: freq in Hz, dur in tenths of a second (host plays sine).
: TONE  ( freq dur -- )             \ freq=Hz, dur=tenths of a second
\       ?REFRESH
        (APP-TONE) ;

PREVIOUS

: BEEP          ( -- )
        440 5 TONE ;

: GOTOXY        ( row col --- ) \ position cursor
        AT-XY ;

: CLEARSCREEN   ( --- )         \ clear screen
        CLS ;

COLS 3 - 6 / VALUE NMAX         \ maximum rings for display size

NMAX VALUE N                    \ number of rings

FALSE CONSTANT HELL_FREEZES_OVER

TRUE CONSTANT THE_POPE_IS_A_CATHOLIC

CHAR + VALUE COLOR             \ character used to represent a ring

13 ARRAY RING                   \ array (1..N) of tower numbers

: DELAY         ( centiseconds --- )    \ pause for clarity
        10 * MS ;

: POS           ( tower --- col )       \ get display column for tower
        N 2*   1+   *   N + ;

: HALFDISPLAY   ( color size --- )      \ display half a ring
        0 DO   DUP EMIT   LOOP   DROP ;

: <DISPLAY>     ( line color size --- ) \ display a whole ring
        2DUP   HALFDISPLAY   ROT 3 <   IF BL   ELSE [CHAR] |   THEN
        EMIT   HALFDISPLAY ;

: DISPLAY       ( size col line color --- )     \ display at proper position
        SWAP >R   -ROT   OVER - R@ GOTOXY
        R>   -ROT   <DISPLAY> ;

: PRESENCE      ( tower ring --- f )    \ true if ring is on tower
        RING +   C@   = ;

: LINE          ( tower --- line )      \ top of pile on tower
        4   N 1+ 1 DO   OVER I PRESENCE   0= -   LOOP   NIP ;


: RAISE         ( size tower --- )      \ raise ring
        DUP POS   SWAP LINE   2 SWAP
        DO      2DUP I    BL    DISPLAY \ erase ring where it is
                2DUP I 1- COLOR DISPLAY \ show it one line higher
        -1 +LOOP   2DROP ;

: LOWER         ( size tower --- )      \ lower ring
        DUP POS   SWAP LINE 1+   2
        DO      2DUP I 1- BL    DISPLAY \ erase ring where it is
                2DUP I    COLOR DISPLAY \ show it one line lower
        LOOP   2DROP ;

: MOVELEFT      ( size source destination --- ) \ move ring to left
        POS   SWAP   POS 1-
        DO      DUP I 1+ 1 BL    DISPLAY        \ erase it where it is
                DUP I    1 COLOR DISPLAY        \ show it 1 column left
        -1 +LOOP   DROP ;

: MOVERIGHT     ( size source destination --- ) \ move ring to right
        POS 1+   SWAP   POS 1+
        DO      DUP I 1- 1 BL    DISPLAY        \ erase it where it is
                DUP I    1 COLOR DISPLAY        \ show it 1 column right
        LOOP   DROP ;

: TRAVERSE      ( size source destination --- ) \ move ring sideways
        2DUP >   IF MOVELEFT   ELSE MOVERIGHT   THEN ;

: MOVE          ( size source destination --- ) \ complete one move
        KEY?   IF   0 N 6 + GOTOXY  ( CURSOR-ON )  ABORT   THEN
        -ROT 2DUP RAISE
        >R 2DUP R> ROT TRAVERSE
        2DUP   RING + C!                \ also update location array
        SWAP LOWER ;

\ The following word is the recursive solution to the puzzle.

: MULTIMOVE     ( size source destination spare --- )   \ RECURSIVE
        3 PICK   1 =                    \ test for case of smallest ring
        IF      DROP MOVE               \ single ring move
        ELSE    2>R SWAP 1- SWAP 2R>    \ refer to next smaller ring, above
                4DUP SWAP RECURSE ( MULTIMOVE )    \ move it to spare tower
                4DUP DROP               \ drop spare tower number
                ROT 1+ -ROT MOVE        \ move specified ring
                -ROT SWAP RECURSE ( MULTIMOVE )   \ move next smaller ring from spare
        THEN ;

: MAKETOWER     ( tower --- )           \ draw tower on display
        POS   4 N +   3
        DO      DUP I GOTOXY
                [CHAR] | EMIT
        LOOP   DROP ;

: MAKEBASE      ( --- )                 \ draw base on display
        0 N 4 + GOTOXY
        N 6 * 3 + 0 DO   [CHAR] - EMIT   LOOP ;

: MAKERING      ( tower size --- )      \ materialize ring on display
        2DUP RING + C!                  \ mark ring location in array
        SWAP LOWER ;

: SETUP         ( --- )                 \ initialize display of puzzle
        CLEARSCREEN                             \ CURSOR-OFF
        N 1+ 0 DO   1 RING I + C!   LOOP        \ initialize array
        3 0 DO   I MAKETOWER   LOOP             \ draw towers
        MAKEBASE                                \ draw base
        1 N DO   0 I MAKERING   -1 +LOOP ;      \ materialize rings

\ The following word performs the solution repeatedly.

: TOWERS        ( quantity --- )        \ use specified number of rings
        1 MAX   NMAX MIN  ( !> ) TO N
        SETUP   N 2 0 1
        BEGIN   OVER POS   N 4 +   GOTOXY       \ put cursor under rings
                N 0 DO   BEEP   50 DELAY   LOOP \ announce completion
                ROT   4DUP   MULTIMOVE          \ move all to next tower
        HELL_FREEZES_OVER UNTIL ;               \ repeat indefinitely

ALSO GRAPHICS

: MAIN          ( -- )
        WINDOW
        7 TOWERS
        KEY DROP ;

FORTH

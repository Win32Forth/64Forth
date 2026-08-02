\ FPCTOOLS.fth

VOCABULARY HIDDEN
80 VALUE COLS
VARIABLE SPAN   \ hold the count of characters from the most recent EXPECT
VARIABLE #OUT   \ the current text output character count

: NOOP ;

DEFER ATTRIB  ' NOOP IS ATTRIB

DEFER DOBUTTON ' NOOP IS DOBUTTON

: 2+    ( n1 -- n2 )   \ n1 + 2
    2 + ;

: ON    ( a1 --- )  \ Set memory contents at a1 to -1 or ON
    -1 SWAP ! ;

: OFF   ( a1 --- )  \ Set memory contents at a1 to 0 or OFF
    0 SWAP ! ;

: HANDLE ( 'name'--- )	\ Define a file spec handle from name
	CREATE 256 ALLOT
	DOES> ;
    
: >NAM ( a1 -- a2 ) \ adjust a1 to name field a2
	128 + ;

: BOUNDS  ( addr u -- addr+u addr )
    OVER + SWAP ;

: TOUPPER ( c -- c' )
    DUP 'a' 'z' 1+ WITHIN IF  32 -  THEN ;

: UPPER ( c-addr u -- )
    BOUNDS ?DO  I C@ TOUPPER I C!  LOOP ;
 
: SKIPTILL ( a1 n1 - 'words' -- )   \ skip words till string a1 n1 is found
    2>R
    BEGIN     BL WORD DUP C@ 0=
        IF     DROP EXIT
        THEN
        COUNT 2R@ COMPARE 0=
    UNTIL 2R> 2DROP ;

: \\	( 'words' -- )	    \ Skip words until '{' is encountered
	S" {" SKIPTILL ;
    
: }     ( words '{' -- )    \ skip words until '{' is encountered
     S" {" SKIPTILL ;

: COMMENT:  ( word, word.. COMMENT; -- )    \ skip words till 'comment;'
    S" COMMENT;" SKIPTILL ;

: ARRAY	( size 'name' -- )	\ define array 'name' of size byte
	CREATE HERE OVER ALLOT ALIGNED SWAP 0 FILL
	DOES> ;
    
: \+    ( 'name' -- )   \ rest of file if name is NOT defined (immediate)
    BL WORD FIND NIP 0= IF POSTPONE \S THEN ; IMMEDIATE
    
: \-    ( 'name' -- )   \ rest of file if name IS defined (immediate)
    BL WORD FIND NIP IF POSTPONE \S THEN ; IMMEDIATE
    
: FREE  ( -- free_mem ) \ return the amount of available memory in the dictionary
    UNUSED ;
    
: PLUCK ( n1 n2 n3 --- n1 n2 n3 n1 ) \ copy second entry below top of stack to top
    2 PICK ;
    
: DUP>R ( n1 --- n1 r1 )
    R> OVER >R >R ;

: R>DROP ( r1 --- ) \ Drop top of return stack
    R> R> DROP >R ;

\ --- Cursor positioning (64Forth facility terminal, not ANSI CSI) ---
\ Kernel AT-XY ( col row -- ) is 0-based and drives FacilityTerminal.
\ AT-XY? is CODE: host returns FacilityTerminal cursorCol/cursorRow (0-based).
\ F-PC AT / AT? aliases for old sources.

: AT   ( col row -- )  \ F-PC name for set cursor (0-based, same as ANS AT-XY)
    AT-XY ;

\ AT-XY? is a kernel CODE word (facility grid). Do not redefine with ANSI DSR —
\ the SwiftUI console has no real terminal to answer ESC [6n.

: AT?   ( -- col row )  \ F-PC name: current cursor (col row, 0-based)
    AT-XY? ;

\ After AT-XY / EMIT in facility mode, paint so the console shows the move.
\ Optional convenience for interactive TCOM tools (SZ-EDITOR does its own refresh).
: AT-XY-REFRESH  ( col row -- )  AT-XY TERMINAL-REFRESH ;

\ --- SAVE> / RESTORE> / SAVE!> (DEFER or VALUE data at >BODY CELL+) ---
\ IMMEDIATE: run while compiling outer colon word; POSTPONE runtime into it.
\ Bare R>/! here ran at the wrong time → stack underflow.
\   save> name              →  <addr> @ >R
\   restore> name           →  R> <addr> !
\   ['] xt save!> name      →  xt  <addr>  DUP @ >R  !

: SAVE>  ( "name" -- )  \ runtime: push current DEFER/VALUE cell to R
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE @  POSTPONE >R ; IMMEDIATE

: RESTORE>  ( "name" -- )  \ runtime: pop R into DEFER/VALUE cell
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE R>  POSTPONE SWAP  POSTPONE ! ; IMMEDIATE

: SAVE!>  ( "name" -- )  \ runtime: ( xt -- ) save old cell to R, store xt
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL
    POSTPONE DUP  POSTPONE @  POSTPONE >R  POSTPONE ! ; IMMEDIATE

: 0MAX  ( n1 -- n2 )    \ maximize n1 with zero and return n2
    0 MAX ;

\ VALUE data is at CFA+16 (DOES> layout: does_ip @ +8, value @ +16).
\
\ OFF> / ON> / =: / +!> are IMMEDIATE (run while compiling an outer colon word).
\ LITERAL is also IMMEDIATE: use POSTPONE LITERAL so it lives in OFF>'s body and
\ runs when OFF> is *used*, with the VALUE address already on the stack.
\
\ =: and +!> must NOT "LITERAL" the value n at compile time of the outer word.
\ The preceding expression is already compiled and will leave n at runtime:
\   ecursor 1+ lenlimit min =: ecursor
\ becomes runtime:  … min  <addr>  !

: OFF>  ( "name" -- )  \ compile: <addr> OFF   (OFF stores 0)
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE OFF ; IMMEDIATE

: ON>   ( "name" -- )  \ compile: <addr> ON    (ON stores -1)
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE ON ; IMMEDIATE

: =:    ( "name" -- )  \ compile: <addr> !     (n comes from code above)
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE ! ; IMMEDIATE

: +!>   ( "name" -- )  \ compile: <addr> +!    (n comes from code above)
    ?COMP  ' >BODY CELL+  POSTPONE LITERAL  POSTPONE +! ; IMMEDIATE

: BETWEEN ( n1|u1 n2|u2 n3|u3 -- flag ) \ n2<=n1<=n3 (unsigned wrap)
    1 + WITHIN ;

: C+!   ( n1 a1 --- )   \ Add n1 to character contents of a1
    DUP C@ ROT + SWAP C! ;

: ?LEAVE    ( f1 --- )  \ Leave DO LOOP if f1 is true
    ?COMP POSTPONE IF POSTPONE LEAVE POSTPONE THEN ; IMMEDIATE

: BEEP  ( --- ) \ make a sound like a beep
    ;

: BIG-CURSOR    ( --- ) \ display a big cursor
    ;
    
: NORM-CURSOR   ( --- ) \ display a normal cursor
    ;

\ Opaque cursor save cell: pack col (lo) and row (hi) from AT-XY?.
CREATE (CURSOR-SAVE) 0 ,

: GET-CURSOR    ( --- a1)   \ address of saved cursor (col,row packed)
    AT-XY?  16 LSHIFT OR  (CURSOR-SAVE) !
    (CURSOR-SAVE) ;

: SET-CURSOR    ( a1 --- )  \ restore cursor from GET-CURSOR cell
    @  DUP $FFFF AND  SWAP 16 RSHIFT  AT-XY ;

: EXEC: ( n1 === )  \ Vector to entry in table immediatly following
    CELLS R> + @ EXECUTE ;

\S

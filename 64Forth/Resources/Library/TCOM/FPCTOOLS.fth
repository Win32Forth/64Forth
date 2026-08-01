\ FPCTOOLS.fth

VOCABULARY HIDDEN

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

VARIABLE SPAN   \ hold the count of characters from the most recent EXPECT

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

\S

\ Load the class engine and the Mac OOP window, menu, and button classes.
\ GRAPHICS / App Output is not used.
\ (OOP-CALL) ( a b c d op -- n ) is a kernel word. Until the app is rebuilt
\ the stub below returns 0 so this file still loads.

FROMLIB FLOAD Classes/classes.fth

[UNDEFINED] (OOP-CALL) [IF]
: (OOP-CALL) ( a b c d op -- n ) 2DROP 2DROP DROP 0 ;
[THEN]

\ op 6: next menu or button tag, or 0.
: OOP-EVENT ( -- tag ) 0 0 0 0 6 (OOP-CALL) ;

\ Tag 1..32 -> xt.  ' DO-QUIT 1 OOP-ON
32 CELLS BUFFER: OOP-ACTS
: OOP-ON ( xt tag -- )
    DUP 1 33 WITHIN 0= ABORT" OOP tag must be 1..32"
    1- CELLS OOP-ACTS + ! ;

VARIABLE OOP-DONE
: OOP-STOP ( -- ) TRUE OOP-DONE ! ;

\ Run stored words until one of them calls OOP-STOP.
\ A tag with no word is printed. The win-id is unused.
: OOP-SERVE ( win-id -- )
    DROP  FALSE OOP-DONE !
    BEGIN
        OOP-DONE @ 0=
    WHILE
        OOP-EVENT ?DUP IF
            DUP 1- CELLS OOP-ACTS + @ ?DUP IF
                NIP EXECUTE
            ELSE
                CR ." tag " .
            THEN
        THEN
    REPEAT ;

\ Pack two small positives into one cell: ( lo hi -- lo|(hi<<16) )
: OOP-PACK ( lo hi -- n ) 16 LSHIFT OR ;

FROMLIB FLOAD Classes/oop-window.fth
FROMLIB FLOAD Classes/oop-child.fth
FROMLIB FLOAD Classes/oop-menu.fth
FROMLIB FLOAD Classes/oop-button.fth

.( oop.fth loaded) CR

\S

\ An example of a simple window with one button Press, and one menu with a single menu item Quit
WINDOW W   CHILD C   MENU M   BUTTON B
START: W
S" Demo" TITLE: W
GETID: W ATTACH: M
S" Quit" ITEM: M
40 TO ORGX  40 TO ORGY  220 TO WIDT  80 TO HITE
GETID: W START: C
GETID: C ATTACH: B
S" Press" 16 16 10 LABEL: B
: DO-QUIT  CLOSE: W  OOP-STOP ;
: DO-PRESS CR ." pressed" ;
' DO-QUIT 1 OOP-ON
' DO-PRESS 10 OOP-ON
GETID: W OOP-SERVE


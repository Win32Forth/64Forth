\ Push button in a WINDOW or CHILD. Host op 5.
\ LABEL: ( c-addr u x y tag -- ). x,y is the top-left inside the parent.
\ OOP-EVENT returns that tag when it is clicked.

: OOP-XYT ( x y tag -- n )
    >R  16 LSHIFT OR  16 LSHIFT  R> OR ;

:CLASS BUTTON <SUPER OBJECT
    INT OWNER
    :M ATTACH: ( win-id -- ) TO OWNER ;M
    :M LABEL: ( c-addr u x y tag -- )
        OOP-XYT OWNER SWAP 5 (OOP-CALL) DROP
    ;M
;CLASS

\ A view inside a WINDOW or another CHILD. Host op 7.
\ Origin is the top-left of the parent. START: takes the parent id.

:CLASS CHILD <SUPER WINDOW
    INT PARENT
    :M CLASSINIT: ( -- )
        CLASSINIT: SUPER
        16 TO ORGX  16 TO ORGY  200 TO WIDT  120 TO HITE
    ;M
    :M START: ( parent-id -- )
        TO PARENT
        ORGX ORGY  WIDT HITE OOP-PACK  PARENT 7 (OOP-CALL) TO WID
    ;M
;CLASS

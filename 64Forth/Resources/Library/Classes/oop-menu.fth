\ Menu items on a WINDOW. Host op 4.
\ ITEM: takes ( c-addr u ). The item's tag is 1, 2, 3... in definition order.
\ OOP-EVENT returns that tag when the item is chosen.

:CLASS MENU <SUPER OBJECT
    INT OWNER
    INT TAGN
    :M ATTACH: ( win-id -- ) TO OWNER ;M
    :M ITEM: ( c-addr u -- )
        TAGN 1+ TO TAGN
        OWNER TAGN 4 (OOP-CALL) DROP
    ;M
;CLASS

\ Isolated PT5 / ?REPEAT / CS-PICK test (toolstest.fth excerpt).
\ Prerequisite: FLOAD debug-bootstrap.fth

: ?REPEAT  0 CS-PICK POSTPONE UNTIL ;  IMMEDIATE
VARIABLE PT4
: PT5  ( N1 -- )
   PT4 !
   BEGIN
      -1 PT4 +!
      PT4 @ 4 > 0= ?REPEAT
      111
      PT4 @ 3 > 0= ?REPEAT
      222
      PT4 @ 2 > 0= ?REPEAT
      333
      PT4 @ 1 =
   UNTIL ;

0 #ERRORS !
T{ 6 PT5 -> 111 111 222 111 222 333 111 222 333 }T
#ERRORS @ .
.( debug-pt5 done, errors= ) #ERRORS @ . CR
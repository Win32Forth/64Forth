: MIX_UP 2 CS-ROLL ; IMMEDIATE
: PT7    ( f3 f2 f1 -- ? )
   IF 1111 ROT ROT
      IF 2222 SWAP
         IF
            3333 MIX_UP
         THEN
         4444
      THEN
      5555
   THEN
   6666
;
: [1CS-ROLL] 1 CS-ROLL ; IMMEDIATE
T{ : PT8
      >R
      AHEAD 111
      BEGIN 222 
         [1CS-ROLL]
         THEN
         333
         R> 1- >R
         R@ 0<
      UNTIL
      R> DROP
   ; -> }T
T{ 1 PT8 -> 333 222 333 }T
TESTING done-pt8
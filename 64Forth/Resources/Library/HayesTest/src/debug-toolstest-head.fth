TESTING [IF] [ELSE] [THEN]

T{ TRUE  [IF] 111 [ELSE] 222 [THEN] -> 111 }T
T{ FALSE [IF] 111 [ELSE] 222 [THEN] -> 222 }T

T{ TRUE  [IF] 1     \ Code spread over more than 1 line
             2
          [ELSE]
             3
             4
          [THEN] -> 1 2 }T
T{ FALSE [IF]
             1 2
          [ELSE]
             3 4
          [THEN] -> 3 4 }T

T{ TRUE  [IF] 1 TRUE  [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 1 2 }T
T{ FALSE [IF] 1 TRUE  [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 4 }T
T{ TRUE  [IF] 1 FALSE [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 1 3 }T
T{ FALSE [IF] 1 FALSE [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 4 }T

\ ------------------------------------------------------------------------------
TESTING immediacy of [IF] [ELSE] [THEN]

T{ : PT2 [  0 ] [IF] 1111 [ELSE] 2222 [THEN]  ; PT2 -> 2222 }T
T{ : PT3 [ -1 ] [IF] 3333 [ELSE] 4444 [THEN]  ; PT3 -> 3333 }T
: PT9 BL WORD FIND ;
T{ PT9 [IF]   NIP -> 1 }T
T{ PT9 [ELSE] NIP -> 1 }T
T{ PT9 [THEN] NIP -> 1 }T

\ -----------------------------------------------------------------------------
TESTING [IF] and [ELSE] carry out a text scan by parsing and discarding words
\ so that an [ELSE] or [THEN] in a comment or string is recognised

: PT10 REFILL DROP REFILL DROP ;

T{ 0  [IF]            \ Words ignored up to [ELSE] 2
      [THEN] -> 2 }T
T{ -1 [IF] 2 [ELSE] 3 $" [THEN] 4 PT10 IGNORED TO END OF LINE"
      [THEN]          \ A precaution in case [THEN] in string isn't recognised
   -> 2 4 }T

\ -----------------------------------------------------------------------------
TESTING [ELSE] and [THEN] without a preceding [IF]

\ [ELSE] ... [THEN] acts like a multi-line comment
T{ [ELSE]
11 12 13
[THEN] 14 -> 14 }T

T{ [ELSE] -1 [IF] 15 [ELSE] 16 [THEN] 17 [THEN] 18 -> 18 }T

\ A lone [THEN] is a noop
T{ 19 [THEN] 20 -> 19 20 }T

\ ------------------------------------------------------------------------------
TESTING CS-PICK and CS-ROLL

\ Test PT5 based on example in ANS document p 176.

: ?REPEAT
   0 CS-PICK POSTPONE UNTIL
; IMMEDIATE

VARIABLE PT4

T{ : PT5  ( N1 -- )
      PT4 !
      BEGIN
         -1 PT4 +!
         PT4 @ 4 > 0= ?REPEAT \ Back TO BEGIN if FALSE
         111
         PT4 @ 3 > 0= ?REPEAT
         222
         PT4 @ 2 > 0= ?REPEAT
         333
         PT4 @ 1 =
      UNTIL
; -> }T

T{ 6 PT5 -> 111 111 222 111 222 333 111 222 333 }T


T{ : ?DONE POSTPONE IF 1 CS-ROLL ; IMMEDIATE -> }T  \ Same as WHILE
T{ : PT6
      >R
      BEGIN
         R@
      ?DONE
         R@
         R> 1- >R
      REPEAT
      R> DROP
   ; -> }T

T{ 5 PT6 -> 5 4 3 2 1 }T

: MIX_UP 2 CS-ROLL ; IMMEDIATE  \ CS-ROT

: PT7    ( f3 f2 f1 -- ? )
   IF 1111 ROT ROT         ( -- 1111 f3 f2 )     ( cs: -- orig1 )
      IF 2222 SWAP         ( -- 1111 2222 f3 )   ( cs: -- orig1 orig2 )
         IF                                      ( cs: -- orig1 orig2 orig3 )
            3333 MIX_UP    ( -- 1111 2222 3333 ) ( cs: -- orig2 orig3 orig1 )
         THEN                                    ( cs: -- orig2 orig3 )
         4444        \ Hence failure of first IF comes here and falls through
      THEN                                      ( cs: -- orig2 )
      5555           \ Failure of 3rd IF comes here
   THEN                                         ( cs: -- )
   6666              \ Failure of 2nd IF comes here
;

T{ -1 -1 -1 PT7 -> 1111 2222 3333 4444 5555 6666 }T
T{  0 -1 -1 PT7 -> 1111 2222 5555 6666 }T
T{  0  0 -1 PT7 -> 1111 0    6666 }T
T{  0  0  0 PT7 -> 0    0    4444 5555 6666 }T

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

\ ------------------------------------------------------------------------------
TESTING [DEFINED] [UNDEFINED]

CREATE DEF1
TESTING after-defined-header

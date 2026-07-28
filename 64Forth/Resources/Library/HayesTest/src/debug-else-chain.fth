: PT10 REFILL DROP REFILL DROP ;

TESTING string scan then orphan [ELSE]
T{ 0  [IF]            \ Words ignored up to [ELSE] 2
      [THEN] -> 2 }T
T{ -1 [IF] 2 [ELSE] 3 $" [THEN] 4 PT10 IGNORED TO END OF LINE"
      [THEN]          \ A precaution in case [THEN] in string isn't recognised
   -> 2 4 }T

TESTING [ELSE] and [THEN] without a preceding [IF]
T{ [ELSE]
11 12 13
[THEN] 14 -> 14 }T
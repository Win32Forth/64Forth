                                        \ \* PASY.PAS - clearer Tiny Pascal sample for PASCAL"
                                        \    Self-contained: no read/KEY. Use Write(#n) for numbers (. not EMIT).
                                        \    Exercises const, var, array, proc, for, while, repeat, if/else. *\
                                        \
                                        \ Program DEMO;
                                        \         const
                                        \           Limit = 5;

5 CONSTANT Limit                        \           Base = 10;
      
10 CONSTANT Base                        \         var
                                        \           idx, sum, n : Integer ;

VARIABLE idx
VARIABLE sum
VARIABLE n                              \         var
                                        \           squares : array [6] of Integer;

CREATE squares 48 ALLOT                 \
                                        \         Proc bump(x:integer);

VARIABLE x
: bump          x !                     \                 BEGIN
                                        \                         n := x + 1;
      x @ 1 + n !                       \                         sum := sum + n;
      sum @ n @ + sum !                 \                 END;
      ;                                 \
                                        \         BEGIN
                                        \                 newline;

: DEMO
      CR                                \                 Write('PASY demo: squares and sum');
      ." PASY demo: squares and sum "   \                 newline;
      CR                                \                 sum := 0;
      0 sum !                           \                 FOR idx := 0 to Limit
      0                                 \                 do      begin
      Limit 1 + SWAP
  DO                                    \                            squares[idx] := idx * idx;
      I idx !
      idx @ CELLS  idx @ idx @ * squares ROT + !
                                        \                            bump(squares[idx]);
      squares idx @ CELLS + @ bump      \                            Write('idx=',#idx);
      ." idx= "
      idx @ .                           \                            Write(' sq=',#squares[idx]);
      ."  sq= "
      squares idx @ CELLS + @ .         \                            Write(' sum=',#sum);
      ."  sum= "
      sum @ .                           \                            newline;
      CR                                \                         end;
      1
  +LOOP                                 \                 idx := 0;
      0 idx !                           \                 WHILE (idx < Limit)
      
  BEGIN   idx @ Limit <                 \                 do      begin
      
  WHILE                                 \                            idx := idx + 1;
      idx @ 1 + idx !                   \                         end;
      
  REPEAT                                \                 REPEAT
                                        \                         begin
      
  BEGIN                                 \                            n := n - 1;
      n @ 1 - n !                       \                         end;
                                        \                 until (n <= Base);
      n @ Base <=
  UNTIL                                 \                 IF (sum > Base)
      sum @ Base >                      \                 then  begin
      
  IF                                    \                         newline;
      CR                                \                         Write('Final sum is ',#sum,' (ok)');
      ." Final sum is  "
      sum @ .
      ."  (ok) "                        \                         newline;
      CR                                \                       end
                                        \                 else  begin
      
  ELSE                                  \                         newline;
      CR                                \                         Write('Unexpected small sum');
      ." Unexpected small sum "         \                         newline;
      CR                                \                       end;
      
  THEN                                  \         END.
      
  ;



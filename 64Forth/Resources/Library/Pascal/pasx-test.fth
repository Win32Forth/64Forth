23 CONSTANT bill                        \           george = 72;
      
72 CONSTANT george                      \         var
                                        \           Factor,test : Integer ;

VARIABLE Factor 
VARIABLE test                           \         var
                                        \           bulgogi, kimchee : array [23] of Integer;

CREATE bulgogi 184 ALLOT 
CREATE kimchee 184 ALLOT                \ 
                                        \         Proc bingo(myvar:integer);

VARIABLE myvar 
: bingo         myvar !                 \                 BEGIN
                                        \                         myvar := myvar+3;
      myvar @ 3 + myvar !               \                         Factor := myvar;
      myvar @ Factor !                  \                 END;
      ;                                 \ 
                                        \         BEGIN   newline;

: DEMO          
      CR                                \                 read(test);
      KEY DUP EMIT test !               \                 Write('hello',345);
      ." hello " 
      345 EMIT                          \                 read(test,Factor,bulgogi[3]);
      KEY DUP EMIT test ! 
      KEY DUP EMIT Factor ! 
      KEY DUP EMIT bulgogi 3 CELLS +  ! 
                                        \                 write(test,Factor,bulgogi[3]);
      test @ EMIT 
      Factor @ EMIT 
      bulgogi 3 CELLS + @ EMIT          \                 Write('Enter a number greater than 100:');
      ." Enter a number greater than 100: " 
                                        \                 read(#test);
      KEY test !                        \                 bulgogi[Factor] := Factor;
      Factor @ CELLS  Factor @ bulgogi ROT + ! 
                                        \                 bingo(bulgogi[Factor]);
      bulgogi Factor @ CELLS + @ bingo  \                 Factor := 100;
      100 Factor !                      \                 FOR test := 0 to bill
      0                                 \                 do      begin
      bill 1 + SWAP 
  DO                                    \                            bulgogi[test] := kimchee[test];
      I test ! 
      test @ CELLS  kimchee test @ CELLS + @ bulgogi ROT + ! 
                                        \                            read(kimchee[test]);
      KEY DUP EMIT kimchee test @ CELLS +  ! 
                                        \                         end;
      1 
  +LOOP                                 \                 mem[test] := 0;
      test @ 0 SWAP !                   \                 WHILE (test < bill)
      
  BEGIN   test @ bill <                 \                 do      begin
      
  WHILE                                 \                            bulgogi[test] := kimchee[test];
      test @ CELLS  kimchee test @ CELLS + @ bulgogi ROT + ! 
                                        \                            test := test+1;
      test @ 1 + test !                 \                         end;
      
  REPEAT                                \                 test := 0;
      0 test !                          \                 REPEAT
                                        \                         begin
      
  BEGIN                                 \                            bulgogi[test] := kimchee[test];
      test @ CELLS  kimchee test @ CELLS + @ bulgogi ROT + ! 
                                        \                            test := test+1;
      test @ 1 + test !                 \                         end;
                                        \                 until (test>=bill);
      test @ bill >= 
  UNTIL                                 \                 IF (factor - 1) < test
      Factor @ 1 -                      \                 then  begin
      test @ < 
  IF                                    \                         newline;
      CR                                \                         Write('Factor is ',#factor);
      ." Factor is  " 
      Factor @ .                        \                         newline;
      CR                                \                         Write('You entered ',#test);
      ." You entered  " 
      test @ .                          \                       end
                                        \                 else  begin
      
  ELSE                                  \                         newline;
      CR                                \                         Write('You entered a number less than 100');
      ." You entered a number less than 100 " 
                                        \                       end;
      
  THEN                                  \         END.
      
  ;  


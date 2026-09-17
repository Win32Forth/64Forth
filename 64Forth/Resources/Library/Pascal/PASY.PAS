\* PASY.PAS - clearer Tiny Pascal sample for PASCAL"
   Self-contained: no read/KEY. Use Write(#n) for numbers (. not EMIT).
   Exercises const, var, array, proc, for, while, repeat, if/else. *\

Program DEMO;
        const
          Limit = 5;
          Base = 10;
        var
          idx, sum, n : Integer ;
        var
          squares : array [6] of Integer;

        Proc bump(x:integer);
                BEGIN
                        n := x + 1;
                        sum := sum + n;
                END;

        BEGIN
                newline;
                Write('PASY demo: squares and sum');
                newline;
                sum := 0;
                FOR idx := 0 to Limit
                do      begin
                           squares[idx] := idx * idx;
                           bump(squares[idx]);
                           Write('idx=',#idx);
                           Write(' sq=',#squares[idx]);
                           Write(' sum=',#sum);
                           newline;
                        end;
                idx := 0;
                WHILE (idx < Limit)
                do      begin
                           idx := idx + 1;
                        end;
                REPEAT
                        begin
                           n := n - 1;
                        end;
                until (n <= Base);
                IF (sum > Base)
                then  begin
                        newline;
                        Write('Final sum is ',#sum,' (ok)');
                        newline;
                      end
                else  begin
                        newline;
                        Write('Unexpected small sum');
                        newline;
                      end;
        END.

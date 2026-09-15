\* A sample pascal program to compile with PASCAL.COM the pascal translator *\

Program DEMO;
        const
          bill = 23;
          george = 72;
        var
          Factor,test : Integer ;
        var
          bulgogi, kimchee : array [23] of Integer;

        Proc bingo(myvar:integer);
                BEGIN
                        myvar := myvar+3;
                        Factor := myvar;
                END;

        BEGIN   newline;
                read(test);
                Write('hello',345);
                read(test,Factor,bulgogi[3]);
                write(test,Factor,bulgogi[3]);
                Write('Enter a number greater than 100:');
                read(#test);
                bulgogi[Factor] := Factor;
                bingo(bulgogi[Factor]);
                Factor := 100;
                FOR test := 0 to bill
                do      begin
                           bulgogi[test] := kimchee[test];
                           read(kimchee[test]);
                        end;
                mem[test] := 0;
                WHILE (test < bill)
                do      begin
                           bulgogi[test] := kimchee[test];
                           test := test+1;
                        end;
                test := 0;
                REPEAT
                        begin
                           bulgogi[test] := kimchee[test];
                           test := test+1;
                        end;
                until (test>=bill);
                IF (factor - 1) < test
                then  begin
                        newline;
                        Write('Factor is ',#factor);
                        newline;
                        Write('You entered ',#test);
                      end
                else  begin
                        newline;
                        Write('You entered a number less than 100');
                      end;
        END.


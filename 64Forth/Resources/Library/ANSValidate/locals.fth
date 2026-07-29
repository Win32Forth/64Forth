\ locals.fth — ANS Locals spot-checks from TZForth ANS-VALIDATE / FTEST
\
\ Requires: tester.fth already loaded
\ LOCALS|  {: … :}  TO for locals
\
\ NOT a formal ANS certificate. Prefer Hayes localstest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Locals ===) CR

\ --- LOCALS| pass-through ---
: LO-A  LOCALS| x | x ;
10 LO-A 10 = S" LOCALS|" EXPECT

\ --- LOCALS| TO ---
: LO-B  LOCALS| x | 5 TO x x ;
0 LO-B 5 = S" LOCALS|-TO" EXPECT

\ --- {: two args order: TOS is last named ---
\ TZForth: {: a b | c :} b . a .  with 3 4 → prints 4 3
: LO-C  {: a b -- n :} a b + ;
3 4 LO-C 7 = S" brace-add" EXPECT

: LO-D  {: a b -- n :} b ;
3 4 LO-D 4 = S" brace-TOS" EXPECT

: LO-E  {: a b -- n :} a ;
3 4 LO-E 3 = S" brace-NOS" EXPECT

\ --- {: TO ---
: LO-F  {: a -- n :} a 1+ TO a a ;
10 LO-F 11 = S" brace-TO" EXPECT

\ --- LOCALS| in DO LOOP ---
: LO-G  LOCALS| r | 3 0 DO I r + TO r LOOP r ;
1 LO-G 4 = S" LOCALS|-DO" EXPECT

\ --- multiple locals ---
: LO-H  LOCALS| x y | x y * ;
5 6 LO-H 30 = S" LOCALS|-2" EXPECT

\ --- {: with value local ---
: LO-I  {: a | b -- n :} a 2* TO b b ;
7 LO-I 14 = S" brace-val" EXPECT

\ --- ENVIRONMENT? ---
S" LOCALS" ENVIRONMENT? NIP S" ENV-LOCALS" EXPECT
S" #LOCALS" ENVIRONMENT? DROP 32 = S" ENV-#LOCALS" EXPECT

\ --- nest: call word with locals from another ---
: LO-J  {: n -- m :} n 1+ ;
: LO-K  {: n -- m :} n LO-J ;
5 LO-K 6 = S" nest-locals" EXPECT

ONLY FORTH

CR .( --- Locals batch done ---) CR

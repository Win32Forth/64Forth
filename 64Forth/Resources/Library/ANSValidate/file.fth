\ file.fth — ANS File-Access spot-checks
\
\ Requires: tester.fth already loaded
\ Uses /tmp so the suite does not depend on Documents cwd.
\ Host FileAccess must be installed - works in the app; CLI harness needs file_op.
\
\ NOT a formal ANS certificate. Prefer Hayes filetest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === File-Access ===) CR

VARIABLE FA-FID

\ --- CREATE-FILE ---
S" /tmp/64forth-ansval-fa.txt" R/W CREATE-FILE
0= S" CREATE-FILE" EXPECT
FA-FID !

\ --- WRITE-LINE ---
S" hello" FA-FID @ WRITE-LINE 0= S" WRITE-LINE" EXPECT

\ --- FLUSH-FILE ---
FA-FID @ FLUSH-FILE 0= S" FLUSH-FILE" EXPECT

\ --- FILE-POSITION ---
FA-FID @ FILE-POSITION
0= S" FILE-POS-ior" EXPECT
2DROP

\ --- REPOSITION to start ---
0 0 FA-FID @ REPOSITION-FILE 0= S" REPOSITION" EXPECT

\ --- READ-LINE ( c-addr u1 fileid -- u2 flag ior ) ---
PAD 80 FA-FID @ READ-LINE
0= S" READ-LINE-ior" EXPECT
\ stack: u2 flag
DROP 5 = S" READ-LINE-u" EXPECT

\ --- CLOSE-FILE ---
FA-FID @ CLOSE-FILE 0= S" CLOSE-FILE" EXPECT

\ --- OPEN-FILE R/O ---
S" /tmp/64forth-ansval-fa.txt" R/O OPEN-FILE
0= S" OPEN-FILE" EXPECT
FA-FID !
PAD 80 FA-FID @ READ-LINE
0= S" OPEN-READ-ior" EXPECT
DROP 5 = S" OPEN-READ-u" EXPECT
FA-FID @ CLOSE-FILE DROP

\ --- FILE-SIZE ---
S" /tmp/64forth-ansval-fa.txt" R/O OPEN-FILE
0= S" SIZE-OPEN" EXPECT
FA-FID !
FA-FID @ FILE-SIZE
0= S" FILE-SIZE-ior" EXPECT
OR 0= 0= S" FILE-SIZE-nz" EXPECT
FA-FID @ CLOSE-FILE DROP

\ --- FILE-STATUS ---
S" /tmp/64forth-ansval-fa.txt" FILE-STATUS
NIP 0= S" FILE-STATUS" EXPECT

\ --- RENAME-FILE ---
S" /tmp/64forth-ansval-fa.txt" S" /tmp/64forth-ansval-fa2.txt" RENAME-FILE
0= S" RENAME-FILE" EXPECT

\ --- DELETE-FILE ---
S" /tmp/64forth-ansval-fa2.txt" DELETE-FILE
0= S" DELETE-FILE" EXPECT

\ --- ENVIRONMENT? FILE - present after rebuild with env table update ---
: (FA-ENV)
  S" FILE" ENVIRONMENT?
  DUP 0= IF DROP TRUE ELSE NIP THEN ;
(FA-ENV) S" ENV-FILE" EXPECT

\ --- BIN create+delete smoke ---
S" /tmp/64forth-ansval-bin.dat" R/W BIN CREATE-FILE
0= S" BIN-CREATE" EXPECT
CLOSE-FILE DROP
S" /tmp/64forth-ansval-bin.dat" DELETE-FILE DROP

ONLY FORTH

.( --- File-Access batch done ---) .STACK-DEPTH CR

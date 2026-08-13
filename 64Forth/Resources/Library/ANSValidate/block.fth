\ block.fth -- ANS Block spot-checks
\
\ Requires: tester.fth already loaded
\ Creates a small writable volume under /tmp.
\ Prefer Hayes blocktest.fth + prepare-blocks.fth for the full suite.
\
\ CRITICAL: no interpret-time IF/ELSE/THEN/BEGIN -- stack helpers are colon-only.
\ NOT a formal ANS certificate.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Block ===) CR

\ Stack helpers (BEGIN only inside colon words)
: (BL-CLEAR)  BEGIN DEPTH WHILE DROP REPEAT ;
: (BL-1)  BEGIN DEPTH 1 > WHILE SWAP DROP REPEAT ;

\ --- ENVIRONMENT? ---
S" BLOCK" ENVIRONMENT? NIP S" ENV-BLOCK" EXPECT

\ --- create a 4-block volume ---
S" /tmp/64forth-ansval.blk" DELETE-FILE DROP
S" /tmp/64forth-ansval.blk" 4 CREATE-BLOCK-FILE
0= S" CREATE-BLOCK-FILE" XEXPECT
\ leave only fileid (CREATE-BLOCK-FILE may leave loop junk below)
(BL-1)
USE-BLOCK-FILE
(BL-CLEAR)

\ --- blank block is spaces ---
0 BLOCK C@ BL = S" BLOCK-blank" EXPECT

\ --- C! into buffer ---
1 BLOCK
90 OVER C!
C@ 90 = S" BLOCK-C!" EXPECT

\ --- UPDATE + SAVE-BUFFERS keep value ---
UPDATE
SAVE-BUFFERS
1 BLOCK C@ 90 = S" BLOCK-save" EXPECT

\ --- EMPTY-BUFFERS then reload ---
EMPTY-BUFFERS
1 BLOCK C@ 90 = S" BLOCK-reload" EXPECT

\ --- BUFFER ---
2 BUFFER 0= 0= S" BUFFER" EXPECT

\ --- FLUSH ---
2 BLOCK
89 OVER C!
UPDATE
FLUSH
EMPTY-BUFFERS
2 BLOCK C@ 89 = S" FLUSH" EXPECT

\ --- SCR ---
1 SCR !
SCR @ 1 = S" SCR" EXPECT

\ --- LOAD a one-liner from block 3 ---
3 BLOCK 1024 BLANK
S" : BL-T 33 ;" 3 BLOCK SWAP CMOVE
UPDATE SAVE-BUFFERS EMPTY-BUFFERS
3 LOAD
BL-T 33 = S" LOAD" EXPECT
\ BLK must be 0 again after LOAD (kernel source-stack restores it)
BLK @ 0= S" BLK-restore" EXPECT

\ --- close and restore interpreter state for later modules ---
EMPTY-BUFFERS
BLOCK-FILE @ CLOSE-BLOCK-FILE 0= S" CLOSE-BLOCK-FILE" EXPECT
S" /tmp/64forth-ansval.blk" DELETE-FILE DROP
0 BLK !
0 SCR !
(BL-CLEAR)
ONLY FORTH DEFINITIONS

.( --- Block batch done ---) .STACK-DEPTH CR

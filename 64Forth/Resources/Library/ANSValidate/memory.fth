\ memory.fth — ANS Memory-Allocation spot-checks
\
\ Requires: tester.fth already loaded
\ ALLOCATE ( u -- a-addr ior )
\ FREE     ( a-addr -- ior )
\ RESIZE   ( a-addr1 u -- a-addr2 ior )
\
\ NOT a formal ANS certificate. Prefer Hayes memorytest.fth.

DECIMAL
ONLY FORTH DEFINITIONS

CR .( === Memory-Allocation ===) CR

VARIABLE MA-A

\ --- ALLOCATE + store/fetch ---
64 ALLOCATE DROP MA-A !
42 MA-A @ !
MA-A @ @ 42 = S" ALLOCATE-store" EXPECT

\ --- FREE ---
MA-A @ FREE 0= S" FREE" EXPECT

\ --- ALLOCATE ior = 0 ---
128 ALLOCATE NIP 0= S" ALLOCATE-ior" EXPECT

\ --- RESIZE grow ---
64 ALLOCATE DROP MA-A !
MA-A @ 256 RESIZE        \ a2 ior
0= S" RESIZE-ior" EXPECT \ a2 remains
MA-A !
99 MA-A @ !
MA-A @ @ 99 = S" RESIZE-store" EXPECT
MA-A @ FREE DROP

\ --- 1-byte region ---
1 ALLOCATE DROP MA-A !
1 MA-A @ C!
MA-A @ C@ 1 = S" ALLOC-1" EXPECT
MA-A @ FREE DROP

\ --- ENVIRONMENT? ---
S" MEMORY-ALLOCATION" ENVIRONMENT? NIP S" ENV-MEM" EXPECT

\ --- UNUSED ---
UNUSED 0 > S" UNUSED" EXPECT

.( --- Memory-Allocation batch done ---) .STACK-DEPTH CR

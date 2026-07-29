\ prepare-blocks.fth — vendor harness (not an ANS test case)
\ Location: HayesTest/src/Harness/
\
\ App-bundled Resources/Library (including HayesTest/src/blocks.blk) is
\ read-only. Block tests need UPDATE/FLUSH, so select a writable .blk under
\ Application Support before blocktest.fth runs.
\
\ Path (~ expands via host FileAccess):
\   ~/Library/Application Support/64Forth/hayes-blocks.blk
\
\ Needs enough blocks for blocktest (FIRST-TEST-BLOCK=20 … LIMIT=30).
\ Creates 64 blocks if the file does not exist yet.
\
\ Note: use ." (compile-time string) not .( inside colon definitions.
\ .( is immediate and prints while the definition is being compiled.

DECIMAL

: PREPARE-HAYES-BLOCKS ( -- )
   S" ~/Library/Application Support/64Forth/hayes-blocks.blk"
   2DUP OPEN-BLOCK-FILE                 \ ( c-addr u bid ior )
   DUP 0= IF                            \ open succeeded
      DROP                              \ ( c-addr u bid )
      NIP NIP USE-BLOCK-FILE
      ." prepare-blocks: using hayes-blocks.blk" CR
   ELSE                                 \ ( c-addr u bid ior )
      2DROP                             \ drop ior bid → ( c-addr u )
      2DUP DELETE-FILE DROP             \ ignore missing-file delete error
      64 CREATE-BLOCK-FILE              \ ( bid ior )
      DUP 0= IF
         DROP USE-BLOCK-FILE
         ." prepare-blocks: created hayes-blocks.blk" CR
      ELSE
         ." prepare-blocks: CREATE-BLOCK-FILE failed ior= " . CR
         DROP                           \ drop bid
      THEN
   THEN
;

PREPARE-HAYES-BLOCKS

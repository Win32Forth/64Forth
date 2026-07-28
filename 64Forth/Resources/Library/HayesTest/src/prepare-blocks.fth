\ prepare-blocks.fth — writable block volume for Hayes block tests
\
\ App-bundled Resources/Library (including HayesTest/src/blocks.blk) is
\ read-only. Block tests need UPDATE/FLUSH, so select a writable .blk under
\ Application Support before blocktest.fth runs.
\
\ Path (sandbox-friendly; ~ expands via host resolvedURL):
\   ~/Library/Application Support/TZForth/hayes-blocks.blk
\
\ Needs enough blocks for blocktest (FIRST-TEST-BLOCK=20 … LIMIT=30).
\ Creates 64 blocks if the file does not exist yet.
\
\ Stack notes (important):
\   OPEN-FILE / OPEN-BLOCK-FILE  ( c-addr u -- bid ior )
\   CREATE-BLOCK-FILE            ( c-addr u n -- bid ior )
\   USE-BLOCK-FILE               ( bid -- )
\   IF consumes the flag (ior). Do not DROP ior again after IF.

DECIMAL

: PREPARE-HAYES-BLOCKS ( -- )
   S" ~/Library/Application Support/TZForth/hayes-blocks.blk"
   2DUP OPEN-BLOCK-FILE                 \ ( c-addr u bid ior )
   DUP 0= IF                            \ open succeeded (ior = 0)
      DROP                              \ ( c-addr u bid )
      NIP NIP                           \ ( bid )
      USE-BLOCK-FILE
      .( prepare-blocks: using Application Support/TZForth/hayes-blocks.blk) CR
   ELSE                                 \ open failed
      DROP DROP                         \ drop ior bid → ( c-addr u )
      64 CREATE-BLOCK-FILE              \ ( bid ior )
      DUP 0= IF
         DROP                           \ ( bid )
         USE-BLOCK-FILE
         .( prepare-blocks: created Application Support/TZForth/hayes-blocks.blk) CR
      ELSE
         DROP DROP                      \ clean bid ior
         .( ? prepare-blocks: CREATE-BLOCK-FILE failed for hayes-blocks.blk) CR
      THEN
   THEN
;

PREPARE-HAYES-BLOCKS

\ High-level Forth bootstrap (interpreted once at startup)
\ Dictionary field helpers (xt = CFA from ' or FIND):
\   >LINK  ( xt -- a-addr )  LINK at CFA-16
\   >FLAGS ( xt -- a-addr )  FLAGS at CFA-8
\   >CODE  ( xt -- a-addr )  CFA itself
\   >BODY  ( xt -- a-addr )  CFA+8

\ DOC" needs SETDOC (CODE). Define DOC" first, then document HERE via redefine.
: DOC" 34 PARSE SETDOC ;
DOC" HERE ( -- addr ) current dictionary pointer (DP @)"
: HERE DP @ ;

\ --- 1. Simple ANS helpers ---
DOC" CHAR+ ( addr -- addr' ) add size of one char"
: CHAR+ 1+ ;
DOC" CHARS ( n -- n ) chars to address units"
: CHARS ;
DOC" CELL+ ( addr -- addr' ) add size of one cell"
: CELL+ 8 + ;
DOC" CELLS ( n -- n ) cells to address units"
: CELLS 8 * ;
DOC" ALIGNED ( addr -- addr' ) next aligned address"
: ALIGNED 7 + 7 INVERT AND ;
DOC" ALIGN ( -- ) align DP to cell boundary"
: ALIGN HERE ALIGNED HERE - ALLOT ;
DOC" 2DUP ( n1 n2 -- n1 n2 n1 n2 ) duplicate pair"
: 2DUP OVER OVER ;
DOC" 2DROP ( n1 n2 -- ) drop two items"
: 2DROP DROP DROP ;
DOC" 2SWAP ( n1 n2 n3 n4 -- n3 n4 n1 n2 ) swap pairs"
: 2SWAP ROT >R ROT R> ;
DOC" 2OVER ( n1 n2 n3 n4 -- n1 n2 n3 n4 n1 n2 ) copy second pair"
: 2OVER >R >R 2DUP R> R> 2SWAP ;
DOC" COUNT ( c-addr -- addr u ) from counted string addr return char-addr and length"
: COUNT DUP C@ SWAP CHAR+ SWAP ;
DOC" /STRING ( c-addr u n -- c-addr' u' ) adjust string by n characters"
: /STRING DUP >R - SWAP R> + SWAP ;
DOC" DECIMAL ( -- ) set BASE to 10"
: DECIMAL 10 BASE ! ;
DOC" HEX ( -- ) set BASE to 16"
: HEX 16 BASE ! ;
\ 0<> 0> WITHIN U> are CODE primitives (boot table)
DOC" >= ( n1 n2 -- flag ) greater or equal"
: >= < 0= ;
DOC" <= ( n1 n2 -- flag ) less or equal"
: <= > 0= ;

\ --- 2. Dictionary field accessors (xt = CFA) ---
DOC" >LINK ( xt -- a-addr ) link field address"
: >LINK 16 - ;
DOC" >FLAGS ( xt -- a-addr ) flags field address"
: >FLAGS 8 - ;
DOC" >CODE ( xt -- a-addr ) code field (xt itself)"
: >CODE ;
DOC" >BODY ( xt -- addr ) data field of a CREATEd word"
: >BODY 8 + ;
\ Layout: HFA | NFA | LFA | FLAGS | CFA | BODY
\ FLAGS: 0-15 NFA_OFF, 16-31 HFA_OFF, 32-47 LINE, 48-62 FILE-ID, 63 IMM
DOC" NFA ( xt -- nfa ) name field address"
: NFA DUP >FLAGS @ 65535 AND - ;
DOC" >NAME ( xt -- nfa ) name field address (classic synonym for NFA)"
: >NAME NFA ;
DOC" >NFA ( xt -- nfa ) synonym for >NAME / NFA"
: >NFA NFA ;
DOC" HFA ( xt -- hfa ) help field address"
: HFA DUP >FLAGS @ 16 RSHIFT 65535 AND - ;
DOC" VIEW-LINE ( xt -- u ) 1-based source line in FLAGS (0=none)"
: VIEW-LINE >FLAGS @ 32 RSHIFT 65535 AND ;
DOC" VIEW-FILE# ( xt -- u ) source file-id in FLAGS (0=none)"
: VIEW-FILE# >FLAGS @ 48 RSHIFT 32767 AND ;
DOC" NAME>STRING ( nt -- c-addr u ) copy name token name to buffer (valid until next NAME>STRING)"
: NAME>STRING NFA COUNT ;
DOC" >HELP ( xt -- hfa ) help string"
: >HELP HFA ;
DOC" DOCOL? ( xt -- flag ) true if colon definition"
: DOCOL? @ DOCOL-ADDR = ;
DOC" SPACE ( -- ) emit one space"
: SPACE BL EMIT ;

\ --- 3. Control flow (immediate) ---
\ Order is strict:
\   1) BEGIN/UNTIL/AGAIN, IF/THEN/ELSE/WHILE/REPEAT  (no ?COMP needed)
\   2) ?COMP  (body uses IF/THEN)
\   3) AHEAD / DO / LOOP…  (compile a call to ?COMP)
DOC" BEGIN ( -- ) start indefinite loop (immediate)"
: BEGIN HERE ; IMMEDIATE
DOC" UNTIL ( flag -- ) loop until true (immediate)"
: UNTIL 0BRANCH-ADDR , HERE - , ; IMMEDIATE
DOC" AGAIN ( -- ) unconditional branch back (immediate)"
: AGAIN BRANCH-ADDR , HERE - , ; IMMEDIATE
DOC" IF ( flag -- ) conditional (immediate)"
: IF 0BRANCH-ADDR , HERE 0 , ; IMMEDIATE
DOC" THEN ( -- ) end of IF/ELSE (immediate)"
: THEN HERE OVER - SWAP ! ; IMMEDIATE
DOC" ELSE ( -- ) else part of IF (immediate)"
: ELSE BRANCH-ADDR , HERE 0 , SWAP HERE OVER - SWAP ! ; IMMEDIATE
DOC" WHILE ( flag -- ) conditional exit from BEGIN (immediate)"
: WHILE 0BRANCH-ADDR , HERE 0 , ; IMMEDIATE
DOC" REPEAT ( -- ) branch back from WHILE (immediate)"
: REPEAT BRANCH-ADDR , SWAP HERE - , HERE OVER - SWAP ! ; IMMEDIATE
DOC" ?COMP ( -- ) error if not compiling"
: ?COMP STATE @ 0= IF S" compile only" TYPE CR -14 THROW THEN ;
DOC" AHEAD ( -- orig ) compile forward branch (immediate; resolve with THEN)"
: AHEAD ?COMP BRANCH-ADDR , HERE 0 , ; IMMEDIATE

\ DO/LOOP: ( limit start -- )
\ DO leaves ( 0 dest ); ?DO leaves ( orig dest )
DOC" DO ( limit start -- ) start counted loop"
: DO ?COMP ['] (DO) , 0 HERE ; IMMEDIATE
DOC" ?DO ( limit start -- ) start counted loop that skips if start==limit"
: ?DO ?COMP ['] (?DO) , HERE 0 , HERE ; IMMEDIATE
DOC" LOOP ( -- ) end DO loop (add 1 to index, branch back if < limit)"
: LOOP ?COMP ['] (LOOP) , HERE - , ?DUP IF HERE OVER - SWAP ! THEN ; IMMEDIATE
DOC" +LOOP ( n -- ) end DO loop with custom increment (delta from stack)"
: +LOOP ?COMP ['] (+LOOP) , HERE - , ?DUP IF HERE OVER - SWAP ! THEN ; IMMEDIATE

\ --- 4. Defining words / parse helpers ---
DOC" CHAR ( 'name' -- char ) first character of next word"
: CHAR BL WORD COUNT DROP C@ ;
DOC" [CHAR] ( 'name' -- ) compile first char of name as literal (immediate)"
: [CHAR] ?COMP CHAR LIT-ADDR , , ; IMMEDIATE
DOC" VARIABLE ( 'name' -- ) create a variable"
: VARIABLE CREATE 0 , ;
DOC" CONSTANT ( x 'name' -- ) create a constant"
: CONSTANT CREATE , DOES> @ ;
DOC" RECURSE ( -- ) recurse into current definition (immediate)"
: RECURSE ?COMP LAST , ; IMMEDIATE

\ --- Search-Order / VOCABULARY ---
DOC" VOCABULARY ( 'name' -- ) named word list; execute to push onto search order"
: VOCABULARY CREATE WORDLIST DROP DOES> PUSH-ORDER ;
DOC" BIG-INTEGER ( -- ) vocabulary for big-integer extensions; execute to ALSO it"
VOCABULARY BIG-INTEGER
DOC" EDITOR ( -- ) vocabulary for editor extensions; execute to ALSO it"
VOCABULARY EDITOR
DOC" ASSEMBLER ( -- ) vocabulary for assembler extensions; execute to ALSO it"
VOCABULARY ASSEMBLER
DOC" FP ( -- ) vocabulary for floating-point word set; execute to ALSO it"
VOCABULARY FP

ONLY FORTH DEFINITIONS


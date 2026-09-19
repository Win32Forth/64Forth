\ dbg-map.fth — debug-time colon token maps (autoload-on-top)
\
\ Own body-walk (Emitter-style rules; no Emitter FLOAD).
\ ALLOCATE arena persists for the process; prune on ANEW-HOOK.
\ Prefer IF/ELSE/THEN over EXIT inside {: … :} (locals frame safety).
\
\ Search order must include SYSVOC: DBG-CFA@ / (LOOP) / … live there.
\ Prereqs: SZ-EDITOR loaded (SZ-TBUF / SZ-HIGHLIGHT-SPAN).
\ Load: Hyper/hyper.fth does FROMLIB FLOAD Hyper/dbg-map.fth

ONLY FORTH ALSO SYSVOC ALSO EDITOR

[UNDEFINED] SZ-TBUF [IF]
  .( dbg-map: need Editor first — FROMLIB FLOAD Editor/SZ-EDITOR.fth ) CR
[ELSE]
[UNDEFINED] SZ-HIGHLIGHT-SPAN [IF]
  .( dbg-map: need SZ-HIGHLIGHT-SPAN — reload updated Editor/sz-edit.fth ) CR
[ELSE]
[UNDEFINED] SZ-SKIP-COMMENT [IF]
  .( dbg-map: need SZ-SKIP-COMMENT — reload updated Editor/sz-edit.fth ) CR
[ELSE]

[UNDEFINED] ANEW-HOOK [IF]
  FORTH DEFINITIONS
  DEFER ANEW-HOOK
  : ANEW-HOOK-NOP  ( -- )  ;
  ' ANEW-HOOK-NOP IS ANEW-HOOK
  .( dbg-map: note — kernel ANEW-HOOK missing; local DEFER until rebuild) CR
[THEN]

[UNDEFINED] DBG-CFA@ [IF]
  FORTH DEFINITIONS
  : DBG-CFA@   ( -- cfa|0 )  0 ;
  : DBG-BODY#  ( -- u )      0 ;
  : DBG-IP@    ( -- ip )     0 ;
  : DBG-XT@    ( -- xt )     0 ;
  .( dbg-map: note — DBG-CFA@/BODY# stubs; rebuild kernel for real maps) CR
[THEN]

\ Define maps into HYPER-VOC; keep SYSVOC+EDITOR visible for compile.
ONLY FORTH ALSO SYSVOC ALSO HYPER-VOC DEFINITIONS
ALSO EDITOR

0 CONSTANT DBG-K-EMPTY
1 CONSTANT DBG-K-CALL
2 CONSTANT DBG-K-LIT
3 CONSTANT DBG-K-SLIT
4 CONSTANT DBG-K-BR
5 CONSTANT DBG-K-EXIT

5 CONSTANT DBG-SLOT-CELLS
512 CONSTANT DBG-MAP-MAX-CELLS
4 CONSTANT DBG-FSEC-CELLS
5 CONSTANT DBG-CMAP-HDR

0 VALUE DBG-MAP-ROOT
0 VALUE DBG-HL-NAME-XT
0 VALUE DBG-HL-SPAN-XT
0 VALUE DBG-HL-HIST-CLR-XT

CREATE DBG-MAP-NAME  64 ALLOT

: DBG-SLOT  ( cmap cell# -- addr )
  {: cmap cell# -- :}
  cmap DBG-CMAP-HDR CELLS +  cell# DBG-SLOT-CELLS * CELLS + ;

: DBG-SLOT-KIND!  ( x cmap cell# -- )  DBG-SLOT ! ;
: DBG-SLOT-KIND@  ( cmap cell# -- x )  DBG-SLOT @ ;
: DBG-SLOT-XT!    ( x cmap cell# -- )  DBG-SLOT CELL+ ! ;
: DBG-SLOT-XT@    ( cmap cell# -- x )  DBG-SLOT CELL+ @ ;
: DBG-SLOT-PAY!   ( x cmap cell# -- )  DBG-SLOT 2 CELLS + ! ;
: DBG-SLOT-PAY@   ( cmap cell# -- x )  DBG-SLOT 2 CELLS + @ ;
: DBG-SLOT-OFF!   ( x cmap cell# -- )  DBG-SLOT 3 CELLS + ! ;
: DBG-SLOT-OFF@   ( cmap cell# -- x )  DBG-SLOT 3 CELLS + @ ;
: DBG-SLOT-LEN!   ( x cmap cell# -- )  DBG-SLOT 4 CELLS + ! ;
: DBG-SLOT-LEN@   ( cmap cell# -- x )  DBG-SLOT 4 CELLS + @ ;

: DBG-CMAP-CFA@     ( cmap -- cfa )  CELL+ @ ;
: DBG-CMAP-NCELLS@  ( cmap -- n )    2 CELLS + @ ;
: DBG-CMAP-TBUF@   ( cmap -- a )    3 CELLS + @ ;
: DBG-CMAP-FSEC@   ( cmap -- s )    4 CELLS + @ ;

: DBG-MAP-FREE-CMAP  ( cmap -- )
  {: cmap -- :}
  cmap IF  cmap FREE DROP  THEN ;

: DBG-MAP-FREE-SECTION  ( fsec -- )
  {: fsec | cmap next -- :}
  fsec IF
     fsec 2 CELLS + @ TO cmap
     BEGIN  cmap  WHILE
        cmap @ TO next
        cmap DBG-MAP-FREE-CMAP
        next TO cmap
     REPEAT
     fsec FREE DROP
  THEN ;

: DBG-MAP-PRUNE  ( -- )
  {: | fsec prev next cmap cn nextc keep -- :}
  0 TO prev
  DBG-MAP-ROOT TO fsec
  BEGIN  fsec  WHILE
     fsec @ TO next
     0 TO keep
     fsec 2 CELLS + @ TO cmap
     0 fsec 2 CELLS + !
     BEGIN  cmap  WHILE
        cmap @ TO nextc
        cmap DBG-CMAP-CFA@ TO cn
        cn IF
           cn DOCOL? IF
              keep IF  cmap keep !  ELSE  cmap fsec 2 CELLS + !  THEN
              cmap TO keep
              0 cmap !
           ELSE
              cmap DBG-MAP-FREE-CMAP
           THEN
        ELSE
           cmap DBG-MAP-FREE-CMAP
        THEN
        nextc TO cmap
     REPEAT
     fsec 2 CELLS + @ 0= IF
        prev IF  next prev !  ELSE  next TO DBG-MAP-ROOT  THEN
        fsec DBG-MAP-FREE-SECTION
     ELSE
        fsec TO prev
     THEN
     next TO fsec
  REPEAT ;

: DBG-MAP-CLEAR  ( -- )
  {: | fsec next -- :}
  DBG-MAP-ROOT TO fsec
  0 TO DBG-MAP-ROOT
  BEGIN  fsec  WHILE
     fsec @ TO next
     fsec DBG-MAP-FREE-SECTION
     next TO fsec
  REPEAT ;

: DBG-MAP-DISCARD-FILE  ( file# -- )
  {: file# | fsec prev next -- :}
  0 TO prev
  DBG-MAP-ROOT TO fsec
  BEGIN  fsec  WHILE
     fsec @ TO next
     fsec CELL+ @ file# = IF
        prev IF  next prev !  ELSE  next TO DBG-MAP-ROOT  THEN
        fsec DBG-MAP-FREE-SECTION
     ELSE
        fsec TO prev
     THEN
     next TO fsec
  REPEAT ;

' DBG-MAP-PRUNE IS ANEW-HOOK

: DBG-MAP-FIND-FILE  ( file# -- fsec|0 )
  {: file# | fsec found -- :}
  0 TO found
  DBG-MAP-ROOT TO fsec
  BEGIN  fsec found 0= AND  WHILE
     fsec CELL+ @ file# = IF
        fsec TO found
     ELSE
        fsec @ TO fsec
     THEN
  REPEAT
  found ;

: DBG-MAP-ENSURE-FILE  ( file# -- fsec|0 )
  {: file# | fsec a ior -- :}
  file# DBG-MAP-FIND-FILE TO fsec
  fsec 0= IF
     DBG-FSEC-CELLS CELLS ALLOCATE TO ior  TO a
     ior IF
        0 TO fsec
     ELSE
        a TO fsec
        DBG-MAP-ROOT fsec !
        file# fsec CELL+ !
        0 fsec 2 CELLS + !
        0 fsec 3 CELLS + !
        fsec TO DBG-MAP-ROOT
     THEN
  THEN
  fsec ;

: DBG-MAP-FIND-CFA  ( cfa -- cmap|0 )
  {: cfa | fsec cmap found -- :}
  0 TO found
  DBG-MAP-ROOT TO fsec
  BEGIN  fsec found 0= AND  WHILE
     fsec 2 CELLS + @ TO cmap
     BEGIN  cmap found 0= AND  WHILE
        cmap DBG-CMAP-CFA@ cfa = IF
           cmap TO found
        ELSE
           cmap @ TO cmap
        THEN
     REPEAT
     found 0= IF  fsec @ TO fsec  THEN
  REPEAT
  found ;

: DBG-BR-OP?  ( xt -- flag )
  {: xt | f -- :}
  FALSE TO f
  xt 0BRANCH-ADDR = IF  TRUE TO f  THEN
  xt BRANCH-ADDR = IF  TRUE TO f  THEN
  xt ['] (LOOP) = IF  TRUE TO f  THEN
  xt ['] (+LOOP) = IF  TRUE TO f  THEN
  xt ['] (?DO) = IF  TRUE TO f  THEN
  f ;

: DBG-SLIT-SKIP  ( addr -- addr' )
  {: addr -- :}
  addr @  addr 8 + +  7 + -8 AND ;

: DBG-COLON-BYTES  ( cfa -- bytes )
  {: cfa | addr lim xt done bytes -- :}
  0 TO bytes
  FALSE TO done
  cfa DOCOL? IF
     cfa >BODY TO addr
     addr 8 + TO lim
     BEGIN  done 0=  WHILE
        addr lim U< IF
           addr @ TO xt
           xt ['] EXIT = IF
              addr 8 + TO addr
           ELSE
              xt LIT-ADDR = IF
                 addr 16 + TO addr
                 addr lim MAX TO lim
              ELSE
                 xt DBG-BR-OP? IF
                    addr 8 + @ addr 8 + + lim MAX TO lim
                    addr 16 + TO addr
                    addr lim MAX TO lim
                 ELSE
                    xt SLIT-ADDR = IF
                       addr 8 + DBG-SLIT-SKIP TO addr
                       addr lim MAX TO lim
                    ELSE
                       addr 8 + TO addr
                       addr lim MAX TO lim
                    THEN
                 THEN
              THEN
           THEN
        ELSE
           lim cfa >BODY - TO bytes
           TRUE TO done
        THEN
     REPEAT
  THEN
  bytes ;

: DBG-SLOT-CLEAR  ( cmap cell# -- )
  {: cmap cell# -- :}
  DBG-K-EMPTY cmap cell# DBG-SLOT-KIND!
  0 cmap cell# DBG-SLOT-XT!
  0 cmap cell# DBG-SLOT-PAY!
  0 cmap cell# DBG-SLOT-OFF!
  0 cmap cell# DBG-SLOT-LEN! ;

: DBG-MAP-FILL-BODY  ( cmap -- )
  {: cmap | body ncells cell# xt -- :}
  cmap DBG-CMAP-CFA@ >BODY TO body
  cmap DBG-CMAP-NCELLS@ TO ncells
  0 TO cell#
  BEGIN  cell# ncells < WHILE
     body cell# CELLS + @ TO xt
     xt LIT-ADDR = IF
        DBG-K-LIT cmap cell# DBG-SLOT-KIND!
        0 cmap cell# DBG-SLOT-XT!
        body cell# 1+ CELLS + @ cmap cell# DBG-SLOT-PAY!
        0 cmap cell# DBG-SLOT-OFF!
        0 cmap cell# DBG-SLOT-LEN!
        cell# 1+ TO cell#
        cell# ncells < IF  cmap cell# DBG-SLOT-CLEAR  THEN
        cell# 1+ TO cell#
     ELSE
        xt SLIT-ADDR = IF
           DBG-K-SLIT cmap cell# DBG-SLOT-KIND!
           0 cmap cell# DBG-SLOT-XT!
           body cell# 1+ CELLS + @ cmap cell# DBG-SLOT-PAY!
           0 cmap cell# DBG-SLOT-OFF!
           0 cmap cell# DBG-SLOT-LEN!
           body cell# CELLS + 8 + DBG-SLIT-SKIP body - 8 / TO cell#
        ELSE
           xt DBG-BR-OP? IF
              DBG-K-BR cmap cell# DBG-SLOT-KIND!
              xt cmap cell# DBG-SLOT-XT!
              body cell# 1+ CELLS + @ cmap cell# DBG-SLOT-PAY!
              0 cmap cell# DBG-SLOT-OFF!
              0 cmap cell# DBG-SLOT-LEN!
              cell# 1+ TO cell#
              cell# ncells < IF  cmap cell# DBG-SLOT-CLEAR  THEN
              cell# 1+ TO cell#
           ELSE
              xt ['] EXIT = IF
                 DBG-K-EXIT cmap cell# DBG-SLOT-KIND!
              ELSE
                 DBG-K-CALL cmap cell# DBG-SLOT-KIND!
              THEN
              xt cmap cell# DBG-SLOT-XT!
              0 cmap cell# DBG-SLOT-PAY!
              0 cmap cell# DBG-SLOT-OFF!
              0 cmap cell# DBG-SLOT-LEN!
              cell# 1+ TO cell#
           THEN
        THEN
     THEN
  REPEAT ;

: DBG-MAP-LOAD-NAME  ( cfa -- )
  {: cfa | a u -- :}
  cfa NAME>STRING TO u TO a
  u 63 MIN TO u
  u DBG-MAP-NAME C!
  a DBG-MAP-NAME CHAR+ u CMOVE ;

\ Whole-word search for SZ-TOKEN in [from, limit).
\ Skips \…EOL / ( … ) so names inside comments are not hits
\ (e.g. "(SLURP)" in "\ empty file: (SLURP) …").
\ No {: :} locals — SZ-SKIP-COMMENT uses >R; EXIT-in-locals hangs the app.
: DBG-SEARCH-TO  ( from limit -- addr|0 )
  >R                                    \ R: limit
  BEGIN
     DUP R@ U< 0= IF  R> 2DROP 0 EXIT  THEN
     DUP R@ SZ-SKIP-COMMENT
     2DUP = IF
        DROP
        DUP SZ-TOKEN C@ + R@ U> IF  R> 2DROP 0 EXIT  THEN
        DUP SZ-WORD-HIT? IF  R> DROP EXIT  THEN
        1+
     ELSE
        NIP
     THEN
  AGAIN
;

: DBG-BLANK?  ( c -- flag )
  {: c | f -- :}
  FALSE TO f
  c BL = IF  TRUE TO f  THEN
  c 9 = IF  TRUE TO f  THEN
  c 10 = IF  TRUE TO f  THEN
  c 13 = IF  TRUE TO f  THEN
  f ;

\ beg = after ": NAME"; end = ";" of this definition (or TEND).
: DBG-MAP-SRC-WINDOW  ( cfa -- beg end )
  {: cfa | from nameu colon after beg end found blank -- :}
  0 TO beg
  0 TO end
  SZ-TBUF IF
     cfa DBG-MAP-LOAD-NAME
     DBG-MAP-NAME C@ TO nameu
     nameu IF
        SZ-CUR @ DUP SZ-TBUF U< IF  DROP SZ-TBUF  THEN TO from
        1 SZ-TOKEN C!  [CHAR] : SZ-TOKEN 1+ C!
        from SZ-TEND DBG-SEARCH-TO TO colon
        colon 0= IF  SZ-TBUF SZ-TEND DBG-SEARCH-TO TO colon  THEN
        colon IF
           colon 1+ TO after
           BEGIN
              after SZ-TEND U< IF
                 after C@ DBG-BLANK? TO blank
                 blank
              ELSE
                 FALSE
              THEN
           WHILE
              after 1+ TO after
           REPEAT
           DBG-MAP-NAME C@ SZ-TOKEN C!
           DBG-MAP-NAME CHAR+ SZ-TOKEN CHAR+ DBG-MAP-NAME C@ CMOVE
           after SZ-WORD-HIT? IF
              after nameu + TO beg
              1 SZ-TOKEN C!  [CHAR] ; SZ-TOKEN 1+ C!
              beg SZ-TEND DBG-SEARCH-TO TO found
              found IF  found TO end  ELSE  SZ-TEND TO end  THEN
           THEN
        THEN
     THEN
  THEN
  beg end ;
\ Skip blanks and Forth comments; leave a at next code token.
\ Must use SZ-SKIP-COMMENT (1-char-word "\" / "(" only) — never treat
\ "(SLURP)" as a paren comment, and never write [CHAR] \.
\ No {: :} locals / no EXIT-in-locals (that locked up the DBG key loop).
: DBG-SKIP-NOISE  ( a end -- a' )
  >R                                    \ R: end
  BEGIN
     DUP R@ U< 0= IF  R> DROP EXIT  THEN
     DUP C@ DBG-BLANK? IF
        1+
     ELSE
        DUP R@ SZ-SKIP-COMMENT
        2DUP = IF  DROP R> DROP EXIT  THEN
        NIP
     THEN
  AGAIN
;

: DBG-SET-TOKEN  ( c-addr u -- )
  {: a u -- :}
  u 63 MIN TO u
  u SZ-TOKEN C!
  a SZ-TOKEN CHAR+ u CMOVE ;

: DBG-ALIAS-SETUP  ( kind xt -- )
  {: kind xt -- :}
  kind DBG-K-EXIT = IF
     S" ;" DBG-SET-TOKEN
  ELSE
     kind DBG-K-BR = IF
        xt 0BRANCH-ADDR = IF  S" IF" DBG-SET-TOKEN
        ELSE xt BRANCH-ADDR = IF  S" ELSE" DBG-SET-TOKEN
        ELSE xt ['] (LOOP) = IF  S" LOOP" DBG-SET-TOKEN
        ELSE xt ['] (+LOOP) = IF  S" +LOOP" DBG-SET-TOKEN
        ELSE xt ['] (?DO) = IF  S" ?DO" DBG-SET-TOKEN
        ELSE xt ['] (DO) = IF  S" DO" DBG-SET-TOKEN
        ELSE  S" BRANCH" DBG-SET-TOKEN
        THEN THEN THEN THEN THEN THEN
     ELSE
        0 SZ-TOKEN C!
     THEN
  THEN ;
\ Match one slot; update scan; write src-off/len into slot.
: DBG-ALIGN-ONE  ( cmap cell# scan end -- scan' )
  {: cmap cell# scan end | kind xt pay ha tbuf u nbuf ok -- :}
  cmap DBG-CMAP-TBUF@ TO tbuf
  cmap cell# DBG-SLOT-KIND@ TO kind
  cmap cell# DBG-SLOT-XT@ TO xt
  cmap cell# DBG-SLOT-PAY@ TO pay
  scan end DBG-SKIP-NOISE TO scan
  FALSE TO ok
  0 TO ha
  kind DBG-K-EMPTY = IF
     scan
  ELSE
     kind DBG-K-CALL = IF
        xt NAME>STRING DBG-SET-TOKEN
        scan end DBG-SEARCH-TO TO ha
        ha IF  TRUE TO ok  THEN
     ELSE
        kind DBG-K-LIT = IF
           \ ['] word → match xt name / ['] ; else decimal digits of pay
           pay IF
              pay 7 AND 0= IF
                 pay 8 - @ 65535 AND DUP IF
                    DUP 4096 U< IF
                       pay SWAP - C@ DUP IF
                          64 U< IF
                             pay NAME>STRING DBG-SET-TOKEN
                             scan end DBG-SEARCH-TO TO ha
                             ha IF  TRUE TO ok  THEN
                          THEN
                       ELSE  DROP  THEN
                    ELSE  DROP  THEN
                 ELSE  DROP  THEN
              THEN
           THEN
           ok 0= IF
              3 SZ-TOKEN C!
              [CHAR] [ SZ-TOKEN 1+ C!
              [CHAR] ' SZ-TOKEN 2 + C!
              [CHAR] ] SZ-TOKEN 3 + C!
              scan end DBG-SEARCH-TO TO ha
              ha IF  TRUE TO ok  THEN
           THEN
           ok 0= IF
              pay 0 <# #S #> DBG-SET-TOKEN
              scan end DBG-SEARCH-TO TO ha
              ha IF  TRUE TO ok  THEN
           THEN
        ELSE
           kind DBG-K-SLIT = IF
              \ match opening S" or ."
              2 SZ-TOKEN C!
              [CHAR] S SZ-TOKEN 1+ C!
              [CHAR] " SZ-TOKEN 2 + C!
              scan end DBG-SEARCH-TO TO ha
              ha 0= IF
                 2 SZ-TOKEN C!
                 [CHAR] . SZ-TOKEN 1+ C!
                 [CHAR] " SZ-TOKEN 2 + C!
                 scan end DBG-SEARCH-TO TO ha
              THEN
              ha IF  TRUE TO ok  THEN
           ELSE
              kind DBG-K-BR = kind DBG-K-EXIT = OR IF
                 kind xt DBG-ALIAS-SETUP
                 SZ-TOKEN C@ IF
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
                 \ TRY alternate aliases for 0BRANCH
                 ok 0= kind DBG-K-BR = AND xt 0BRANCH-ADDR = AND IF
                    S" WHILE" DBG-SET-TOKEN
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
                 ok 0= kind DBG-K-BR = AND xt 0BRANCH-ADDR = AND IF
                    S" UNTIL" DBG-SET-TOKEN
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
                 ok 0= kind DBG-K-BR = AND xt BRANCH-ADDR = AND IF
                    S" AGAIN" DBG-SET-TOKEN
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
                 ok 0= kind DBG-K-BR = AND xt BRANCH-ADDR = AND IF
                    S" REPEAT" DBG-SET-TOKEN
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
                 ok 0= kind DBG-K-EXIT = AND IF
                    S" EXIT" DBG-SET-TOKEN
                    scan end DBG-SEARCH-TO TO ha
                    ha IF  TRUE TO ok  THEN
                 THEN
              THEN
           THEN
        THEN
     THEN
     ok IF
        ha tbuf - cmap cell# DBG-SLOT-OFF!
        SZ-TOKEN C@ cmap cell# DBG-SLOT-LEN!
        ha SZ-TOKEN C@ + TO scan
     ELSE
        0 cmap cell# DBG-SLOT-OFF!
        0 cmap cell# DBG-SLOT-LEN!
     THEN
     scan
  THEN ;

: DBG-MAP-ALIGN  ( cmap beg end -- )
  {: cmap beg end | n cell# scan -- :}
  cmap DBG-CMAP-NCELLS@ TO n
  beg TO scan
  0 TO cell#
  BEGIN  cell# n < WHILE
     cmap cell# scan end DBG-ALIGN-ONE TO scan
     cell# 1+ TO cell#
  REPEAT ;

: DBG-MAP-NEW-CMAP  ( cfa ncells fsec -- cmap|0 )
  {: cfa ncells fsec | bytes a ior cmap -- :}
  ncells DBG-SLOT-CELLS * DBG-CMAP-HDR + CELLS TO bytes
  bytes ALLOCATE TO ior TO a
  ior IF
     0 TO cmap
  ELSE
     a TO cmap
     fsec 2 CELLS + @ cmap !          \ link after section's first
     cfa cmap CELL+ !
     ncells cmap 2 CELLS + !
     SZ-TBUF cmap 3 CELLS + !
     fsec cmap 4 CELLS + !
     cmap fsec 2 CELLS + !            \ new head of section list
     0 TO ior
     BEGIN  ior ncells < WHILE
        cmap ior DBG-SLOT-CLEAR
        ior 1+ TO ior
     REPEAT
  THEN
  cmap ;

\ Unlink and FREE the cmap for cfa (all file sections).
: DBG-MAP-DROP-CFA  ( cfa -- )
  {: cfa | fsec prev cmap next -- :}
  DBG-MAP-ROOT TO fsec
  BEGIN  fsec  WHILE
     0 TO prev
     fsec 2 CELLS + @ TO cmap
     BEGIN  cmap  WHILE
        cmap @ TO next
        cmap DBG-CMAP-CFA@ cfa = IF
           prev IF  next prev !  ELSE  next fsec 2 CELLS + !  THEN
           cmap DBG-MAP-FREE-CMAP
           0 TO cmap
        ELSE
           cmap TO prev
           next TO cmap
        THEN
     REPEAT
     fsec @ TO fsec
  REPEAT ;

: DBG-MAP-BUILD  ( cfa -- )
  {: cfa | bytes ncells file# fsec cmap beg end -- :}
  DBG-MAP-PRUNE
  cfa IF
     cfa DOCOL? IF
        cfa DBG-MAP-FIND-CFA TO cmap
        cmap IF
           cmap DBG-CMAP-TBUF@ SZ-TBUF <> IF
              cfa DBG-MAP-DROP-CFA
              0 TO cmap
           THEN
        THEN
        cmap 0= IF
           cfa DBG-COLON-BYTES TO bytes
           bytes 8 / TO ncells
           ncells IF
              ncells DBG-MAP-MAX-CELLS > IF  DBG-MAP-MAX-CELLS TO ncells  THEN
              cfa VIEW-FILE# TO file#
              file# DBG-MAP-ENSURE-FILE TO fsec
              fsec IF
                 cfa ncells fsec DBG-MAP-NEW-CMAP TO cmap
                 cmap IF
                    cmap DBG-MAP-FILL-BODY
                    DBG-HL-HIST-CLR-XT IF  DBG-HL-HIST-CLR-XT EXECUTE  THEN
                    cfa DBG-MAP-SRC-WINDOW TO end TO beg
                    beg 0<> end 0<> AND IF
                       cmap beg end DBG-MAP-ALIGN
                    THEN
                 THEN
              THEN
           THEN
        THEN
     THEN
  THEN ;
: DBG-MAP-SPAN@  ( cmap cell# -- addr u )
  {: cmap cell# | off u tbuf -- :}
  0 TO off  0 TO u
  cmap IF
     cell# cmap DBG-CMAP-NCELLS@ U< IF
        cmap cell# DBG-SLOT-OFF@ TO off
        cmap cell# DBG-SLOT-LEN@ TO u
        cmap DBG-CMAP-TBUF@ TO tbuf
        tbuf SZ-TBUF = u AND IF
           tbuf off + u
        ELSE
           0 0
        THEN
     ELSE
        0 0
     THEN
  ELSE
     0 0
  THEN ;

\ Highlight via map; ( c-addr u -- ) same contract as SZ-HIGHLIGHT-NAME.
: DBG-MAP-HL  ( c-addr u -- )
  {: a u | cfa cell# cmap addr len used -- :}
  FALSE TO used
  0 TO cmap
  DBG-CFA@ TO cfa
  cfa IF
     cfa DBG-MAP-FIND-CFA TO cmap
     cmap 0= IF
        cfa DBG-MAP-BUILD
        cfa DBG-MAP-FIND-CFA TO cmap
     THEN
     cmap IF
        cmap DBG-CMAP-TBUF@ SZ-TBUF <> IF
           cfa DBG-MAP-BUILD
           cfa DBG-MAP-FIND-CFA TO cmap
        THEN
     THEN
  THEN
  cmap IF
     DBG-BODY# TO cell#
     cmap cell# DBG-MAP-SPAN@ TO len TO addr
     len IF
        DBG-HL-SPAN-XT IF
           addr len DBG-HL-SPAN-XT EXECUTE
           TRUE TO used
        THEN
     THEN
  THEN
  \ Name-search fallback only when the colon has a stamped source file.
  \ Console-defined CFA (VIEW-FILE#=0) must not paint NDX/buffer namesakes
  \ (e.g. highlight DUP inside PASX-SAMPLE while debugging a prompt : test).
  used 0= IF
     cfa IF
        cfa VIEW-FILE# IF
           DBG-HL-NAME-XT IF
              a u DBG-HL-NAME-XT EXECUTE
           THEN
        THEN
     THEN
  THEN ;
: DBG-MAP-BIND  ( -- flag )
  {: | ok -- :}
  FALSE TO ok
  ONLY FORTH ALSO EDITOR
  S" SZ-HIGHLIGHT-NAME" HYPER-CMD HYPER-PLACE
  HYPER-CMD FIND IF  TO DBG-HL-NAME-XT  ELSE  DROP 0 TO DBG-HL-NAME-XT  THEN
  S" SZ-HIGHLIGHT-SPAN" HYPER-CMD HYPER-PLACE
  HYPER-CMD FIND IF  TO DBG-HL-SPAN-XT  ELSE  DROP 0 TO DBG-HL-SPAN-XT  THEN
  S" SZ-HL-HIST-CLEAR" HYPER-CMD HYPER-PLACE
  HYPER-CMD FIND IF  TO DBG-HL-HIST-CLR-XT  ELSE  DROP 0 TO DBG-HL-HIST-CLR-XT  THEN
  ONLY FORTH ALSO HYPER-VOC
  DBG-HL-NAME-XT 0<> DBG-HL-SPAN-XT 0<> AND TO ok
  ok IF
     ['] DBG-MAP-HL TO HYPER-HL-XT
  THEN
  ok ;

PREVIOUS PREVIOUS
ONLY FORTH ALSO HYPER-VOC

[THEN]  \ SZ-SKIP-COMMENT
[THEN]  \ SZ-HIGHLIGHT-SPAN
[THEN]  \ SZ-TBUF

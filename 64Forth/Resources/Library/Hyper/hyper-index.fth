\ hyper-index.fth — Phase 3a: in-app HYPER.NDX builder (Forth)
\
\ Loaded from hyper.fth. Writes HYPER.NDX to session cwd (Documents).
\
\ - Fixed SPECS (Kernel + Library; no Hayes/ANS/Benchmarks)
\ - TYPE 0 prefixes on Forth sources
\ - BOOT_WORD → resolve CodeLabel to Kernel/forth.s (same idea as Python)
\ - Kernel .s/.inc TYPE 0 only on .ascii / .asciz lines
\
\ Use:  HYPER-REINDEX

ONLY FORTH DEFINITIONS

\ -----------------------------------------------------------------------------
\ Buffers
\ -----------------------------------------------------------------------------

CREATE HX-LINE   512 ALLOT
CREATE HX-OUT    256 ALLOT
CREATE HX-NAME    64 ALLOT
CREATE HX-CODE    64 ALLOT
CREATE HX-PATH   128 ALLOT

0 VALUE HX-FID
0 VALUE HX-LINE#
0 VALUE HX-COUNT
0 VALUE HX-ASM
0 VALUE HX-OUTLEN
0 VALUE HX-LA
0 VALUE HX-LU
0 VALUE HX-PA
0 VALUE HX-PU
0 VALUE HX-MA
0 VALUE HX-MU
0 VALUE HX-TMP

\ Label entry: count + name[31] + line cell at offset 32
40 CONSTANT HX-ESIZE
2048 CONSTANT HX-LMAX          \ forth.s ~900 labels; was 1024 and hit the ceiling
CREATE HX-LTAB  HX-LMAX HX-ESIZE * ALLOT
0 VALUE HX-LN

\ -----------------------------------------------------------------------------
\ Output
\ -----------------------------------------------------------------------------

: HX-OUT-CLEAR  ( -- )  0 TO HX-OUTLEN ;

: HX-OUT-CH  ( c -- )
   HX-OUTLEN 255 < IF
      HX-OUT HX-OUTLEN + C!
      HX-OUTLEN 1+ TO HX-OUTLEN
   ELSE  DROP  THEN ;

: HX-OUT-S  ( c-addr u -- )
   BEGIN  DUP WHILE
      OVER C@ HX-OUT-CH
      1 /STRING
   REPEAT  2DROP ;

: HX-OUT-NUM  ( n -- )
   BASE @ >R DECIMAL
   0 <# #S #> HX-OUT-S
   R> BASE ! ;

: HX-OUT-FLUSH  ( -- )
   HX-FID IF
      HX-OUT HX-OUTLEN HX-FID WRITE-LINE DROP
   THEN ;

: HX-EMIT  ( c-addr u -- )
   DUP 0= IF  2DROP EXIT  THEN
   DUP 63 > IF  2DROP EXIT  THEN
   HX-OUT-CLEAR
   HX-OUT-S
   BL HX-OUT-CH
   HX-LINE# HX-OUT-NUM
   HX-OUT-FLUSH
   HX-COUNT 1+ TO HX-COUNT ;

: HX-EMIT-AT  ( -- )
   HX-OUT-CLEAR
   [CHAR] @ HX-OUT-CH
   BL HX-OUT-CH
   HX-PATH COUNT HX-OUT-S
   HX-OUT-FLUSH ;

\ name u line → @ Kernel/forth.s + entry, then restore current @ path
: HX-EMIT-CODE  ( c-addr u line -- )
   >R
   DUP 0= IF  R> DROP 2DROP EXIT  THEN
   DUP 63 > IF  R> DROP 2DROP EXIT  THEN
   HX-OUT-CLEAR
   [CHAR] @ HX-OUT-CH  BL HX-OUT-CH
   S" Kernel/forth.s" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR
   HX-OUT-S
   BL HX-OUT-CH
   R> HX-OUT-NUM
   HX-OUT-FLUSH
   HX-COUNT 1+ TO HX-COUNT
   HX-EMIT-AT ;

\ -----------------------------------------------------------------------------
\ String helpers
\ -----------------------------------------------------------------------------

: HX-SKIP-BL  ( a u -- a' u' )
   BEGIN
      DUP 0= IF  EXIT  THEN
      OVER C@ BL <> IF  EXIT  THEN
      SWAP 1+ SWAP 1-
   AGAIN ;

: HX-SKIP1  ( a u -- a' u' )  SWAP 1+ SWAP 1- ;

: HX-SKIP-COMMA-BL  ( a u -- a' u' )
   BEGIN
      DUP 0= IF  EXIT  THEN
      OVER C@ DUP BL = SWAP [CHAR] , = OR IF
         HX-SKIP1
      ELSE  EXIT  THEN
   AGAIN ;

: HX-ALNUM?  ( c -- flag )
   DUP [CHAR] 0 [CHAR] 9 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  DROP TRUE EXIT  THEN
   DROP FALSE ;

: HX-LABCHAR?  ( c -- flag )
   DUP HX-ALNUM? IF  DROP TRUE EXIT  THEN
   [CHAR] _ = ;

: HX-BOUND-OK  ( ma -- flag )
   DUP HX-LA = IF  DROP TRUE EXIT  THEN
   1- C@
   HX-PA C@ [CHAR] : = IF
      DUP HX-ALNUM? IF  DROP FALSE EXIT  THEN
      DUP [CHAR] . = IF  DROP FALSE EXIT  THEN
      DUP [CHAR] _ = IF  DROP FALSE EXIT  THEN
      DROP TRUE
   ELSE
      BL =
   THEN ;

: HX-NUMBER?  ( a u -- flag )
   DUP 0= IF  2DROP TRUE EXIT  THEN
   OVER C@ [CHAR] - = IF  HX-SKIP1  THEN
   DUP 0= IF  2DROP TRUE EXIT  THEN
   BEGIN  DUP WHILE
      OVER C@ [CHAR] 0 [CHAR] 9 1+ WITHIN 0= IF  2DROP FALSE EXIT  THEN
      HX-SKIP1
   REPEAT
   2DROP TRUE ;

: HX-PLAUSIBLE?  ( a u -- flag )
   DUP 0= IF  2DROP FALSE EXIT  THEN
   DUP 63 > IF  2DROP FALSE EXIT  THEN
   2DUP HX-NUMBER? IF  2DROP FALSE EXIT  THEN
   OVER C@ [CHAR] : = OVER 1 = AND IF  2DROP FALSE EXIT  THEN
   OVER C@ [CHAR] ; = OVER 1 = AND IF  2DROP FALSE EXIT  THEN
   OVER C@ [CHAR] \ = IF  2DROP FALSE EXIT  THEN
   2DROP TRUE ;

\ ( a u -- wa wu ra ru )  wlen stays on data stack with (a u wlen)
: HX-NEXT-WORD  ( a u -- wa wu ra ru )
   HX-SKIP-BL
   DUP 0= IF  0 0 2SWAP EXIT  THEN
   OVER C@ [CHAR] " = IF
      HX-SKIP1
      0
      BEGIN  1 PICK OVER > WHILE
         2 PICK OVER + C@ [CHAR] " = IF
            >R  OVER R@  2SWAP
            SWAP R@ + 1+  SWAP R@ - 1-
            R> DROP EXIT
         THEN  1+
      REPEAT
      DROP  0 0 2SWAP EXIT
   THEN
   0
   BEGIN  1 PICK OVER > WHILE
      2 PICK OVER + C@ BL = IF
         >R  OVER R@  2SWAP
         SWAP R@ + SWAP R@ -
         R> DROP EXIT
      THEN  1+
   REPEAT
   DROP  2DUP + 0 ;

: HX-HAS  ( a u na nu -- flag )
   SEARCH IF  2DROP TRUE  ELSE  2DROP FALSE  THEN ;

: HX-STOPAT  ( a u -- a' u' )
   DUP 0= IF  EXIT  THEN
   OVER C@ [CHAR] \ = IF  DROP 0 EXIT  THEN
   2DUP S"  \" SEARCH IF
      DROP SWAP DROP OVER - EXIT
   THEN  2DROP
   2DUP S" //" SEARCH IF
      DROP SWAP DROP OVER - EXIT
   THEN  2DROP ;

\ -----------------------------------------------------------------------------
\ TYPE 0
\ -----------------------------------------------------------------------------

: HX-REST-AFTER  ( -- a u )
   HX-MA 1+  HX-LA HX-LU + OVER - ;

: HX-SCAN-PREF  ( -- )
   HX-LA HX-LU
   BEGIN  DUP 0> WHILE
      2DUP HX-PA HX-PU SEARCH
      0= IF  2DROP 2DROP EXIT  THEN
      TO HX-MU  TO HX-MA  2DROP
      HX-MA HX-BOUND-OK IF
         HX-MA HX-MU HX-PU /STRING
         HX-NEXT-WORD 2DROP
         2DUP HX-PLAUSIBLE? IF  HX-EMIT  ELSE  2DROP  THEN
      THEN
      HX-REST-AFTER
   REPEAT
   2DROP ;

: HX-PREF  ( c-addr u -- )  TO HX-PU  TO HX-PA  HX-SCAN-PREF ;

: HX-ALL-PREFS  ( -- )
   S" : "          HX-PREF
   S" CODE "       HX-PREF
   S" CREATE "     HX-PREF
   S" CONSTANT "   HX-PREF
   S" VALUE "      HX-PREF
   S" 2VALUE "     HX-PREF
   S" DEFER "      HX-PREF
   S" VARIABLE "   HX-PREF
   S" VOCABULARY " HX-PREF
   S" BUFFER: "    HX-PREF
   S" SYNONYM "    HX-PREF
   S" ALIAS "      HX-PREF ;

\ -----------------------------------------------------------------------------
\ Labels from Kernel/forth.s
\ -----------------------------------------------------------------------------

: HX-LENT  ( i -- addr )  HX-ESIZE * HX-LTAB + ;

\ ( a u line -- )
: HX-ADD-LABEL
   HX-LN HX-LMAX >= IF  DROP 2DROP EXIT  THEN
   HX-LN HX-LENT >R                \ R: ent  ( a u line )
   ROT ROT 31 MIN                  \ line a u   (no -ROT in kernel)
   DUP R@ C!
   R@ CHAR+ SWAP CMOVE             \ line
   R@ 32 + !
   R> DROP
   HX-LN 1+ TO HX-LN ;

\ ( a u -- line true | false )
: HX-FIND-LABEL
   0
   BEGIN  DUP HX-LN < WHILE
      DUP HX-LENT >R               \ R: ent  ( a u i )
      2 PICK 2 PICK R@ COUNT COMPARE 0= IF
         R@ 32 + @                 \ a u i line
         NIP NIP NIP               \ line
         R> DROP TRUE EXIT
      THEN
      R> DROP 1+
   REPEAT
   DROP 2DROP FALSE ;

\ Line starts with Label:  (optional blanks). No LEAVE (DO-only).
: HX-TRY-LABEL  ( a u -- )
   HX-SKIP-BL
   DUP 0= IF  2DROP EXIT  THEN
   OVER C@ DUP HX-ALNUM? SWAP [CHAR] _ = OR 0= IF  2DROP EXIT  THEN
   0                               \ a u wlen
   BEGIN
      1 PICK OVER > 0= IF  TRUE  ELSE
         2 PICK OVER + C@ HX-LABCHAR? 0= IF  TRUE  ELSE
            1+ FALSE
         THEN
      THEN
   UNTIL
   \ a u wlen — name length; a[wlen] must be ':' (requires wlen < u)
   DUP 0= IF  DROP 2DROP EXIT  THEN
   1 PICK OVER <= IF  DROP 2DROP EXIT  THEN
   2 PICK OVER + C@ [CHAR] : <> IF  DROP 2DROP EXIT  THEN
   >R                              \ R: wlen  ( a u )
   R@ 1+                           \ a u off
   1 PICK OVER > IF
      2 PICK OVER + C@
      DUP BL = OVER 9 = OR OVER [CHAR] / = OR
      NIP 0= IF  DROP R> DROP 2DROP EXIT  THEN
   THEN  DROP
   OVER R@ HX-LINE# HX-ADD-LABEL
   R> DROP 2DROP ;

: HX-COLLECT-LABELS-FILE  ( c-addr u -- )
   2DUP R/O OPEN-FILE
   IF  DROP ." HX: labels skip " TYPE CR EXIT  THEN
   >R 2DROP
   0 TO HX-LINE#
   BEGIN
      HX-LINE 500 R@ READ-LINE
      IF  DROP DROP R> CLOSE-FILE DROP EXIT  THEN
      0= IF  DROP R> CLOSE-FILE DROP EXIT  THEN
      HX-LINE# 1+ TO HX-LINE#
      HX-LINE SWAP HX-TRY-LABEL
   AGAIN ;

: HX-COLLECT-LABELS  ( -- )
   0 TO HX-LN
   S" Kernel/forth.s" HX-COLLECT-LABELS-FILE
   ." HX: " HX-LN . ." asm labels" CR ;

\ -----------------------------------------------------------------------------
\ BOOT_WORD "name", "help", imm, CodeLabel
\ -----------------------------------------------------------------------------

\ In at open quote → after close quote
: HX-SKIP-QUOTED  ( a u -- a' u' )
   DUP 0= IF  EXIT  THEN
   OVER C@ [CHAR] " <> IF  EXIT  THEN
   HX-SKIP1
   BEGIN
      DUP 0= IF  EXIT  THEN
      OVER C@ [CHAR] " = IF  HX-SKIP1 EXIT  THEN
      HX-SKIP1
   AGAIN ;

\ ( a u dest -- a' u' flag )  in at open quote; fills dest counted string
: HX-PARSE-QUOTED
   TO HX-TMP
   DUP 0= IF  FALSE EXIT  THEN
   OVER C@ [CHAR] " <> IF  FALSE EXIT  THEN
   HX-SKIP1
   0
   BEGIN  1 PICK OVER > WHILE
      2 PICK OVER + C@ [CHAR] " = IF
         >R                        \ R: wlen  ( a u )
         OVER R@ HX-TMP PLACE
         SWAP R@ + 1+ SWAP R@ - 1-
         R> DROP TRUE EXIT
      THEN  1+
   REPEAT
   DROP 2DROP FALSE ;

\ ( a u dest -- a' u' flag )
: HX-PARSE-IDENT
   TO HX-TMP
   HX-SKIP-COMMA-BL
   DUP 0= IF  FALSE EXIT  THEN
   OVER C@ HX-LABCHAR? 0= IF  FALSE EXIT  THEN
   0
   BEGIN
      1 PICK OVER > 0= IF  TRUE  ELSE
         2 PICK OVER + C@ HX-LABCHAR? 0= IF  TRUE  ELSE
            1+ FALSE
         THEN
      THEN
   UNTIL
   DUP 0= IF  DROP 2DROP FALSE EXIT  THEN
   >R
   OVER R@ HX-TMP PLACE
   SWAP R@ + SWAP R@ -
   R> DROP TRUE ;

: HX-TRY-BOOT  ( a u -- flag )
   HX-SKIP-BL
   DUP 9 < IF  2DROP FALSE EXIT  THEN
   OVER 9 S" BOOT_WORD" COMPARE IF  2DROP FALSE EXIT  THEN
   9 /STRING
   HX-SKIP-BL
   HX-NAME HX-PARSE-QUOTED 0= IF  2DROP FALSE EXIT  THEN
   HX-SKIP-COMMA-BL
   HX-SKIP-QUOTED
   HX-SKIP-COMMA-BL
   BEGIN
      DUP 0= IF  2DROP FALSE EXIT  THEN
      OVER C@ [CHAR] 0 [CHAR] 9 1+ WITHIN IF
         HX-SKIP1 FALSE
      ELSE  TRUE  THEN
   UNTIL
   HX-SKIP-COMMA-BL
   HX-CODE HX-PARSE-IDENT 0= IF  2DROP FALSE EXIT  THEN
   2DROP
   HX-NAME COUNT HX-PLAUSIBLE? 0= IF  FALSE EXIT  THEN
   HX-CODE COUNT HX-FIND-LABEL IF
      HX-NAME COUNT ROT HX-EMIT-CODE
   ELSE
      HX-NAME COUNT HX-EMIT
   THEN
   TRUE ;

\ -----------------------------------------------------------------------------
\ Scan line / file
\ -----------------------------------------------------------------------------

: HX-SCAN-LINE  ( a u -- )
   DUP 0= IF  2DROP EXIT  THEN
   HX-ASM IF
      2DUP HX-TRY-BOOT IF  2DROP EXIT  THEN
      2DUP S" .ascii" HX-HAS 0= IF
         2DUP S" .asciz" HX-HAS 0= IF
            2DROP EXIT
         THEN
      THEN
   THEN
   HX-STOPAT
   500 MIN
   DUP 0= IF  2DROP EXIT  THEN
   TO HX-LU  TO HX-LA
   HX-ALL-PREFS ;

: HX-SET-ASM  ( c-addr u -- )
   2DUP S" .s" SEARCH IF  2DROP 2DROP TRUE TO HX-ASM EXIT  THEN  2DROP
   2DUP S" .S" SEARCH IF  2DROP 2DROP TRUE TO HX-ASM EXIT  THEN  2DROP
   2DUP S" .inc" SEARCH IF  2DROP 2DROP TRUE TO HX-ASM EXIT  THEN  2DROP
   2DROP FALSE TO HX-ASM ;

: HX-SCAN-FILE  ( c-addr u -- )
   2DUP HX-PATH PLACE
   2DUP HX-SET-ASM
   2DUP R/O OPEN-FILE
   IF  DROP ." HX: skip " TYPE CR EXIT  THEN
   >R 2DROP
   HX-EMIT-AT
   0 TO HX-LINE#
   BEGIN
      HX-LINE 500 R@ READ-LINE
      IF  DROP DROP R> CLOSE-FILE DROP EXIT  THEN
      0= IF  DROP R> CLOSE-FILE DROP EXIT  THEN
      HX-LINE# 1+ TO HX-LINE#
      HX-LINE SWAP HX-SCAN-LINE
   AGAIN ;

\ -----------------------------------------------------------------------------
\ SPECS
\ -----------------------------------------------------------------------------

: HX-SCAN-ALL  ( -- )
   S" Kernel/boot_words.inc"                 HX-SCAN-FILE
   S" Kernel/colon_words.inc"                HX-SCAN-FILE
   S" Kernel/forth.s"                        HX-SCAN-FILE
   S" Library/BigInteger/bi-test.fth"        HX-SCAN-FILE
   S" Library/BigInteger/bi-vocab-smoke.fth" HX-SCAN-FILE
   S" Library/BigInteger/big-int.fth"        HX-SCAN-FILE
   S" Library/Editor/sz-buffer.fth"          HX-SCAN-FILE
   S" Library/Editor/sz-edit.fth"            HX-SCAN-FILE
   S" Library/Editor/SZ-EDITOR.fth"          HX-SCAN-FILE
   S" Library/Editor/sz-host.fth"            HX-SCAN-FILE
   S" Library/Editor/sz-screen.fth"          HX-SCAN-FILE
   S" Library/Hyper/hyper.fth"               HX-SCAN-FILE
   S" Library/Hyper/hyper-index.fth"         HX-SCAN-FILE
   S" Library/PI/pi-chudnovsky.fth"          HX-SCAN-FILE
   S" Library/PI/pi-test.fth"                HX-SCAN-FILE
   S" Library/smoke-load.fth"                HX-SCAN-FILE
   S" Library/TCOM/ALLSPECS.FTH"             HX-SCAN-FILE
   S" Library/TCOM/FPCTOOLS.fth"             HX-SCAN-FILE
   S" Library/TCOM/GLOBAL.FTH"               HX-SCAN-FILE
   S" Library/TCOM/HYPER.FTH"                HX-SCAN-FILE
   S" Library/TCOM/LEDIT.FTH"                HX-SCAN-FILE
   S" Library/TCOM/LOOK.FTH"                 HX-SCAN-FILE
   S" Library/TCOM/MIDNIGHT.FTH"             HX-SCAN-FILE
   S" Library/TCOM/SZ.FTH"                   HX-SCAN-FILE
   S" Library/TCOM/VED.FTH"                  HX-SCAN-FILE
   S" Library/TCOM/ZIM.FTH"                  HX-SCAN-FILE
   S" Library/TCOM/ZLIST.FTH"                HX-SCAN-FILE
   S" Library/xchar-smoke.fth"               HX-SCAN-FILE ;

\ -----------------------------------------------------------------------------
\ HYPER-REINDEX → Config/HYPER.NDX
\
\ Path uses the same hyper-style root as FROMLIB does for Library/:
\   Config/…  → Resources/Config (source tree when running from Xcode),
\               else Application Support/64Forth/Config/ (writable overlay).
\ Host CREATE-FILE maps read-only bundle paths to the overlay automatically.
\ -----------------------------------------------------------------------------

CREATE HX-NDX-OUT  32 ALLOT
S" Config/HYPER.NDX" HX-NDX-OUT PLACE

: HX-WRITE-HEADER  ( -- )
   HX-OUT-CLEAR
   S" # 64Forth hyper index — generated by HYPER-REINDEX (Forth)" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR
   S" # Format: @ path, then NAME linenumber" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR
   S" # BOOT_WORD → Kernel/forth.s CODE label when present" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR HX-OUT-FLUSH ;

: HYPER-REINDEX  ( -- )
   ." HYPER-REINDEX: writing " HX-NDX-OUT COUNT TYPE ." ..." CR
   0 TO HX-COUNT
   0 TO HX-FID
   HX-COLLECT-LABELS
   HX-NDX-OUT COUNT W/O CREATE-FILE
   IF
      DROP
      ." HYPER-REINDEX: CREATE-FILE failed for Config/HYPER.NDX" CR
      ."   (host should map Config/ to source tree or App Support)" CR
      EXIT
   THEN
   TO HX-FID
   HX-WRITE-HEADER
   HX-SCAN-ALL
   HX-FID CLOSE-FILE DROP
   0 TO HX-FID
   HX-NDX-OUT COUNT HYPER-NDX-NAME PLACE
   ." HYPER-REINDEX: " HX-COUNT . ." entries" CR
   HYPER-RELOAD ;

ONLY FORTH DEFINITIONS

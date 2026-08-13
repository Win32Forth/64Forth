\ hyper-index.fth — Phase 3a/4: in-app HYPER.NDX builder (Forth)
\
\ Loaded from hyper.fth. Writes Config/HYPER.NDX.
\
\ Phase 4:
\   - TYPE 0 prefixes from Config/HYPER.CFG (fallback defaults)
\   - SPECS expanded by host via virtual Config/HYPER.SPECS
\   - *EXCLUDE applied by host when building the SPECS list
\   - BOOT_WORD → CodeLabel in Library/Sources/forth.s
\   - Sources .s/.inc TYPE 0 only on .ascii / .asciz lines
\
\ Use:  HYPER-REINDEX   (FORTH wrapper; HX-DO-REINDEX + helpers in HYPER-VOC)
\
\ Caller (hyper.fth) defines into HYPER-VOC; stay on that CURRENT.

ONLY FORTH ALSO HYPER-VOC DEFINITIONS

VARIABLE MIN-HYPER-NOISE
MIN-HYPER-NOISE OFF
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

\ TYPE 0 prefix table (from HYPER.CFG)
16 CONSTANT HX-PMAX
64 CONSTANT HX-PSZ
CREATE HX-PTAB  HX-PMAX HX-PSZ * ALLOT
0 VALUE HX-PN

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

\ name u line → @ Library/Sources/forth.s + entry, then restore current @ path
: HX-EMIT-CODE  ( c-addr u line -- )
   >R
   DUP 0= IF  R> DROP 2DROP EXIT  THEN
   DUP 63 > IF  R> DROP 2DROP EXIT  THEN
   HX-OUT-CLEAR
   [CHAR] @ HX-OUT-CH  BL HX-OUT-CH
   S" Library/Sources/forth.s" HX-OUT-S
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

: HX-PENT  ( i -- addr )  HX-PSZ * HX-PTAB + ;

: HX-ADD-PREF  ( c-addr u -- )
   HX-PN HX-PMAX >= IF  2DROP EXIT  THEN
   63 MIN HX-PN HX-PENT PLACE
   HX-PN 1+ TO HX-PN ;

: HX-DEFAULT-PREFS  ( -- )
   0 TO HX-PN
   S" : "          HX-ADD-PREF
   S" CODE "       HX-ADD-PREF
   S" CREATE "     HX-ADD-PREF
   S" CONSTANT "   HX-ADD-PREF
   S" VALUE "      HX-ADD-PREF
   S" 2VALUE "     HX-ADD-PREF
   S" DEFER "      HX-ADD-PREF
   S" VARIABLE "   HX-ADD-PREF
   S" VOCABULARY " HX-ADD-PREF
   S" BUFFER: "    HX-ADD-PREF
   S" SYNONYM "    HX-ADD-PREF
   S" ALIAS "      HX-ADD-PREF ;

: HX-ALL-PREFS  ( -- )
   HX-PN 0= IF  HX-DEFAULT-PREFS  THEN
   0
   BEGIN  DUP HX-PN < WHILE
      DUP HX-PENT COUNT HX-PREF
      1+
   REPEAT
   DROP ;

\ -----------------------------------------------------------------------------
\ Load TYPE 0 "…" from Config/HYPER.CFG
\ -----------------------------------------------------------------------------

\ Parse TYPE 0 "prefix"  — kind 0 only; BOOT_WORD handled separately.
: HX-CFG-TYPE-LINE  ( a u -- )
   HX-SKIP-BL
   DUP 4 < IF  2DROP EXIT  THEN
   OVER 4 S" TYPE" COMPARE IF  2DROP EXIT  THEN
   4 /STRING HX-SKIP-BL
   DUP 0= IF  2DROP EXIT  THEN
   OVER C@ [CHAR] 0 <> IF  2DROP EXIT  THEN
   HX-SKIP1 HX-SKIP-BL
   DUP 0= IF  2DROP EXIT  THEN
   OVER C@ [CHAR] " <> IF  2DROP EXIT  THEN
   HX-SKIP1
   0
   BEGIN  1 PICK OVER > WHILE
      2 PICK OVER + C@ [CHAR] " = IF
         >R OVER R@                  \ a u a wlen
         DUP 9 >= IF
            OVER 9 S" BOOT_WORD" COMPARE 0= IF
               2DROP R> DROP 2DROP EXIT
            THEN
         THEN
         HX-ADD-PREF
         R> DROP 2DROP EXIT
      THEN  1+
   REPEAT
   DROP 2DROP ;

: HX-LOAD-CFG  ( -- )
   0 TO HX-PN
   S" Config/HYPER.CFG" R/O OPEN-FILE
   IF  DROP HX-DEFAULT-PREFS ." HX: no HYPER.CFG — default TYPE 0" CR EXIT  THEN
   >R
   BEGIN
      HX-LINE 500 R@ READ-LINE
      IF  DROP DROP R> CLOSE-FILE DROP
          HX-PN 0= IF  HX-DEFAULT-PREFS  THEN EXIT  THEN
      0= IF  DROP R> CLOSE-FILE DROP
          HX-PN 0= IF  HX-DEFAULT-PREFS  THEN EXIT  THEN
      HX-LINE SWAP
      DUP 0= IF  2DROP
      ELSE  OVER C@ [CHAR] # = IF  2DROP
      ELSE  OVER C@ [CHAR] ; = IF  2DROP R> CLOSE-FILE DROP
          HX-PN 0= IF  HX-DEFAULT-PREFS  THEN EXIT
      ELSE
         HX-CFG-TYPE-LINE
      THEN THEN THEN
   AGAIN ;

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
   S" Library/Sources/forth.s" HX-COLLECT-LABELS-FILE
   MIN-HYPER-NOISE @ 0=
   IF   ." HX: " HX-LN . ." asm labels" CR
   THEN ;

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
   IF
      DROP
      \ Quiet when MIN-HYPER-NOISE is on (autoload reindex on release DMG).
      MIN-HYPER-NOISE @ 0= IF  ." HX: skip " TYPE CR  ELSE  2DROP  THEN
      EXIT
   THEN
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
\ SPECS — host expands Config/HYPER.CFG into virtual Config/HYPER.SPECS
\ -----------------------------------------------------------------------------

: HX-SCAN-FALLBACK  ( -- )
   S" Library/Sources/forth.s"       HX-SCAN-FILE
   S" Library/Sources/colon_words.inc" HX-SCAN-FILE
   S" Library/Sources/boot_words.inc"  HX-SCAN-FILE
   S" Library/Hyper/hyper.fth"   HX-SCAN-FILE
   S" Library/Hyper/hyper-index.fth" HX-SCAN-FILE
   S" Library/Editor/sz-edit.fth" HX-SCAN-FILE
   S" Library/Editor/sz-buffer.fth" HX-SCAN-FILE
   S" Library/Editor/sz-screen.fth" HX-SCAN-FILE
   S" Library/Editor/sz-host.fth" HX-SCAN-FILE
   S" Library/Editor/SZ-EDITOR.fth" HX-SCAN-FILE ;

\ One SPECS path line (skip blanks / # comments)
: HX-SCAN-SPECS-LINE  ( a u -- )
   HX-SKIP-BL
   DUP 0= IF  2DROP EXIT  THEN
   OVER C@ [CHAR] # = IF  2DROP EXIT  THEN
   HX-SCAN-FILE ;

0 VALUE HX-FCNT

: HX-SCAN-ALL  ( -- )
   S" Config/HYPER.SPECS" R/O OPEN-FILE
   IF
      DROP ." HX: HYPER.SPECS unavailable — fallback list" CR
      HX-SCAN-FALLBACK EXIT
   THEN
   >R                               \ R: fid
   0 TO HX-FCNT
   BEGIN
      HX-LINE 500 R@ READ-LINE      \ u2 flag ior
      IF
         DROP DROP R> CLOSE-FILE DROP
         HX-FCNT 0= IF  HX-SCAN-FALLBACK  THEN EXIT
      THEN
      0= IF
         DROP R> CLOSE-FILE DROP
         HX-FCNT 0= IF  HX-SCAN-FALLBACK
         ELSE
            MIN-HYPER-NOISE @ 0=
            IF  ." HX: " HX-FCNT . ." SPECS files" CR
            THEN
         THEN EXIT
      THEN
      HX-LINE SWAP HX-SCAN-SPECS-LINE
      HX-FCNT 1+ TO HX-FCNT
   AGAIN ;

\ -----------------------------------------------------------------------------
\ HYPER-REINDEX → Config/HYPER.NDX
\ Writes the canonical Config/ path and records it in HYPER-NDX-NAME (FORTH;
\ 256-byte counted path used for load/reload status — no separate HX-NDX-OUT).
\ -----------------------------------------------------------------------------

: HX-WRITE-HEADER  ( -- )
   HX-OUT-CLEAR
   S" # 64Forth hyper index — generated by HYPER-REINDEX (Forth Phase 4)" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR
   S" # Format: @ path, then NAME linenumber" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR
   S" # SPECS from HYPER.CFG via host HYPER.SPECS; TYPE 0 from CFG" HX-OUT-S
   HX-OUT-FLUSH
   HX-OUT-CLEAR HX-OUT-FLUSH ;

\ Body in HYPER-VOC so HX-* / MIN-HYPER-NOISE compile against this wordlist.
: HX-DO-REINDEX  ( -- )
   S" Config/HYPER.NDX" HYPER-NDX-NAME PLACE
   ." HYPER-REINDEX: writing " HYPER-NDX-NAME COUNT TYPE ." ..." CR
   0 TO HX-COUNT
   0 TO HX-FID
   HX-LOAD-CFG
   MIN-HYPER-NOISE @ 0=
   IF   ." HX: " HX-PN . ." TYPE 0 prefixes" CR
   THEN
   HX-COLLECT-LABELS
   HYPER-NDX-NAME COUNT W/O CREATE-FILE
   IF
      DROP
      ." HYPER-REINDEX: CREATE-FILE failed for " HYPER-NDX-NAME COUNT TYPE CR
      EXIT
   THEN
   TO HX-FID
   HX-WRITE-HEADER
   HX-SCAN-ALL
   HX-FID CLOSE-FILE DROP
   0 TO HX-FID
   MIN-HYPER-NOISE @ 0=
   IF   ." HYPER-REINDEX: " HX-COUNT . ." entries" CR
   THEN
   \ Use HYPER-LOAD here (HYPER-VOC); HYPER-RELOAD is defined later in FORTH.
   HYPER-LOAD IF
      ." HYPER: " HYPER-NDX-NAME COUNT TYPE
      ."  " HYPER-LEN . ." bytes" CR
   ELSE  ." HYPER: cannot open index" CR  THEN ;

\ Public entry in FORTH — no ALSO needed at the call site.
\ Note: FORTH replaces search_order[0] (does not push). Keep HYPER-VOC first
\ for FIND, and set CURRENT with FORTH-WORDLIST SET-CURRENT instead.
\ Do NOT end with ONLY FORTH — hyper.fth still needs HYPER-VOC visible for
\ HYPER-LOAD / HYPER-BIND-EDITOR after this FLOAD returns.
ONLY FORTH ALSO HYPER-VOC
FORTH-WORDLIST SET-CURRENT
: HYPER-REINDEX  ( -- )  ['] HX-DO-REINDEX EXECUTE ;

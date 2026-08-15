\ hyper.fth — HYPER.NDX: LOCATE / VIEW
\
\ Load: FROMLIB FLOAD Hyper/hyper.fth
\ Use:  ALSO HYPER-VOC  LOCATE DUP  PREVIOUS
\       (or: HYPER-VOC LOCATE DUP FORTH)
\
\ Internals in HYPER-VOC. Public VIEW/LOCATE/SEE/… defined once in FORTH
\ with ALSO HYPER-VOC so bodies find Hyper words (survive ONLY FORTH).

ANEW HYPER-MODULE
ONLY FORTH DEFINITIONS
VOCABULARY HYPER-VOC
ONLY FORTH ALSO HYPER-VOC DEFINITIONS

0 VALUE HYPER-BUF
0 VALUE HYPER-LEN
0 VALUE HYPER-OK
0 VALUE HYPER-POS
0 VALUE HYPER-LC
0 VALUE HYPER-LINE#

CREATE HYPER-CUR   256 ALLOT
CREATE HYPER-HIT   256 ALLOT
CREATE HYPER-LINE  256 ALLOT
CREATE HYPER-SEEK   64 ALLOT
CREATE HYPER-CMD   512 ALLOT

\ Path of the index file last opened or written (counted; room for long abs paths).
CREATE HYPER-NDX-NAME  256 ALLOT
S" Config/HYPER.NDX" HYPER-NDX-NAME PLACE

\ Try open path; on success leave fileid and set HYPER-NDX-NAME. flag true = ok.
: HYPER-TRY-OPEN  ( c-addr u -- fileid true | false )
   2DUP R/O OPEN-FILE
   IF  DROP 2DROP FALSE EXIT  THEN     \ ior: fail
   >R                                  \ R: fid  ( c-addr u )
   HYPER-NDX-NAME PLACE
   R> TRUE ;

\ Config/HYPER.NDX first (HYPER-REINDEX + shipped index), else cwd HYPER.NDX.
: HYPER-OPEN-NDX  ( -- fileid true | false )
   S" Config/HYPER.NDX" HYPER-TRY-OPEN DUP IF  EXIT  THEN  DROP
   S" HYPER.NDX" HYPER-TRY-OPEN ;

: HYPER-UPC  ( c -- c' )
   DUP [CHAR] a [CHAR] z 1+ WITHIN IF  32 -  THEN ;

: HYPER-SKIP1  ( a u -- a' u' )
   SWAP 1+ SWAP 1- ;

: HYPER-SKIP-BL  ( a u -- a' u' )
   BEGIN
      DUP 0= IF  EXIT  THEN
      OVER C@ BL <> IF  EXIT  THEN
      HYPER-SKIP1
   AGAIN ;

\ ( src u dest -- ) counted string at dest (kernel CMOVE)
: HYPER-PLACE  ( src u dest -- )
   >R                              \ R: dest  (CMOVE uses its own R frame)
   255 MIN
   DUP R@ C!                       \ count at dest
   R@ CHAR+ SWAP CMOVE             \ ( src dest+1 u ) → CMOVE
   R> DROP ;

\ ( a1 u1 a2 u2 -- flag )  case-insensitive; always consumes all four args.
\ After length check stack must be ( a1 a2 u ). A missing DROP left ( a1 a2 u2 u1 )
\ so DUP C@ treated the length as an address → soft-fault / hang loops.
\ Lengths must use U> : signed 255 > on a corrupt -1 length never trips and the
\ compare loop runs "forever".
: HYPER-NAME=  ( a1 u1 a2 u2 -- flag )
   ROT                                 \ a1 a2 u2 u1
   2DUP <> IF  2DROP 2DROP FALSE EXIT  THEN   \ len mismatch
   DROP                                \ a1 a2 u
   DUP 255 U> IF  DROP 2DROP FALSE EXIT  THEN
   BEGIN  DUP WHILE
      1- >R                            \ R: remaining-1  ( a1 a2 )
      DUP C@ HYPER-UPC >R              \ R: rem ch2
      OVER C@ HYPER-UPC R> <> IF       \ chars differ
         R> DROP                       \ drop rem
         2DROP FALSE EXIT
      THEN
      1+ SWAP 1+ SWAP
      R>
   REPEAT
   DROP 2DROP TRUE ;

: HYPER-FREE  ( -- )
   HYPER-BUF IF  HYPER-BUF FREE DROP  THEN
   0 TO HYPER-BUF  0 TO HYPER-LEN  0 TO HYPER-POS
   FALSE TO HYPER-OK
   0 HYPER-CUR C!  0 HYPER-HIT C!
   0 TO HYPER-LINE# ;

\ Prefer Config/HYPER.NDX, else cwd HYPER.NDX.
: HYPER-LOAD  ( -- flag )
   HYPER-FREE
   HYPER-OPEN-NDX 0= IF  FALSE EXIT  THEN
   >R                                  \ R: fid
   R@ FILE-SIZE
   IF  2DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   IF  DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   DUP 0= IF  DROP R> CLOSE-FILE DROP FALSE EXIT  THEN
   \ ( size ) ALLOCATE → ( size addr ior )
   DUP ALLOCATE IF                 \ fail
      2DROP R> CLOSE-FILE DROP FALSE EXIT
   THEN                            \ ( size addr )
   TO HYPER-BUF                    \ ( size )
   DUP TO HYPER-LEN
   HYPER-BUF SWAP R@ READ-FILE
   R> CLOSE-FILE DROP
   IF  HYPER-FREE FALSE EXIT  THEN
   TO HYPER-LEN
   TRUE TO HYPER-OK
   TRUE ;

: HYPER-ENSURE  ( -- flag )
   HYPER-OK IF  TRUE EXIT  THEN  HYPER-LOAD ;

: HYPER-EOF?  ( -- flag )  HYPER-POS HYPER-LEN U< 0= ;

: HYPER-CH  ( -- c | -1 )
   HYPER-EOF? IF  -1 EXIT  THEN
   HYPER-BUF HYPER-POS + C@
   HYPER-POS 1+ TO HYPER-POS ;

: HYPER-READ-LINE  ( -- a u | 0 0 )
   0 TO HYPER-LC
   BEGIN
      HYPER-CH
      DUP 0< IF
         DROP
         HYPER-LC IF  HYPER-LC HYPER-LINE C! HYPER-LINE COUNT
         ELSE  0 0  THEN EXIT
      THEN
      DUP 10 = IF
         DROP HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
      DUP 13 = IF
         DROP
         HYPER-EOF? 0= IF
            HYPER-BUF HYPER-POS + C@ 10 = IF  HYPER-CH DROP  THEN
         THEN
         HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
      HYPER-LC 255 < IF
         HYPER-LINE 1+ HYPER-LC + C!
         HYPER-LC 1+ TO HYPER-LC
      ELSE
         DROP
         BEGIN
            HYPER-CH
            DUP 0< OVER 10 = OR OVER 13 = OR 0=
         WHILE  DROP
         REPEAT
         DUP 13 = IF
            DROP
            HYPER-EOF? 0= IF
               HYPER-BUF HYPER-POS + C@ 10 = IF  HYPER-CH DROP  THEN
            THEN
         ELSE  DROP  THEN
         HYPER-LC HYPER-LINE C! HYPER-LINE COUNT EXIT
      THEN
   AGAIN ;

\ Stack while scanning: ( a u wlen ) — three cells.
\ ANS PICK: 0=TOS=wlen, 1=u, 2=a.  (3 PICK is out of range → bogus C@)
: HYPER-FIRST-WORD  ( a u -- wa wu ra ru )
   HYPER-SKIP-BL
   DUP 0= IF  2DUP EXIT  THEN
   0
   BEGIN
      1 PICK OVER >                \ u > wlen ?
   WHILE
      2 PICK OVER + C@ BL = IF     \ a[wlen] blank?
         >R                        \ R: wlen
         OVER R@  2SWAP            \ a wlen a u
         SWAP R@ + SWAP R@ -       \ a wlen (a+wlen) (u-wlen)
         R> DROP EXIT
      THEN
      1+
   REPEAT
   DROP
   2DUP + 0 ;

: HYPER-SET-CUR  ( a u -- )
   HYPER-CUR HYPER-PLACE ;

: HYPER->LINE  ( a u -- n true | false )
   HYPER-SKIP-BL
   DUP 0= IF  2DROP FALSE EXIT  THEN
   0 >R
   BEGIN  DUP WHILE
      OVER C@ DUP [CHAR] 0 [CHAR] 9 1+ WITHIN 0= IF
         DROP 2DROP R> DROP FALSE EXIT
      THEN
      [CHAR] 0 - R> 10 * + >R
      HYPER-SKIP1
   REPEAT
   2DROP R> TRUE ;

\ -----------------------------------------------------------------------------
\ Multi-hit / visit entry layout
\   byte0 = path count, bytes1..PATHMAX = path, cell @HOFF = line
\ PATHMAX was 55 — truncated absolute DerivedData paths mid-string (VIEW fail).
\ Prefer short Library/… paths from host; room for long abs paths if needed.
\ -----------------------------------------------------------------------------

247 CONSTANT HYPER-PATHMAX           \ max path chars in a hit entry
248 CONSTANT HYPER-HOFF              \ offset of line cell (aligned)
256 CONSTANT HYPER-HESZ
 32 CONSTANT HYPER-HMAX

CREATE HYPER-HTAB  HYPER-HMAX HYPER-HESZ * ALLOT
0 VALUE HYPER-HN
0 VALUE HYPER-HI
0 VALUE HYPER-VIEWING

: HYPER-HENT  ( i -- addr )  HYPER-HESZ * HYPER-HTAB + ;

: HYPER-CLEAR-HITS  ( -- )
   0 TO HYPER-HN  0 TO HYPER-HI
   0 HYPER-HIT C!  0 TO HYPER-LINE# ;

VARIABLE HYPER-TMP-LINE
VARIABLE HYPER-TMP-XT
VARIABLE HYPER-TMP-WID
VARIABLE HYPER-TMP-I
VARIABLE HYPER-TMP-J                 \ HIT-DUP must not clobber other scan indices
VARIABLE HYPER-TMP-N
VARIABLE HYPER-TMP-ADDR

\ True if HYPER-CUR + line already in hit table (path compare is
\ case-insensitive via HYPER-NAME= — same file as AutoLoad/x vs autoload/x).
: HYPER-HIT-DUP?  ( line -- flag )
   HYPER-TMP-LINE !
   0 HYPER-TMP-J !
   BEGIN  HYPER-TMP-J @ HYPER-HN < WHILE
      HYPER-TMP-J @ HYPER-HENT >R
      R@ HYPER-HOFF + @ HYPER-TMP-LINE @ = IF
         R@ COUNT HYPER-CUR COUNT HYPER-NAME= IF
            R> DROP TRUE EXIT
         THEN
      THEN
      R> DROP
      1 HYPER-TMP-J +!
   REPEAT
   FALSE ;

\ Store HYPER-CUR path + line into next table slot. ( line -- )
\ Dedup here so NDX + dict VIEW (or two NDX @ paths that differ only by case)
\ do not produce two "same" hits for VIEW VIEW etc.
: HYPER-STORE-HIT  ( line -- )
   DUP HYPER-HIT-DUP? IF  DROP EXIT  THEN
   HYPER-HN HYPER-HMAX >= IF  DROP EXIT  THEN
   HYPER-HN HYPER-HENT >R                \ R: ent  ( line )
   HYPER-CUR COUNT HYPER-PATHMAX MIN     \ line a u
   DUP R@ C!                             \ count at ent
   R@ 1+ SWAP CMOVE                      \ copy chars; leaves ( line )
   R@ HYPER-HOFF + !                     \ line → ent+HOFF
   R> DROP
   HYPER-HN 1+ TO HYPER-HN ;

\ Copy hit i into HYPER-HIT / HYPER-LINE#. ( i -- )
: HYPER-SELECT  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP HYPER-HN >= IF  DROP EXIT  THEN
   TO HYPER-HI
   HYPER-HI HYPER-HENT                   \ ent
   DUP C@ HYPER-PATHMAX MIN >R           \ ent  R: n
   R@ HYPER-HIT C!
   1+ HYPER-HIT 1+ R@ CMOVE              \ src dest u
   R> DROP
   HYPER-HI HYPER-HENT HYPER-HOFF + @ TO HYPER-LINE# ;

\ Leaf after last / or \ — console hit lines use this instead of absolute
\ DerivedData paths (VIEW/LOCATE stay readable after editor exit restore).
VARIABLE HYPER-LEAF-A
VARIABLE HYPER-LEAF-U
: HYPER-HIT-LEAF  ( -- c-addr u )
   HYPER-HIT COUNT
   DUP 0= IF  EXIT  THEN
   OVER HYPER-LEAF-A !
   DUP HYPER-LEAF-U !
   2DROP
   HYPER-LEAF-U @
   BEGIN  1- DUP 0< 0= WHILE
      HYPER-LEAF-A @ OVER + C@
      DUP [CHAR] / = SWAP [CHAR] \ = OR IF
         1+
         DUP HYPER-LEAF-A @ +             \ leaf-a
         SWAP HYPER-LEAF-U @ SWAP -       \ leaf-a leaf-u
         EXIT
      THEN
   REPEAT
   DROP
   HYPER-LEAF-A @ HYPER-LEAF-U @
;

\ Console location line: leaf:line [n/m]  (not full absolute path).
: HYPER-SHOW-HIT  ( -- )
   HYPER-HIT-LEAF TYPE [CHAR] : EMIT HYPER-LINE# 0 .R
   HYPER-HN 1 > IF
      ."  [" HYPER-HI 1+ 0 .R [CHAR] / EMIT HYPER-HN 0 .R ." ]"
   THEN
   CR
;

\ ( a u -- ) try one NDX body line; stack-clean
: (HYPER-TRY-LINE)  ( a u -- )
   HYPER-FIRST-WORD                      \ wa wu ra ru
   2SWAP                                 \ ra ru wa wu
   DUP HYPER-SEEK C@ <> IF  2DROP 2DROP EXIT  THEN
   HYPER-SEEK COUNT HYPER-NAME=          \ ra ru flag
   IF  HYPER->LINE IF  HYPER-STORE-HIT  THEN
   ELSE  2DROP  THEN ;

\ Append NDX hits for HYPER-SEEK (does not clear existing hits).
: (HYPER-COLLECT-NDX)  ( -- )
   HYPER-ENSURE 0= IF  EXIT  THEN
   0 TO HYPER-POS
   0 HYPER-CUR C!
   BEGIN  HYPER-EOF? 0= WHILE
      HYPER-READ-LINE
      DUP 0= IF  2DROP
      ELSE  OVER C@ [CHAR] # = IF  2DROP
      ELSE  OVER C@ 64 = IF
         DUP 1 < IF  2DROP
         ELSE  HYPER-SKIP1 HYPER-SKIP-BL
            DUP 0= IF  2DROP  ELSE  HYPER-SET-CUR  THEN
         THEN
      ELSE  (HYPER-TRY-LINE)
      THEN THEN THEN
   REPEAT ;

\ --- Dictionary VIEW hits (header file-id + line) ----------------------------
\ NOTE: TRAVERSE-WORDLIST keeps state on the return stack — do NOT use {: :}
\ locals inside visitors (corrupts traverse / leaves garbage for VIEW-REG).

\ Add one xt's VIEW (if present) to hit table. ( xt -- )
\ HYPER-STORE-HIT drops path+line duplicates (case-insensitive path).
: HYPER-ADD-XT-VIEW  ( xt -- )
   DUP VIEW-FILE# 0= IF  DROP EXIT  THEN
   DUP VIEW-LINE 0= IF  DROP EXIT  THEN
   >R
   R@ VIEW-FILE# VIEW-PATH              \ ca u | 0 0
   DUP 0= IF  2DROP R> DROP EXIT  THEN
   HYPER-CUR HYPER-PLACE                \ ( ca u dest )
   R> VIEW-LINE HYPER-STORE-HIT ;

\ One wordlist: hash SEARCH-WORDLIST only (never TRAVERSE — that compared
\ every same-length name via HYPER-NAME= and hung VIEW).
: HYPER-SCAN-WID  ( wid -- )
   DUP 0= IF  DROP EXIT  THEN
   >R HYPER-SEEK COUNT R> SEARCH-WORDLIST   \ 0 | xt 1 | xt -1
   DUP IF
      DROP                                  \ drop imm flag, leave xt
      HYPER-ADD-XT-VIEW
   ELSE
      DROP                                  \ not found
   THEN ;

CREATE HYPER-SEEN-WID  128 CELLS ALLOT
0 VALUE HYPER-SEEN-N
CREATE HYPER-ORDER-TMP  16 CELLS ALLOT
0 VALUE HYPER-ORDER-N

: HYPER-SEEN?  ( wid -- flag )
   HYPER-TMP-WID !
   0 HYPER-TMP-I !
   BEGIN  HYPER-TMP-I @ HYPER-SEEN-N < WHILE
      HYPER-SEEN-WID HYPER-TMP-I @ CELLS + @ HYPER-TMP-WID @ = IF
         TRUE EXIT
      THEN
      1 HYPER-TMP-I +!
   REPEAT
   FALSE ;

: HYPER-MARK-SEEN  ( wid -- )
   HYPER-SEEN-N 128 >= IF  DROP EXIT  THEN
   HYPER-SEEN-WID HYPER-SEEN-N CELLS + !
   HYPER-SEEN-N 1+ TO HYPER-SEEN-N ;

\ Dictionary VIEW hits: one FIND over the search order (same as the interpreter).
\
\ Why not SEARCH-WORDLIST on each GET-ORDER / WORDLISTS wid?
\ After ANEW/FORGET, search_order or the registry can still hold a stale wid
\ (old VOCABULARY head array in reclaimed dict). SEARCH-WORDLIST walks
\ heads[hash(name)] with no cycle guard — empty thread = instant miss (DUP),
\ cyclic garbage thread = hang forever (MAIN). FIND stops at the first hit in
\ order, so a later stale wid is never entered once FORTH has the word.
\ Multi-hit / CODE / asm sites still come from HYPER.NDX below.
\ FIND ( c-addr -- c-addr 0 | xt 1 | xt -1 ). IF consumes the flag, so on a
\ hit TOS is already xt — do NOT DROP it (that threw the xt away and left
\ HYPER-ADD-XT-VIEW to @ garbage → XFETCH crash). On a miss, DROP the c-addr.
: HYPER-COLLECT-DICT  ( -- )
   HYPER-SEEK FIND IF
      HYPER-ADD-XT-VIEW
   ELSE
      DROP
   THEN ;

: (HYPER-FIND)  ( c-addr u -- flag )
   63 MIN HYPER-SEEK HYPER-PLACE
   HYPER-CLEAR-HITS
   HYPER-COLLECT-DICT
   (HYPER-COLLECT-NDX)
   HYPER-HN 0= IF  FALSE EXIT  THEN
   0 HYPER-SELECT
   TRUE ;

\ Cached XTs (avoid ALSO/PREVIOUS/FIND every time — search order got stuck
\ after editor exit and FIND missed SZ-EDIT-FILE-AT).
0 VALUE HYPER-EDIT-XT                \ SZ-EDIT-FILE-AT
0 VALUE HYPER-GOTO-XT                \ SZ-HYPER-GOTO
0 VALUE HYPER-ACTIVE-XT              \ SZ-EDITOR-ACTIVE variable xt
0 VALUE HYPER-ORIGIN-XT              \ SZ-HYPER-ORIGIN
0 VALUE HYPER-HITS-XT                \ SZ-HYPER-HITS! ( cur tot -- )
0 VALUE HYPER-FL-NOTE-XT             \ SZ-FL-NOTE-HERE ( a u line -- )
0 VALUE HYPER-FL-REC-XT              \ SZ-FL-RECORD ( a u line -- )
0 VALUE HYPER-FL-CUR-XT              \ SZ-FL-CUR variable xt
0 VALUE HYPER-FL-CLR-XT              \ SZ-FL-CLEAR ( -- )
0 VALUE HYPER-FL-PUT-XT              \ SZ-FL-PUT ( a u line i -- )
0 VALUE HYPER-FL-SCUR-XT             \ SZ-FL-SET-CUR ( i -- )
FALSE VALUE HYPER-SKIP-NOTE?         \ true → next VIEW-NAME skips HIST-NOTE

\ -----------------------------------------------------------------------------
\ Visit list — same entry store/load as the tested jump stack (PUSH/POP-ORIGIN).
\ HYPER-VN = entries, HYPER-VI = current (0 .. VN-1).
\ Cmd-PgUp/PgDn move VI; new VIEW inserts after VI (keeps later entries).
\ -----------------------------------------------------------------------------
 32 CONSTANT HYPER-VMAX
CREATE HYPER-VTAB  HYPER-VMAX HYPER-HESZ * ALLOT
0 VALUE HYPER-VN
0 VALUE HYPER-VI
VARIABLE HYPER-V-IX                    \ slot index while storing

: HYPER-VENT  ( i -- addr )  HYPER-HESZ * HYPER-VTAB + ;

\ Store path+line at slot i. Body is the proven HYPER-PUSH-ORIGIN sequence.
\ Reject empty path — empty VTAB slots become blank FL rows / stale paint after
\ CLEAR without ERASE (fixed) and break index alignment with PUT-SLOT skips.
: HYPER-V-STORE  ( a u line i -- )
   2>R                                        \ R: line i  ( a u )  i = R-TOS
   DUP 0= IF  2DROP 2R> 2DROP EXIT  THEN      \ empty u
   R> HYPER-V-IX !                            \ R: line  ( a u )
   R@ 1 < IF  R> DROP 1 >R  THEN              \ clamp line on R
   HYPER-V-IX @ HYPER-VENT >R                 \ R: line ent
   HYPER-PATHMAX MIN
   DUP R@ C!
   R@ 1+ SWAP CMOVE
   R@ HYPER-HOFF +
   R> DROP
   R> SWAP !
;

\ Load slot i into HYPER-HIT / HYPER-LINE# (same as former POP load).
: HYPER-V-LOAD  ( i -- )
   HYPER-VENT                                \ ent
   DUP C@ HYPER-PATHMAX MIN >R               \ ent  R: n
   R@ HYPER-HIT C!
   DUP 1+ HYPER-HIT 1+ R@ CMOVE              \ leaves ent
   R> DROP
   HYPER-HOFF + @ TO HYPER-LINE#
;

\ Open a hole at ins: shift [ins, VN) up one (MOVE handles overlap).
: HYPER-V-OPEN  ( ins -- )
   DUP HYPER-VN > IF  DROP EXIT  THEN
   HYPER-V-IX !
   HYPER-VN HYPER-V-IX @ - DUP 0= IF  DROP EXIT  THEN
   HYPER-HESZ * >R
   HYPER-V-IX @ HYPER-VENT
   HYPER-V-IX @ 1+ HYPER-VENT
   R> MOVE
;

: HYPER-HIST-CLEAR  ( -- )  0 TO HYPER-VN  0 TO HYPER-VI ;

: HYPER-BIND-EDITOR  ( -- flag )
   ONLY FORTH ALSO EDITOR
   S" SZ-EDIT-FILE-AT" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-EDIT-XT  ELSE  DROP 0 TO HYPER-EDIT-XT  THEN
   S" SZ-HYPER-GOTO" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-GOTO-XT  ELSE  DROP 0 TO HYPER-GOTO-XT  THEN
   S" SZ-EDITOR-ACTIVE" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-ACTIVE-XT  ELSE  DROP 0 TO HYPER-ACTIVE-XT  THEN
   S" SZ-HYPER-ORIGIN" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-ORIGIN-XT  ELSE  DROP 0 TO HYPER-ORIGIN-XT  THEN
   S" SZ-HYPER-HITS!" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-HITS-XT  ELSE  DROP 0 TO HYPER-HITS-XT  THEN
   S" SZ-FL-NOTE-HERE" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-NOTE-XT  ELSE  DROP 0 TO HYPER-FL-NOTE-XT  THEN
   S" SZ-FL-RECORD" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-REC-XT  ELSE  DROP 0 TO HYPER-FL-REC-XT  THEN
   S" SZ-FL-CUR" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-CUR-XT  ELSE  DROP 0 TO HYPER-FL-CUR-XT  THEN
   S" SZ-FL-CLEAR" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-CLR-XT  ELSE  DROP 0 TO HYPER-FL-CLR-XT  THEN
   S" SZ-FL-PUT" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-PUT-XT  ELSE  DROP 0 TO HYPER-FL-PUT-XT  THEN
   S" SZ-FL-SET-CUR" HYPER-CMD HYPER-PLACE
   HYPER-CMD FIND IF  TO HYPER-FL-SCUR-XT  ELSE  DROP 0 TO HYPER-FL-SCUR-XT  THEN
   ONLY FORTH
   HYPER-EDIT-XT 0<> ;

\ Editor Cmd-click already noted origin — skip one HIST-NOTE in VIEW-NAME.
: HYPER-SKIP-NOTE  ( -- )  TRUE TO HYPER-SKIP-NOTE? ;

\ Temps so PLACE never sees (a u line) as a counted name.
VARIABLE HYPER-FL-A
VARIABLE HYPER-FL-U
VARIABLE HYPER-FL-LN
VARIABLE HYPER-FL-IX

: HYPER-FL-CALL3  ( name-a name-u -- )
   HYPER-CMD HYPER-PLACE
   ALSO EDITOR
   HYPER-CMD FIND IF
      >R
      HYPER-FL-A @ HYPER-FL-U @ HYPER-FL-LN @
      R> EXECUTE
   ELSE  DROP  THEN
   PREVIOUS
;

\ Prefer bound XTs (set by HYPER-BIND-EDITOR). FIND-per-slot was silent on
\ failure and left holes; stale FL memory then painted forth.s above hyper.
: HYPER-FL-ENSURE-BIND  ( -- )
   HYPER-FL-PUT-XT 0=  HYPER-FL-CLR-XT 0= OR  HYPER-FL-SCUR-XT 0= OR IF
      HYPER-BIND-EDITOR DROP
   THEN
;

: HYPER-FL-SHOW  ( c-addr u line -- )
   \ Keep for tests / diagnostics: append via ENSURE (not used by VIEW path).
   HYPER-FL-LN !  HYPER-FL-U !  HYPER-FL-A !
   S" SZ-FL-ENSURE-VISIT" HYPER-FL-CALL3
;

: HYPER-FL-NOTE  ( c-addr u line -- )
   HYPER-FL-LN !  HYPER-FL-U !  HYPER-FL-A !
   HYPER-FL-ENSURE-BIND
   HYPER-FL-NOTE-XT IF
      HYPER-FL-A @ HYPER-FL-U @ HYPER-FL-LN @
      HYPER-FL-NOTE-XT EXECUTE
   THEN
;

: HYPER-FL-SET-CUR  ( i -- )
   HYPER-FL-ENSURE-BIND
   HYPER-FL-SCUR-XT IF  HYPER-FL-SCUR-XT EXECUTE
   ELSE  DROP  THEN
;

: HYPER-FL-CLEAR  ( -- )
   HYPER-FL-ENSURE-BIND
   HYPER-FL-CLR-XT IF  HYPER-FL-CLR-XT EXECUTE  THEN
;

\ Copy VTAB[i] → FL[i] via bound SZ-FL-PUT (fixed index; preserves visit order).
\ Empty VTAB path: still consume i but do not PUT (and do not leave FL stale —
\ CLEAR already erased the table).
: HYPER-FL-PUT-SLOT  ( i -- )
   DUP HYPER-VENT C@ 0= IF  DROP EXIT  THEN
   HYPER-FL-IX !
   HYPER-FL-IX @ HYPER-VENT                   \ ent
   DUP 1+                                     \ ent body
   SWAP C@ HYPER-PATHMAX MIN                  \ body n
   DUP 0= IF  2DROP EXIT  THEN
   HYPER-FL-U !  HYPER-FL-A !                 \ path
   HYPER-FL-IX @ HYPER-VENT HYPER-HOFF + @ HYPER-FL-LN !
   HYPER-FL-PUT-XT 0= IF  EXIT  THEN
   HYPER-FL-A @ HYPER-FL-U @ HYPER-FL-LN @ HYPER-FL-IX @
   HYPER-FL-PUT-XT EXECUTE
;

\ Full panel = exact mirror of VTAB order (no insert-after scramble).
\ Uses bound XTs only — no ALSO/FIND mid-rebuild (search-order safe in KEY).
: HYPER-FL-REBUILD  ( -- )
   HYPER-FL-ENSURE-BIND
   HYPER-FL-CLEAR
   HYPER-VN 0= IF  0 HYPER-FL-SET-CUR  EXIT  THEN
   0
   BEGIN  DUP HYPER-VN < WHILE
      DUP HYPER-FL-PUT-SLOT
      1+
   REPEAT  DROP
   \ Clamp VI then highlight; TOP forced to 0 so first visits always paint in-band.
   HYPER-VI 0 MAX HYPER-VN 1- MIN TO HYPER-VI
   HYPER-VI HYPER-FL-SET-CUR
   S" SZ-FL-TOP" HYPER-CMD HYPER-PLACE
   ALSO EDITOR
   HYPER-CMD FIND IF  EXECUTE 0 SWAP !  ELSE  DROP  THEN
   PREVIOUS
;

: HYPER-SET-VI  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP HYPER-VN >= IF  DROP EXIT  THEN
   DUP TO HYPER-VI
   HYPER-FL-SET-CUR
;

\ Remove visit i from VTAB and rebuild side list.
\ If i was current, VI becomes previous (i-1) or 0 — editor should then
\ load that visit (see SZ-FL-CLOSE). Does not load/goto itself.
: HYPER-V-REMOVE  ( i -- )
   DUP 0< IF  DROP EXIT  THEN
   DUP HYPER-VN >= IF  DROP EXIT  THEN
   DUP HYPER-VI = >R                          \ R: was-current?
   HYPER-V-IX !
   HYPER-VN 1 = IF
      0 TO HYPER-VN  0 TO HYPER-VI
      R> DROP
      HYPER-FL-REBUILD EXIT
   THEN
   HYPER-VN HYPER-V-IX @ - 1- DUP 0> IF
      HYPER-HESZ * >R
      HYPER-V-IX @ 1+ HYPER-VENT
      HYPER-V-IX @ HYPER-VENT
      R> MOVE
   ELSE  DROP  THEN
   HYPER-VN 1- TO HYPER-VN
   R> IF
      \ Closed the current visit → land on previous row (or 0).
      HYPER-V-IX @ 1- 0 MAX
      HYPER-VN 1- MIN TO HYPER-VI
   ELSE
      HYPER-VI HYPER-V-IX @ > IF  HYPER-VI 1- TO HYPER-VI  THEN
      HYPER-VI HYPER-VN >= IF  HYPER-VN 1- 0 MAX TO HYPER-VI  THEN
   THEN
   HYPER-FL-REBUILD
;

\ Push multi-hit (1-based HI+1 / HN) into the editor status badge.
: HYPER-SYNC-HITS  ( -- )
   HYPER-HITS-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-HITS-XT 0= IF  EXIT  THEN
   HYPER-HN 0= IF  0 0 HYPER-HITS-XT EXECUTE EXIT  THEN
   HYPER-HI 1+ HYPER-HN HYPER-HITS-XT EXECUTE ;

: HYPER-EDITOR?  ( -- flag )
   HYPER-EDIT-XT IF  TRUE EXIT  THEN
   HYPER-BIND-EDITOR ;

: HYPER-EDITOR-ACTIVE?  ( -- flag )
   HYPER-ACTIVE-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-ACTIVE-XT IF  HYPER-ACTIVE-XT EXECUTE @  ELSE  FALSE  THEN ;

\ Goto visit i — load path:line, sync side-panel current.
: HYPER-V-GOTO  ( i -- )
   DUP TO HYPER-VI
   HYPER-V-LOAD
   HYPER-GOTO-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-GOTO-XT 0= IF  EXIT  THEN
   HYPER-HIT COUNT HYPER-LINE#
   HYPER-GOTO-XT EXECUTE
   \ Highlight the visit we jumped to (list already has rows from RECORD).
   HYPER-VI HYPER-FL-SET-CUR
   0 TO HYPER-HN
   0 TO HYPER-HI
   HYPER-SYNC-HITS
;

\ Save caret path:line as current visit (overwrite VI). Dual-write side list.
: HYPER-HIST-NOTE-HERE  ( -- )
   HYPER-EDITOR-ACTIVE? 0= IF  EXIT  THEN
   HYPER-ORIGIN-XT 0= IF
      HYPER-BIND-EDITOR DROP
      HYPER-ORIGIN-XT 0= IF  EXIT  THEN
   THEN
   HYPER-ORIGIN-XT EXECUTE                   \ a u line
   \ Empty path (untitled / no name) — do not poison VTAB.
   OVER 0= IF  DROP 2DROP EXIT  THEN
   >R                                        \ R: line  ( a u )
   HYPER-VN 0= IF
      2DUP R@ 0 HYPER-V-STORE
      1 TO HYPER-VN  0 TO HYPER-VI
      2DROP R> DROP
      HYPER-FL-REBUILD
      EXIT
   THEN
   \ Keep VI in range before overwrite.
   HYPER-VI 0 MAX HYPER-VN 1- MIN TO HYPER-VI
   2DUP R@ HYPER-VI HYPER-V-STORE
   2DROP R> DROP
   HYPER-FL-REBUILD
;

: HYPER-HIST-RECORD-DEST  ( -- )
   HYPER-HIT C@ 0= IF  EXIT  THEN
   HYPER-VN HYPER-VMAX >= IF
      HYPER-VN 1- TO HYPER-VN
      HYPER-VI 0> IF  HYPER-VI 1- TO HYPER-VI  THEN
      HYPER-VN IF
         HYPER-VTAB HYPER-HESZ +  HYPER-VTAB  HYPER-VN HYPER-HESZ * MOVE
      THEN
   THEN
   HYPER-VN 0= IF
      HYPER-HIT COUNT HYPER-LINE# 0 HYPER-V-STORE
      1 TO HYPER-VN  0 TO HYPER-VI
      HYPER-FL-REBUILD
      EXIT
   THEN
   \ Clamp VI so ins = VI+1 is never 0 unless VI was invalid (-1 → 0 → ins 1).
   HYPER-VI 0 MAX HYPER-VN 1- MIN TO HYPER-VI
   HYPER-VI 1+                               \ ins (1..VN) append or mid
   DUP HYPER-V-OPEN
   >R
   HYPER-HIT COUNT HYPER-LINE# R@ HYPER-V-STORE
   R@ TO HYPER-VI
   R> DROP
   HYPER-VN 1+ TO HYPER-VN
   \ Panel = exact VTAB mirror (order preserved).
   HYPER-FL-REBUILD
;

\ True if VTAB[i] matches path a u and line. ( a u line i -- flag )
: HYPER-V-SAME?  ( c-addr u line i -- flag )
   >R                                         \ R: i  a u line
   R@ HYPER-VENT HYPER-HOFF + @ <> IF
      R> DROP 2DROP FALSE EXIT
   THEN
   R> HYPER-VENT COUNT                        \ a u ea eu
   HYPER-NAME=
;

\ Index of path+line in VTAB, or -1. ( a u line -- i )
: HYPER-V-FIND  ( c-addr u line -- i )
   HYPER-TMP-LINE !
   HYPER-VN 0= IF  2DROP -1 EXIT  THEN
   0
   BEGIN  DUP HYPER-VN < WHILE
      >R 2DUP HYPER-TMP-LINE @ R@ HYPER-V-SAME? IF
         2DROP R> EXIT
      THEN
      R> 1+
   REPEAT
   DROP 2DROP -1
;

\ Ensure HYPER-HIT:line is a visit and current (for multi-hit Cmd-PgUp/Dn).
\ Already present → select that row; else insert after current (RECORD-DEST).
: HYPER-HIST-ENSURE-HIT  ( -- )
   HYPER-HIT C@ 0= IF  EXIT  THEN
   HYPER-HIT COUNT HYPER-LINE# HYPER-V-FIND
   DUP 0< IF
      DROP
      HYPER-HIST-RECORD-DEST
   ELSE
      TO HYPER-VI
      HYPER-VI HYPER-FL-SET-CUR
   THEN
;

\ ( c-addr u line -- ) open in SZ-EDITOR; rebinds if needed
: HYPER-OPEN-AT  ( c-addr u line -- )
   HYPER-EDIT-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
   HYPER-EDIT-XT 0= IF
      DROP 2DROP
      ." VIEW: load SZ-EDITOR first" CR
      ."   FROMLIB FLOAD Editor/SZ-EDITOR.fth" CR
      EXIT
   THEN
   HYPER-SYNC-HITS
   HYPER-EDIT-XT EXECUTE ;

\ In-editor: SZ-HYPER-GOTO ( a u line )
\ Multi-hit next/prev must also land in the visit / Files list (path+line).
: HYPER-APPLY-HIT  ( -- )
   HYPER-HN 0= IF  EXIT  THEN
   HYPER-SYNC-HITS
   HYPER-EDITOR-ACTIVE? IF
      HYPER-GOTO-XT 0= IF  HYPER-BIND-EDITOR DROP  THEN
      HYPER-GOTO-XT 0= IF  EXIT  THEN
      \ Record or select this hit in VTAB/side list before load+paint.
      HYPER-HIST-ENSURE-HIT
      HYPER-HIT COUNT HYPER-LINE#
      HYPER-GOTO-XT EXECUTE
   ELSE
      HYPER-VIEWING IF
         HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT
      THEN
   THEN ;

: HYPER-SHOW-HIT-SAFE  ( -- )
   HYPER-EDITOR-ACTIVE? IF  EXIT  THEN
   HYPER-SHOW-HIT ;

\ Cmd-PgDn / Cmd-PgUp  (matches README / HYPER-HELP)
\
\ Two lists (same FIND as VIEW / Cmd-click / Cmd-E):
\   1) Visit list (VN/VI) — path+line trail from VIEW / Cmd-E / Cmd-click.
\      PRIMARY: browser-style Back/Forward across files and positions.
\   2) Multi-hit (HN/HI) — all sites for the *current* search name (n/m badge).
\      Used when the visit list cannot move (only one visit, or at end/start).
\
\ Older code preferred multi-hit whenever HN>1, which trapped you inside one
\ name's hit list after a multi-site word and made Cmd-PgUp/Dn ignore visits.
\ Visit-first matches IDE “go back” and the shipped Hyper README.

: HYPER-HIT-NEXT  ( -- )
   HYPER-HN 0= IF
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: end of history" CR  THEN
      EXIT
   THEN
   HYPER-HI 1+
   DUP HYPER-HN >= IF
      DROP
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: last hit [" HYPER-HN . ." ]" CR  THEN
      EXIT
   THEN
   HYPER-SELECT
   HYPER-SHOW-HIT-SAFE
   HYPER-APPLY-HIT ;

: HYPER-HIT-PREV  ( -- )
   HYPER-HN 0= IF
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: start of history" CR  THEN
      EXIT
   THEN
   HYPER-HI 0= IF
      HYPER-EDITOR-ACTIVE? 0= IF  ." HYPER: first hit [1/" HYPER-HN 0 .R ." ]" CR  THEN
      EXIT
   THEN
   HYPER-HI 1- HYPER-SELECT
   HYPER-SHOW-HIT-SAFE
   HYPER-APPLY-HIT ;

: HYPER-VISIT-NEXT  ( -- flag )
   HYPER-VN 1 >  HYPER-VI 1+ HYPER-VN <  AND IF
      HYPER-VI 1+ TO HYPER-VI
      HYPER-VI HYPER-V-GOTO
      TRUE
   ELSE  FALSE  THEN ;

: HYPER-VISIT-PREV  ( -- flag )
   HYPER-VN 1 >  HYPER-VI 0>  AND IF
      HYPER-VI 1- TO HYPER-VI
      HYPER-VI HYPER-V-GOTO
      TRUE
   ELSE  FALSE  THEN ;

\ Kernel SEE xt for FORTH SEE fallback (must find system SEE, not ours).
ONLY FORTH
' SEE CONSTANT (SEE-OLD)
ONLY FORTH ALSO HYPER-VOC DEFINITIONS

\ Phase 3a/4 indexer (stays in HYPER-VOC; HYPER-REINDEX wrapper → FORTH).
FLOAD hyper-index.fth

\ Init with HYPER-VOC visible.
ONLY FORTH ALSO HYPER-VOC
HYPER-LOAD DROP
HYPER-BIND-EDITOR DROP

\ Public API once, in FORTH. CURRENT=FORTH; search order includes HYPER-VOC
\ so bodies resolve Hyper internals (HYPER-FIND, OPEN-AT, …).
ONLY FORTH DEFINITIONS ALSO HYPER-VOC

: HYPER-NEXT  ( -- )
   HYPER-VISIT-NEXT IF  EXIT  THEN
   HYPER-HIT-NEXT ;

: HYPER-PREV  ( -- )
   HYPER-VISIT-PREV IF  EXIT  THEN
   HYPER-HIT-PREV ;

: LOCATE  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." LOCATE needs a name" CR EXIT  THEN
   FALSE TO HYPER-VIEWING
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   HYPER-SHOW-HIT ;

: HYPER-VIEW-NAME  ( c-addr u -- )
   DUP 0= IF  2DROP EXIT  THEN
   HYPER-EDITOR? 0= IF  2DROP EXIT  THEN
   TRUE TO HYPER-VIEWING
   \ Cmd-click notes origin before mouse-place, then sets SKIP-NOTE.
   HYPER-EDITOR-ACTIVE? IF
      HYPER-SKIP-NOTE? IF  FALSE TO HYPER-SKIP-NOTE?
      ELSE  HYPER-HIST-NOTE-HERE  THEN
   THEN
   (HYPER-FIND) 0= IF
      HYPER-EDITOR-ACTIVE? 0= IF
         HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR
      THEN
      EXIT
   THEN
   HYPER-SHOW-HIT-SAFE
   \ Record dest *before* goto so side list shows the new visit on first paint.
   HYPER-HIST-RECORD-DEST
   HYPER-APPLY-HIT ;

: (VIEW)  ( c-addr u -- )
   DUP 0= IF  2DROP EXIT  THEN
   HYPER-EDITOR-ACTIVE? IF  HYPER-VIEW-NAME EXIT  THEN
   TRUE TO HYPER-VIEWING
   (HYPER-FIND) 0= IF
      HYPER-OK 0= IF  ." HYPER: index not loaded" CR
      ELSE  HYPER-SEEK COUNT TYPE ."  not in HYPER.NDX" CR  THEN
      EXIT
   THEN
   \ Editor shows path/line/(n/m); do not dump a long path onto the console
   \ (it would reappear after Cmd-W when the host restores the transcript).
   HYPER-EDITOR? 0= IF  HYPER-SHOW-HIT  THEN
   HYPER-HIST-CLEAR
   HYPER-HIT COUNT HYPER-LINE# 0 HYPER-V-STORE
   1 TO HYPER-VN  0 TO HYPER-VI
   HYPER-FL-REBUILD
   HYPER-HIT COUNT HYPER-LINE# HYPER-OPEN-AT ;

: VIEW  ( "name" -- )
   PARSE-NAME
   DUP 0= IF  2DROP ." VIEW needs a name" CR EXIT  THEN
   (VIEW) ;

: SEE-SOURCE  ( "name" -- )  VIEW ;

: HYPER-VIEW-CU  ( c-addr u -- )  HYPER-VIEW-NAME ;

: SEE  ( "name" -- )
   >IN @ >R
   PARSE-NAME
   DUP 0= IF  R> DROP 2DROP ." SEE needs a name" CR EXIT  THEN
   2DUP (HYPER-FIND) IF
      HYPER-EDITOR? IF
         R> DROP 2DROP
         TRUE TO HYPER-VIEWING
         HYPER-SHOW-HIT-SAFE
         HYPER-APPLY-HIT
         EXIT
      THEN
   THEN
   2DROP
   R> >IN !
   (SEE-OLD) EXECUTE ;

: HYPER-RELOAD  ( -- )
   HYPER-LOAD IF  ." HYPER: " HYPER-NDX-NAME COUNT TYPE
      ."  " HYPER-LEN . ." bytes" CR
   ELSE  ." HYPER: cannot open index" CR  THEN ;

: .HYPER  ( -- )
   CR ." HYPER " HYPER-NDX-NAME COUNT TYPE
   HYPER-OK IF  ."  " HYPER-LEN . ." bytes" CR
   ELSE  ."  not loaded" CR  THEN
   HYPER-HN IF
      ."   hits " HYPER-HN . ."  current " HYPER-HI 1+ . CR
      HYPER-SHOW-HIT
   THEN
   HYPER-VN IF
      ."   visit " HYPER-VI 1+ 0 .R [CHAR] / EMIT HYPER-VN 0 .R CR
   THEN ;

: HYPER-HELP  ( -- )
   CR
   ." LOCATE <name>     print path:line  [n/m] if multiple" CR
   ." VIEW <name>       open in SZ-EDITOR at line" CR
   ." SEE <name>        VIEW if editor loaded, else decompile" CR
   ." Cmd-PgUp/PgDn     visit history (back/forward); else multi-hit n/m" CR
   ." Cmd-Left/Right    prev/next occurrence in current editor file" CR
   ." Cmd-E / Cmd-click VIEW word; side list = visits (line# + [X] close)" CR
   ." HYPER-REINDEX     rebuild Config/HYPER.NDX, reload" CR
   ." HYPER-RELOAD  .HYPER   |  ALSO HYPER-VOC WORDS  |  ORDER" CR ;

\ Session order: FORTH then HYPER-VOC.
ONLY FORTH ALSO HYPER-VOC
GET-ORDER >R SWAP R> SET-ORDER
FORTH-WORDLIST SET-CURRENT

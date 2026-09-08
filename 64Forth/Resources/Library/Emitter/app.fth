\ app.fth — FORTH entry points: EMIT-APP / EMIT-WINDOW-APP (+ -TO)
\ Requires save.fth (and thus target/reloc/run). Public domain.
\
\ Public words parse the entry name from the input stream so the .app
\ basename matches the word (not LAST-INCLUDED — a nested REQUIRE like
\ big-int.fth must not rename PIMAIN.app):
\   FROMLIB FLOAD Emitter/emitter.fth
\   EMIT-APP MAIN                      \ → ./MAIN.app
\   FROMLIB EMIT-APP MAIN              \ → <LIBRARY-PATH>/MAIN.app
\   S" /tmp" EMIT-APP-TO MAIN          \ → /tmp/MAIN.app
\
\ Window wrapper (APP-NAME + WINDOW … WINDOW-OFF). Basename = parsed
\ word; window title = stem of LAST-INCLUDED when set, else the word:
\   FROMLIB FLOAD Emitter/emitter.fth
\   S" …/tetra/tetra.fth" INCLUDED
\   EMIT-WINDOW-APP GAME               \ → ./GAME.app, title TETRA
\   S" /tmp" EMIT-WINDOW-APP-TO GAME
\ Pass a body that expects an open window (e.g. GAME), not MAIN.
\
\ Stack-based (xt) variants — naming follows NAME>STRING of the xt
\ (less reliable if you pass a :NONAME or alias):
\   ' MAIN EMIT-APP-XT
\   ' MAIN S" /tmp" EMIT-APP-XT-TO
\   ' GAME EMIT-WINDOW-APP-XT
\   ' GAME S" /tmp" EMIT-WINDOW-APP-XT-TO
\
\ Both wrap the entry in CATCH. Default EMIT-ON-THROW prints the code
\ then KEY DROP; override with ' MY-HANDLER IS EMIT-ON-THROW before
\ emitting. WINDOW-OFF still runs after the handler.
\
\ Forces /EMIT-STANDALONE + /EMIT-UNBOUND, TGT-BUILDs, SAVE-IMAGEs, then
\ runs Library/Emitter/app-build.sh via SYSTEM (found via LIBRARY-PATH).

ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS
DECIMAL

512 CONSTANT /EMIT-PB
CREATE EMIT-APP-BUILD  /EMIT-PB ALLOT   \ counted path to app-build.sh (override OK)
CREATE EMIT-NAMEBUF    64 ALLOT         \ counted app basename / APP-NAME title
CREATE EMIT-IMGBUF     /EMIT-PB ALLOT   \ counted path to .img
CREATE EMIT-APPBUF     /EMIT-PB ALLOT   \ counted path to .app (message)
CREATE EMIT-CMDBUF     1024 ALLOT       \ counted SYSTEM command
CREATE EMIT-TMP        /EMIT-PB ALLOT
CREATE EMIT-TITLE      64 ALLOT         \ counted title for SLITERAL into wrapper

: (EMIT-S0)  ( dest -- )  0 SWAP C! ;

: (EMIT-S+)  ( c-addr u dest -- )
  {: a u dest | n -- :}
  dest C@ TO n
  n u + /EMIT-PB 1- > IF
    ." EMIT-APP: path too long" CR ABORT
  THEN
  a  dest CHAR+ n +  u MOVE
  n u + dest C! ;

: (EMIT-CH+)  ( char dest -- )
  SWAP PAD C!  PAD 1 ROT (EMIT-S+) ;

: (EMIT-UPC)  ( c -- c' )
  DUP [CHAR] a >= OVER [CHAR] z <= AND IF  32 -  THEN ;

\ Absolute or ~ path? (does not consume FROMLIB)
: (EMIT-ABS?)  ( c-addr u -- flag )
  DUP 0= IF  2DROP FALSE EXIT  THEN
  OVER C@ [CHAR] / = IF  2DROP TRUE EXIT  THEN
  OVER C@ [CHAR] ~ = IF  2DROP TRUE EXIT  THEN
  2DROP FALSE ;

\ Resolve outdir: relative + FROMLIB? → under LIBRARY-PATH (then FROMLIB-OFF).
\ Absolute unchanged. Relative without FROMLIB stays cwd-relative.
\ Result left counted in EMIT-TMP.
: (EMIT-RESOLVE-OUT)  ( c-addr u -- )
  {: a u | la lu -- :}
  a u (EMIT-ABS?) IF
    a u EMIT-TMP PLACE  EXIT
  THEN
  FROMLIB? 0= IF
    a u EMIT-TMP PLACE  EXIT
  THEN
  LIBRARY-PATH TO lu TO la
  lu 0= IF
    ." EMIT-APP: LIBRARY-PATH empty (no Library)" CR ABORT
  THEN
  EMIT-TMP (EMIT-S0)
  la lu EMIT-TMP (EMIT-S+)
  \ "." under Library → Library root itself
  u 1 =  a C@ [CHAR] . =  AND IF
    FROMLIB-OFF  EXIT
  THEN
  u IF
    [CHAR] / EMIT-TMP (EMIT-CH+)
    a u EMIT-TMP (EMIT-S+)
  THEN
  FROMLIB-OFF
  ;

\ Resolve app-build.sh via LIBRARY-PATH (does not consume user FROMLIB).
: (EMIT-RESOLVE-SH)  ( -- )
  EMIT-APP-BUILD C@ IF EXIT THEN
  LIBRARY-PATH DUP 0= IF
    2DROP ." EMIT-APP: LIBRARY-PATH empty (set EMIT-APP-BUILD)" CR ABORT
  THEN
  EMIT-APP-BUILD PLACE
  S" /Emitter/app-build.sh" EMIT-APP-BUILD (EMIT-S+)
  EMIT-APP-BUILD COUNT FILE-STATUS NIP IF
    ." EMIT-APP: app-build.sh missing: " EMIT-APP-BUILD COUNT TYPE CR ABORT
  THEN ;

: (EMIT-APP-NAME!)  ( xt -- )
  NAME>STRING DUP 0= IF
    2DROP ." EMIT-APP: empty word name" CR ABORT
  THEN
  DUP 63 > IF  2DROP ." EMIT-APP: name too long" CR ABORT  THEN
  EMIT-NAMEBUF PLACE ;

\ Path → uppercase stem in EMIT-NAMEBUF (…/tetra.fth → TETRA).
: (EMIT-STEM-UPPER!)  ( c-addr u -- )
  {: a u | i base blen -- :}
  0 TO base
  0 TO i
  BEGIN  i u <  WHILE
    a i + C@ [CHAR] / = IF  i 1+ TO base  THEN
    i 1+ TO i
  REPEAT
  u base - TO blen
  a base + TO a
  \ strip final .ext if present
  blen TO i
  BEGIN  i  WHILE
    i 1- TO i
    a i + C@ [CHAR] . = IF
      i TO blen
      0 TO i
    THEN
  REPEAT
  blen 0= IF  ." EMIT-WINDOW-APP: empty stem" CR ABORT  THEN
  blen 63 > IF  ." EMIT-WINDOW-APP: stem too long" CR ABORT  THEN
  EMIT-NAMEBUF (EMIT-S0)
  0 TO i
  BEGIN  i blen <  WHILE
    a i + C@ (EMIT-UPC) EMIT-NAMEBUF (EMIT-CH+)
    i 1+ TO i
  REPEAT
  ;

\ Window title only (EMIT-TITLE). Does not touch EMIT-NAMEBUF (basename).
\ Prefers LAST-INCLUDED stem; else xt name (uppercased).
\ Consumes xt from the stack; caller keeps its own copy (e.g. local).
: (EMIT-TITLE!)  ( xt -- )
  {: xt | -- :}
  LAST-INCLUDED DUP IF
    (EMIT-STEM-UPPER!)                 \ path → EMIT-NAMEBUF temp
  ELSE
    2DROP
    xt NAME>STRING DUP 0= IF
      2DROP ." EMIT-WINDOW-APP: no LAST-INCLUDED and empty xt name" CR ABORT
    THEN
    (EMIT-STEM-UPPER!)
  THEN
  EMIT-NAMEBUF COUNT EMIT-TITLE PLACE
  ;

\ Join outdir + "/" + name + suffix → dest counted string.
: (EMIT-JOIN)  ( out-addr out-u name-addr name-u suffix-addr suffix-u dest -- )
  {: oa ou na nu sa su dest -- :}
  dest (EMIT-S0)
  oa ou dest (EMIT-S+)
  ou IF
    oa ou + 1- C@ [CHAR] / <> IF  [CHAR] / dest (EMIT-CH+)  THEN
  THEN
  na nu dest (EMIT-S+)
  sa su dest (EMIT-S+) ;

: (EMIT-QUOTE+)  ( c-addr u dest -- )  \ append '…' (no escaping; Forth names are plain)
  {: a u dest -- :}
  [CHAR] ' dest (EMIT-CH+)
  a u dest (EMIT-S+)
  [CHAR] ' dest (EMIT-CH+) ;

: (EMIT-MKDIR)  ( c-addr u -- )
  DUP 1 = IF  OVER C@ [CHAR] . = IF  2DROP EXIT  THEN THEN
  EMIT-CMDBUF (EMIT-S0)
  S" mkdir -p " EMIT-CMDBUF (EMIT-S+)
  EMIT-CMDBUF (EMIT-QUOTE+)
  EMIT-CMDBUF COUNT SYSTEM IF
    ." EMIT-APP: mkdir failed" CR ABORT
  THEN ;

: (EMIT-PACK)  ( -- )  \ uses EMIT-NAMEBUF, EMIT-IMGBUF, outdir left in EMIT-TMP
  (EMIT-RESOLVE-SH)
  EMIT-CMDBUF (EMIT-S0)
  EMIT-APP-BUILD COUNT EMIT-CMDBUF (EMIT-QUOTE+)
  BL EMIT-CMDBUF (EMIT-CH+)
  EMIT-NAMEBUF COUNT EMIT-CMDBUF (EMIT-QUOTE+)
  BL EMIT-CMDBUF (EMIT-CH+)
  EMIT-IMGBUF COUNT EMIT-CMDBUF (EMIT-QUOTE+)
  BL EMIT-CMDBUF (EMIT-CH+)
  EMIT-TMP COUNT EMIT-CMDBUF (EMIT-QUOTE+)
  EMIT-CMDBUF COUNT SYSTEM IF
    ." EMIT-APP: app-build.sh failed" CR
    ."   cmd: " EMIT-CMDBUF COUNT TYPE CR ABORT
  THEN ;

: (EMIT-SAVE+PACK)  ( xt c-addr u -- )
  {: xt oa ou -- :}
  oa ou (EMIT-RESOLVE-OUT)          \ → EMIT-TMP; may consume FROMLIB
  xt (EMIT-APP-NAME!)
  EMIT-TMP COUNT (EMIT-MKDIR)
  EMIT-TMP COUNT  EMIT-NAMEBUF COUNT  S" .img"  EMIT-IMGBUF  (EMIT-JOIN)
  EMIT-TMP COUNT  EMIT-NAMEBUF COUNT  S" .app"  EMIT-APPBUF  (EMIT-JOIN)
  /EMIT-CONSOLE                     \ terminal I/O (SA-PRINT → write(1))
  /EMIT-STANDALONE
  /EMIT-UNBOUND
  xt TGT-BUILD
  xt EMIT-IMGBUF COUNT SAVE-IMAGE
  (EMIT-PACK)
  CR ." EMIT-APP: built " EMIT-APPBUF COUNT TYPE CR
  ."   image: " EMIT-IMGBUF COUNT TYPE CR
  ."   open " EMIT-APPBUF COUNT TYPE CR ;

\ Like (EMIT-SAVE+PACK) but EMIT-NAMEBUF already set (for :NONAME wrappers).
\ Caller arms /EMIT-WINDOW or /EMIT-CONSOLE before this (see *-APP-XT-TO).
: (EMIT-SAVE+PACK-NAMED)  ( xt c-addr u -- )
  {: xt oa ou -- :}
  oa ou (EMIT-RESOLVE-OUT)
  EMIT-NAMEBUF C@ 0= IF
    ." EMIT-WINDOW-APP: empty app name" CR ABORT
  THEN
  EMIT-TMP COUNT (EMIT-MKDIR)
  EMIT-TMP COUNT  EMIT-NAMEBUF COUNT  S" .img"  EMIT-IMGBUF  (EMIT-JOIN)
  EMIT-TMP COUNT  EMIT-NAMEBUF COUNT  S" .app"  EMIT-APPBUF  (EMIT-JOIN)
  /EMIT-STANDALONE
  /EMIT-UNBOUND
  xt TGT-BUILD
  xt EMIT-IMGBUF COUNT SAVE-IMAGE
  (EMIT-PACK)
  CR ." EMIT-APP: built " EMIT-APPBUF COUNT TYPE CR
  ."   image: " EMIT-IMGBUF COUNT TYPE CR
  ."   open " EMIT-APPBUF COUNT TYPE CR ;

\ --- public FORTH API ---
ONLY FORTH DEFINITIONS
ALSO SYSVOC ALSO EMITTER

\ Auto-CATCH handler (n -- ). Override before EMIT-APP / EMIT-WINDOW-APP:
\   : MY-THROW  ( n -- )  ... ;  ' MY-THROW IS EMIT-ON-THROW
\ Default prints the code then KEY DROP so the message stays visible before
\ exit; WINDOW-OFF still runs after the handler in the window wrap.

DEFER EMIT-ON-THROW

\ :NONAME  <xt> CATCH ?DUP IF <handler> THEN ;
\ Captures ACTION-OF EMIT-ON-THROW at wrap time.
\ LITERAL must be POSTPONEd: bare LITERAL is IMMEDIATE and would run while
\ compiling this word (stack underflow), not while compiling the :NONAME.
: (EMIT-CATCH-WRAP)  ( xt -- wxt )
  {: xt | h -- :}
  ACTION-OF EMIT-ON-THROW TO h
  :NONAME
    xt POSTPONE LITERAL
    POSTPONE CATCH
    POSTPONE ?DUP
    POSTPONE IF
      h COMPILE,
    POSTPONE THEN
  POSTPONE ;
  ;

\ Non-window EMIT-APP: FORTH TYPE + KEY (terminal).
: (EMIT-ON-THROW-DEFAULT)  ( n -- )
  S" exception " TYPE
  BASE @ >R  DECIMAL
  DUP 0< IF  S" -" TYPE  ABS  THEN
  S>D <# #S #> TYPE
  R> BASE !
  S\" \r\npress any key to exit " TYPE
  KEY DROP
  S\" \r\n" TYPE
  ;

\ Resolve GRAPHICS words by wid (not search order) so we never bind kernel KEY.
: (EMIT-GFX-XT)  ( c-addr u -- xt )
  2DUP GRAPHICS-WID SEARCH-WORDLIST
  ?DUP 0= IF  ." EMIT: missing GRAPHICS " TYPE CR ABORT  THEN
  DROP >R 2DROP R> ;

S" KEY"        (EMIT-GFX-XT) CONSTANT (EMIT-GFX-KEY)
S" WINDOW"     (EMIT-GFX-XT) CONSTANT (EMIT-GFX-WINDOW)
S" WINDOW-OFF" (EMIT-GFX-XT) CONSTANT (EMIT-GFX-WINDOW-OFF)
S" APP-NAME"   (EMIT-GFX-XT) CONSTANT (EMIT-GFX-APP-NAME)
S" TYPE"       (EMIT-GFX-XT) CONSTANT (EMIT-GFX-TYPE)

\ Error path only — success-path KEY belongs in the app source (e.g. PIMAIN),
\ same as tetra: ONLY FORTH ALSO GRAPHICS … KEY … Host (APP-KEY) waits;
\ see emit-host.inc.
: (EMIT-ON-THROW-WIN)  ( n -- )
  S" exception " (EMIT-GFX-TYPE) EXECUTE
  BASE @ >R  DECIMAL
  DUP 0< IF  S" -" (EMIT-GFX-TYPE) EXECUTE  ABS  THEN
  S>D <# #S #> (EMIT-GFX-TYPE) EXECUTE
  R> BASE !
  S\" \r\npress any key to exit " (EMIT-GFX-TYPE) EXECUTE
  (EMIT-GFX-KEY) EXECUTE DROP
  S\" \r\n" (EMIT-GFX-TYPE) EXECUTE
  ;

\ :NONAME  title APP-NAME WINDOW
\   <xt> CATCH ?DUP IF win-handler THEN
\   WINDOW-OFF ;
\ No automatic KEY here — the entry word decides (KEY DROP under GRAPHICS).
: (EMIT-WIN-WRAP)  ( xt c-addr u -- wxt )
  {: xt a u -- :}
  :NONAME
  a u POSTPONE SLITERAL
  (EMIT-GFX-APP-NAME)   POSTPONE LITERAL POSTPONE EXECUTE
  (EMIT-GFX-WINDOW)     POSTPONE LITERAL POSTPONE EXECUTE
  xt POSTPONE LITERAL
  POSTPONE CATCH
  POSTPONE ?DUP
  POSTPONE IF
    ['] (EMIT-ON-THROW-WIN) COMPILE,
  POSTPONE THEN
  (EMIT-GFX-WINDOW-OFF) POSTPONE LITERAL POSTPONE EXECUTE
  POSTPONE ;
  ;

' (EMIT-ON-THROW-DEFAULT) IS EMIT-ON-THROW

\ Parse "<name>" from the input stream → xt (ABORT if undefined).
: (EMIT-PARSE-XT)  ( -- xt )
  BL WORD FIND DUP 0= IF
    DROP COUNT ." EMIT-APP: undefined " TYPE CR ABORT
  THEN
  DROP ;

\ --- stack-based (xt) ---

: EMIT-APP-XT-TO  ( xt c-addr u -- )
  {: xt a u -- :}
  /EMIT-CONSOLE                       \ FORTH I/O stays console / SA-PRINT
  xt (EMIT-APP-NAME!)                 \ basename from xt (not :NONAME wrap)
  xt (EMIT-CATCH-WRAP) TO xt
  xt a u (EMIT-SAVE+PACK-NAMED) ;

: EMIT-APP-XT  ( xt -- )
  S" ." EMIT-APP-XT-TO ;

: EMIT-WINDOW-APP-XT-TO  ( xt c-addr u -- )
  {: xt a u -- :}
  /EMIT-WINDOW                        \ remap FORTH EMIT/TYPE/… → GRAPHICS
  xt (EMIT-APP-NAME!)                 \ basename from entry xt
  xt (EMIT-TITLE!)                    \ EMIT-TITLE from stem; clobbers NAMEBUF
  xt (EMIT-APP-NAME!)                 \ restore basename
  xt EMIT-TITLE COUNT (EMIT-WIN-WRAP) TO xt
  xt a u (EMIT-SAVE+PACK-NAMED) ;

: EMIT-WINDOW-APP-XT  ( xt -- )
  S" ." EMIT-WINDOW-APP-XT-TO ;

\ --- public: parse name from input; path on stack for *-TO ---

: EMIT-APP-TO  ( c-addr u -- )        \ S" /tmp" EMIT-APP-TO MAIN
  (EMIT-PARSE-XT) -ROT EMIT-APP-XT-TO ;

: EMIT-APP  ( -- )                    \ EMIT-APP MAIN
  S" ." EMIT-APP-TO ;

: EMIT-WINDOW-APP-TO  ( c-addr u -- ) \ S" /tmp" EMIT-WINDOW-APP-TO PIMAIN
  (EMIT-PARSE-XT) -ROT EMIT-WINDOW-APP-XT-TO ;

: EMIT-WINDOW-APP  ( -- )             \ EMIT-WINDOW-APP PIMAIN
  S" ." EMIT-WINDOW-APP-TO ;


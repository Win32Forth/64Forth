\ app.fth — FORTH entry points: EMIT-APP / EMIT-APP-TO
\ Requires save.fth (and thus target/reloc/run). Public domain.
\
\ After compiling a colon entry the normal way:
\   FROMLIB FLOAD Emitter/emitter.fth
\   ' MAIN EMIT-APP                 \ → ./MAIN.app
\   ' MAIN S" /tmp" EMIT-APP-TO     \ → /tmp/MAIN.app
\
\ Forces /EMIT-STANDALONE + /EMIT-UNBOUND, TGT-BUILDs, SAVE-IMAGEs, then
\ runs Library/Emitter/app-build.sh via SYSTEM.

ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS
DECIMAL

512 CONSTANT /EMIT-PB
CREATE EMIT-APP-BUILD  /EMIT-PB ALLOT   \ counted path to app-build.sh (override OK)
CREATE EMIT-NAMEBUF    64 ALLOT         \ counted app basename
CREATE EMIT-IMGBUF     /EMIT-PB ALLOT   \ counted path to .img
CREATE EMIT-APPBUF     /EMIT-PB ALLOT   \ counted path to .app (message)
CREATE EMIT-CMDBUF     1024 ALLOT       \ counted SYSTEM command
CREATE EMIT-TMP        /EMIT-PB ALLOT

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

\ Resolve app-build.sh once (Documents user tree, else bundle Resources).
\ Uses EMIT-APP-BUILD only — do not touch EMIT-TMP (outdir lives there).
: (EMIT-RESOLVE-SH)  ( -- )
  EMIT-APP-BUILD C@ IF EXIT THEN
  S\" sh -c 'for p in \"$HOME/Documents/64Forth/Library/Emitter/app-build.sh\" \"/Applications/64Forth.app/Contents/Resources/Library/Emitter/app-build.sh\"; do if [ -f \"$p\" ]; then printf %s \"$p\"; exit 0; fi; done; exit 1' > /tmp/64emit-app-build.path" SYSTEM
  IF
    ." EMIT-APP: cannot locate app-build.sh (set EMIT-APP-BUILD)" CR ABORT
  THEN
  S" /tmp/64emit-app-build.path" R/O OPEN-FILE THROW
  {: fid | n -- :}
  EMIT-APP-BUILD (EMIT-S0)
  EMIT-APP-BUILD CHAR+ /EMIT-PB 1- fid READ-FILE THROW TO n
  fid CLOSE-FILE DROP
  n 0= IF  ." EMIT-APP: empty app-build path" CR ABORT  THEN
  n EMIT-APP-BUILD C!
  EMIT-APP-BUILD COUNT FILE-STATUS NIP IF
    ." EMIT-APP: app-build.sh missing: " EMIT-APP-BUILD COUNT TYPE CR ABORT
  THEN ;

: (EMIT-APP-NAME!)  ( xt -- )
  NAME>STRING DUP 0= IF
    2DROP ." EMIT-APP: empty word name" CR ABORT
  THEN
  DUP 63 > IF  2DROP ." EMIT-APP: name too long" CR ABORT  THEN
  EMIT-NAMEBUF PLACE ;

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
  oa ou EMIT-TMP PLACE
  xt (EMIT-APP-NAME!)
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

: EMIT-APP-TO  ( xt c-addr u -- )
  (EMIT-SAVE+PACK) ;

: EMIT-APP  ( xt -- )
  S" ." EMIT-APP-TO ;

CR .( EMIT-APP / EMIT-APP-TO ready in FORTH. ) CR

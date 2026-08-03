\ sz-buffer.fth — SZ-EDITOR single text buffer + load/save (growable)
\
\ One in-memory document on the ANS ALLOCATE heap. Starts at 1 MB and grows
\ (doubling / as needed) for inserts and large loads — including future
\ copy/paste. Engine auto-grows linear memory if the heap is tight.
\
\ Lines may end with CR LF or LF (preserved as stored).
\ Byte addresses are cell values pointing into SZ-TBUF.
\
\ Prerequisites: sz-host.fth (or full File-Access already in dictionary)
\
\ Quick test (from a writable cwd, after loading modules):
\   S" notes.txt" SZ-LOAD-FILE THROW
\   SZ-.INFO
\   S" notes-copy.txt" SZ-SAVE-AS THROW
\   SZ-.INFO

DECIMAL

\ -----------------------------------------------------------------------------
\ Limits
\ -----------------------------------------------------------------------------

1048576 CONSTANT SZ-TBUF-MIN       \ initial capacity (1 MB)
     255 CONSTANT SZ-NAME-MAX      \ counted path capacity

\ -----------------------------------------------------------------------------
\ Storage (heap; not dictionary ALLOT)
\ -----------------------------------------------------------------------------

VARIABLE SZ-TBUF-ADDR              \ base address (0 until SZ-BUF-BOOT)
VARIABLE SZ-TBUF-CAP               \ current capacity in bytes
VARIABLE SZ-TLEN                   \ used bytes (0..SZ-TBUF-CAP)
VARIABLE SZ-MODIFIED               \ nonzero if buffer dirty
VARIABLE SZ-CUR                    \ insert point (byte addr in SZ-TBUF)
VARIABLE SZ-TOP                    \ first visible line start (screen)
CREATE SZ-FNAME  256 ALLOT         \ counted path of current file (0 = untitled)

: SZ-TBUF  ( -- addr )  SZ-TBUF-ADDR @ ;

\ -----------------------------------------------------------------------------
\ Grow capacity (preserves SZ-CUR / SZ-TOP offsets when buffer moves)
\ -----------------------------------------------------------------------------

\ ( need -- flag )  ensure capacity >= need; true = ok
\ Note: TZForth has no <= ; use > 0=  (a b > 0=  <=>  a <= b)
: SZ-ENSURE-CAP  ( need -- flag )
   DUP 0< IF  DROP 0 EXIT  THEN
   DUP SZ-TBUF-CAP @ > 0= IF  DROP -1 EXIT  THEN
   \ newcap = max(need, max(cap*2, SZ-TBUF-MIN))
   SZ-TBUF-CAP @ DUP IF  2*  ELSE  DROP SZ-TBUF-MIN  THEN
   MAX  SZ-TBUF-MIN MAX                     ( newcap )
   SZ-TBUF-ADDR @ 0= IF
      DUP ALLOCATE 0<> IF  DROP 0 EXIT  THEN
      SZ-TBUF-ADDR !
      SZ-TBUF-CAP !
      SZ-TBUF DUP SZ-CUR !  SZ-TOP !
      -1 EXIT
   THEN
   \ save cursor/top as offsets into current buffer (clamp if unset)
   SZ-CUR @ SZ-TBUF -  0 MAX
   SZ-TOP @ SZ-TBUF -  0 MAX
   2>R
   SZ-TBUF-ADDR @ OVER RESIZE 0<> IF
      DROP 2R> 2DROP 0 EXIT
   THEN                                    ( newcap a' )
   SZ-TBUF-ADDR !
   SZ-TBUF-CAP !
   2R>
   SZ-TBUF + SZ-TOP !
   SZ-TBUF + SZ-CUR !
   -1
;

: SZ-BUF-BOOT  ( -- )
   0 SZ-TBUF-ADDR !
   0 SZ-TBUF-CAP !
   0 SZ-TLEN !
   0 SZ-CUR !
   0 SZ-TOP !
   SZ-TBUF-MIN SZ-ENSURE-CAP 0= IF
      \ Use ." not .( — nested ) would end .( early; message is runtime-only.
      ." SZ-EDITOR: buffer ALLOCATE failed - need more heap/memory" CR
   THEN
;

\ -----------------------------------------------------------------------------
\ Buffer basics
\ -----------------------------------------------------------------------------

: SZ-TBUF0      ( -- addr )  SZ-TBUF ;
: SZ-TEND       ( -- addr )  SZ-TBUF SZ-TLEN @ + ;   \ one past last byte

: SZ-CLEAR-BUF  ( -- )
   0 SZ-TLEN !
   0 SZ-MODIFIED !
   0 SZ-FNAME C! ;

: SZ-EMPTY?     ( -- flag )  SZ-TLEN @ 0= ;

\ ( -- free )  bytes free in buffer
: SZ-FREE-BYTES ( -- n )  SZ-TBUF-CAP @ SZ-TLEN @ - ;

: SZ-FULL?      ( -- flag )  SZ-FREE-BYTES 0= ;

: SZ-TOUCH      ( -- )  -1 SZ-MODIFIED ! ;
: SZ-CLEAN      ( -- )   0 SZ-MODIFIED ! ;

\ Copy path into SZ-FNAME (counted)
: SZ-SET-NAME   ( c-addr u -- )
   SZ-FNAME SZ-PLACE ;

: SZ-GET-NAME   ( -- c-addr u )
   SZ-FNAME COUNT ;

: SZ-HAS-NAME?  ( -- flag )
   SZ-FNAME C@ 0<> ;

\ -----------------------------------------------------------------------------
\ Line scan — CR / LF / CRLF (pure Forth; TZForth used Swift host scans)
\ -----------------------------------------------------------------------------

$0A CONSTANT SZ-CH-LF
$0D CONSTANT SZ-CH-CR

: SZ-HOST-CLAMP  ( addr -- addr' )
   DUP SZ-TBUF U< IF  DROP SZ-TBUF  THEN
   DUP SZ-TEND U> IF  DROP SZ-TEND  THEN ;

\ ( addr -- addr' )  next CR or LF at/after addr, or SZ-TEND
: SZ-HOST-NEXT-EOL  ( addr -- addr' )
   SZ-HOST-CLAMP
   BEGIN
      DUP SZ-TEND SZ-U>= IF  EXIT  THEN
      DUP C@ DUP SZ-CH-LF = SWAP SZ-CH-CR = OR IF  EXIT  THEN
      1+
   AGAIN ;

\ ( addr -- addr' )  skip one EOL at addr (CRLF / CR / LF); else unchanged
: SZ-HOST-SKIP-EOL  ( addr -- addr' )
   SZ-HOST-CLAMP
   DUP SZ-TEND SZ-U>= IF  EXIT  THEN
   DUP C@ SZ-CH-CR = IF
      1+ DUP SZ-TEND U< IF  DUP C@ SZ-CH-LF = IF  1+  THEN  THEN
      EXIT
   THEN
   DUP C@ SZ-CH-LF = IF  1+  THEN ;

\ ( addr -- addr' )  start of line containing addr.
\ A line starts at TBUF or immediately after a previous line's EOL.
\ Consecutive LFs are separate empty lines (e.g. 0a 0a → starts at 0 and 1).
\ TEND after a final EOL is a new empty line (append point), start = TEND.
\ TEND with no trailing EOL is the end of the last content line.
: SZ-HOST-LINE-START  ( addr -- addr' )
   SZ-HOST-CLAMP
   DUP SZ-TBUF = IF  EXIT  THEN
   DUP SZ-TEND = IF
      \ Empty line only if last stored byte is EOL; else end of last content line
      DUP SZ-TBUF U> IF
         DUP 1- C@ SZ-CH-LF = IF  EXIT  THEN
         DUP 1- C@ SZ-CH-CR = IF  EXIT  THEN
      THEN
      1-                                   \ onto last content byte
   THEN
   BEGIN
      DUP SZ-TBUF = IF  EXIT  THEN
      DUP 1- C@
      DUP SZ-CH-LF = IF  DROP EXIT  THEN   \ after LF → line start
      DUP SZ-CH-CR = IF
         DROP
         \ prev=CR: if addr is LF (CRLF), step to CR and keep walking
         DUP C@ SZ-CH-LF = IF  1-  ELSE  EXIT  THEN
      ELSE
         DROP
      THEN
      1-
   AGAIN ;

: SZ-HOST-PREV-LINE  ( ls -- ls' )
   SZ-HOST-CLAMP
   DUP SZ-TBUF = IF  EXIT  THEN
   1- SZ-HOST-LINE-START ;

: SZ-HOST-NEXT-LINE  ( ls -- ls' )
   SZ-HOST-CLAMP
   DUP SZ-TEND SZ-U>= IF  DROP SZ-TEND EXIT  THEN
   SZ-HOST-NEXT-EOL SZ-HOST-SKIP-EOL ;

\ ( addr -- n )  1-based line number of byte addr.
\ Uses a VARIABLE (not >R) so it is safe inside DO/LOOP (R holds loop params).
VARIABLE SZ-LN-TGT
: SZ-HOST-LINE-NO  ( addr -- n )
   SZ-HOST-CLAMP SZ-LN-TGT !
   1 SZ-TBUF                        ( n p )
   BEGIN
      DUP SZ-LN-TGT @ U<
   WHILE
      DUP C@ SZ-CH-CR = IF
         1+ SWAP 1+ SWAP
         DUP SZ-LN-TGT @ U< IF  DUP C@ SZ-CH-LF = IF  1+  THEN  THEN
      ELSE DUP C@ SZ-CH-LF = IF
         1+ SWAP 1+ SWAP
      ELSE
         1+
      THEN THEN
   REPEAT
   DROP                              ( n )
;

\ ( from-ls to-ls -- n )  line steps from from to to (0 if to at/before from)
: SZ-HOST-LINE-STEPS  ( from to -- n )
   SZ-HOST-LINE-START >R
   SZ-HOST-LINE-START               ( from' )  ( R: to' )
   0 SWAP                           ( n p )
   BEGIN
      DUP R@ U<
   WHILE
      SZ-HOST-NEXT-LINE             ( n p' )
      SWAP 1+ SWAP
   REPEAT
   DROP R> DROP ;

VARIABLE SZ-ET-ROWS
VARIABLE SZ-ET-TOP
VARIABLE SZ-ET-CUR

\ ( cursor top rows -- newtop )  keep cursor line visible in rows text lines
: SZ-HOST-ENSURE-TOP  ( cursor top rows -- newtop )
   SZ-ET-ROWS !
   SZ-HOST-LINE-START SZ-ET-TOP !
   SZ-HOST-LINE-START SZ-ET-CUR !
   SZ-ET-CUR @ SZ-ET-TOP @ U< IF  SZ-ET-CUR @ EXIT  THEN
   SZ-ET-TOP @ SZ-ET-CUR @ SZ-HOST-LINE-STEPS
   SZ-ET-ROWS @ < IF  SZ-ET-TOP @ EXIT  THEN
   SZ-ET-CUR @
   SZ-ET-ROWS @ 1- 0 MAX 0 ?DO
      DUP SZ-HOST-PREV-LINE
      2DUP = IF  DROP LEAVE  THEN
      NIP
   LOOP ;

\ Thin aliases used by the rest of the editor
: SZ-NEXTLF       ( addr -- addr' )  SZ-HOST-NEXT-EOL ;
: SZ-LINE-START   ( addr -- addr' )  SZ-HOST-LINE-START ;
: SZ-PARSE-LINE   ( addr -- addr u )
   DUP SZ-HOST-NEXT-EOL OVER - ;
: SZ-NEXT-LINE    ( ls -- ls' )  SZ-HOST-NEXT-LINE ;
: SZ-PREV-LINE    ( ls -- ls' )  SZ-HOST-PREV-LINE ;
: SZ-LINE-COUNT   ( -- n )
   SZ-TLEN @ 0= IF  0 EXIT  THEN
   SZ-TEND 1- SZ-HOST-LINE-NO
   \ Trailing EOL means there is an empty line at TEND (append line)
   SZ-TEND 1- C@ SZ-CH-LF =
   SZ-TEND 1- C@ SZ-CH-CR = OR IF  1+  THEN
;

\ -----------------------------------------------------------------------------
\ Load / save
\ -----------------------------------------------------------------------------

\ Read entire file into buffer. ior = 0 success.
\ Grows the buffer to FILE-SIZE when needed. Does not change SZ-FNAME.
: SZ-LOAD-FILE  ( c-addr u -- ior )
   R/O OPEN-FILE                 ( fileid ior )
   DUP 0<> IF  NIP EXIT  THEN    \ open failed — leave ior only
   DROP >R                       ( R: fid )
   R@ FILE-SIZE                  ( ud ior )
   ?DUP IF  NIP NIP R> CLOSE-FILE DROP EXIT  THEN
   ( lo hi )  \ size as unsigned double; reject if high cell nonzero
   IF  DROP R> CLOSE-FILE DROP -59 EXIT  THEN   \ -59 result out of range
   ( size )
   DUP SZ-ENSURE-CAP 0= IF  DROP R> CLOSE-FILE DROP -59 EXIT  THEN
   SZ-TBUF SWAP R@ READ-FILE     ( u2 ior )
   ?DUP IF  R> CLOSE-FILE DROP EXIT  THEN
   SZ-TLEN !
   R> CLOSE-FILE DROP
   SZ-CLEAN
   0
;

\ Load and remember name (c-addr u is path)
: SZ-LOAD  ( c-addr u -- ior )
   2DUP SZ-SET-NAME
   SZ-LOAD-FILE
   DUP IF  0 SZ-FNAME C!  THEN     \ clear name on failure
;

\ Parse name from input and load:  SZ-LOAD" path"
: SZ-LOAD"  ( -- ior )
   [CHAR] " PARSE  SZ-LOAD
;

\ Save buffer to open path in SZ-FNAME. ior = 0 success.
: SZ-SAVE  ( -- ior )
   SZ-HAS-NAME? 0= IF  -1 EXIT  THEN   \ no name
   SZ-GET-NAME W/O CREATE-FILE       ( fileid ior )
   DUP 0<> IF  NIP EXIT  THEN
   DROP >R
   SZ-TBUF SZ-TLEN @ R@ WRITE-FILE   ( ior )
   ?DUP IF  R> CLOSE-FILE DROP EXIT  THEN
   R> CLOSE-FILE
   DUP 0= IF  SZ-CLEAN  THEN
;

\ Save to a new name (updates SZ-FNAME on success)
: SZ-SAVE-AS  ( c-addr u -- ior )
   2DUP SZ-SET-NAME
   SZ-SAVE
   DUP IF  0 SZ-FNAME C!  THEN
;

: SZ-SAVE-AS"  ( -- ior )
   [CHAR] " PARSE  SZ-SAVE-AS
;

\ -----------------------------------------------------------------------------
\ Status / smoke test
\ -----------------------------------------------------------------------------

: SZ-.INFO  ( -- )
   ." SZ-buffer: "
   SZ-HAS-NAME? IF  SZ-GET-NAME TYPE  ELSE  ." untitled"  THEN
   ."  bytes=" SZ-TLEN @ 0 .R
   ."  cap=" SZ-TBUF-CAP @ 0 .R
   ."  lines=" SZ-LINE-COUNT 0 .R
   ."  free=" SZ-FREE-BYTES 0 .R
   SZ-MODIFIED @ IF  ."  *modified*"  THEN
   CR
;

\ Dump buffer contents to the console (for verifying edits / save).
: SZ-TYPE-BUF  ( -- )
   SZ-TBUF SZ-TLEN @ TYPE CR
;

\ Re-load the current file from disk into the buffer (discards unsaved edits).
\ Useful after ⌃S + ⌃Q to prove the file on disk matches what you typed.
: SZ-RELOAD  ( -- ior )
   SZ-HAS-NAME? 0= IF  -1 EXIT  THEN
   SZ-GET-NAME SZ-LOAD-FILE
;

\ Two-byte CRLF helper (avoids depending on S\" escapes)
CREATE SZ-CRLF  SZ-CH-CR C, SZ-CH-LF C,

\ Write a short scratch file, load it, report, save a copy (needs writable cwd).
: SZ-BUFFER-SMOKE  ( -- )
   S" sz-smoke-out.txt" W/O CREATE-FILE  ( fid ior )
   DUP 0<> IF  ." sz-buffer smoke: CREATE failed ior=" . CR NIP EXIT  THEN
   DROP >R
   S" line1" R@ WRITE-FILE DROP
   SZ-CRLF 2 R@ WRITE-FILE DROP
   S" line2" R@ WRITE-FILE DROP
   SZ-CRLF 2 R@ WRITE-FILE DROP
   R> CLOSE-FILE DROP
   S" sz-smoke-out.txt" SZ-LOAD
   DUP IF  ." sz-buffer smoke: LOAD failed ior=" . CR EXIT  THEN  DROP
   SZ-.INFO
   S" sz-smoke-copy.txt" SZ-SAVE-AS
   DUP IF  ." sz-buffer smoke: SAVE-AS failed ior=" . CR EXIT  THEN  DROP
   ." sz-buffer: OK - load/save smoke wrote sz-smoke-out.txt and sz-smoke-copy.txt" CR
;

\ Allocate the initial 1 MB buffer when this module loads.
SZ-BUF-BOOT

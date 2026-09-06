\ save.fth — Phase 2b.1: persist / reload Emitter image (64EMIT02).
\ Requires target.fth + reloc.fth + run.fth.
\ Public domain.
\
\ Format (little-endian):
\   magic[8]="64EMIT02"
\   flags u64   bit0=has_data  bit1=unbound_host_relocs
\   code_len u64
\   data_len u64
\   entry_off u64   CFA byte offset within code
\   reloc_n u64
\   code_base u64   TGT-ORG at emit (for ITC rebase on load)
\   data_base u64   TGT-DATA-ORG at emit (0 if no data)
\   code[code_len]
\   data[data_len]
\   reloc[reloc_n] { off:u32, slot:u32 }  off relative to code base
\   ptr_n u64
\   ptr[ptr_n] { off:u32, spc:u32 }  spc 0=code 1=data; cells holding abs ptrs
\
\ Header size = 8 + 7*u64 = 64.

\ Loaded under EMITTER DEFINITIONS (see emitter.fth).
DECIMAL

64 CONSTANT /EMIT-HDR
1 CONSTANT EMIT-F-DATA
2 CONSTANT EMIT-F-UNBOUND

VARIABLE IMG-FID
VARIABLE IMG-ENTRY-OFF
VARIABLE IMG-FLAGS
VARIABLE IMG-CODE-LEN
VARIABLE IMG-DATA-LEN
VARIABLE IMG-RELOC-N
VARIABLE IMG-CODE-BASE
VARIABLE IMG-DATA-BASE

CREATE EMIT-MAGIC 8 ALLOT
S" 64EMIT02" EMIT-MAGIC SWAP CMOVE

: IMG-WRITE  ( c-addr u -- )
  IMG-FID @ WRITE-FILE IF
    ." SAVE-IMAGE: WRITE-FILE failed" CR ABORT
  THEN ;

: IMG-WRITE-U64  ( u -- )
  PAD !  PAD 8 IMG-WRITE ;

: IMG-WRITE-U32  ( u -- )
  DUP           $FF AND  PAD C!
  8 RSHIFT DUP  $FF AND  PAD 1+ C!
  8 RSHIFT DUP  $FF AND  PAD 2 + C!
  8 RSHIFT      $FF AND  PAD 3 + C!
  PAD 4 IMG-WRITE ;

: IMG-READ  ( c-addr u -- )
  {: a n -- :}
  a n IMG-FID @ READ-FILE  ( u2 ior )
  IF  DROP ." LOAD-IMAGE: READ-FILE failed" CR ABORT  THEN
  n <> IF  ." LOAD-IMAGE: short read" CR ABORT  THEN ;

: IMG-READ-U64  ( -- u )
  PAD 8 IMG-READ  PAD @ ;

: IMG-READ-U32  ( -- u )
  PAD 4 IMG-READ
  PAD C@
  PAD 1+ C@  8 LSHIFT OR
  PAD 2 + C@ 16 LSHIFT OR
  PAD 3 + C@ 24 LSHIFT OR ;

: IMG-DATA-BYTES  ( -- u )
  TGT-DATA-ORG @ IF
    TGT-DATA-DP @ TGT-DATA-ORG @ -
  ELSE  0  THEN ;

\ SAVE-IMAGE ( xt c-addr u -- )
\ xt must be mapped; image must still hold MAGIC|slot (use /EMIT-UNBOUND).
: SAVE-IMAGE  ( xt c-addr u -- )
  {: xt name u | entry dlen flags i off -- :}
  TGT-ORG @ 0= IF  ." SAVE-IMAGE: no image" CR ABORT  THEN
  HOST-RELOC-N @ IF
    HOST-UNBOUND? 0= IF
      ." SAVE-IMAGE: image already bound (use /EMIT-UNBOUND)" CR ABORT
    THEN
  THEN
  xt MAP-FIND DUP 0= IF
    ." SAVE-IMAGE: xt not mapped" CR ABORT
  THEN  TO entry
  entry TGT-ORG @ - IMG-ENTRY-OFF !
  IMG-DATA-BYTES TO dlen
  EMIT-F-UNBOUND TO flags
  dlen IF  flags EMIT-F-DATA OR TO flags  THEN
  name u W/O BIN CREATE-FILE IF
    DROP
    ." SAVE-IMAGE: CREATE-FILE failed for " name u TYPE CR ABORT
  THEN
  IMG-FID !
  EMIT-MAGIC 8 IMG-WRITE
  flags IMG-WRITE-U64
  TGT-SIZE IMG-WRITE-U64
  dlen IMG-WRITE-U64
  IMG-ENTRY-OFF @ IMG-WRITE-U64
  HOST-RELOC-N @ IMG-WRITE-U64
  TGT-ORG @ IMG-WRITE-U64
  TGT-DATA-ORG @ IMG-WRITE-U64
  TGT-ORG @ TGT-SIZE IMG-WRITE
  dlen IF  TGT-DATA-ORG @ dlen IMG-WRITE  THEN
  0 TO i
  BEGIN  i HOST-RELOC-N @ <  WHILE
    i CELLS HOST-RELOC-OFF + @ TGT-ORG @ - TO off
    off IMG-WRITE-U32
    i CELLS HOST-RELOC-SLOT + @ IMG-WRITE-U32
    i 1+ TO i
  REPEAT
  PTR-RELOC-N @ IMG-WRITE-U64
  0 TO i
  BEGIN  i PTR-RELOC-N @ <  WHILE
    i CELLS PTR-RELOC-OFF + @ TO off
    i PTR-RELOC-SPC + C@ IF
      off TGT-DATA-ORG @ - IMG-WRITE-U32
      1 IMG-WRITE-U32
    ELSE
      off TGT-ORG @ - IMG-WRITE-U32
      0 IMG-WRITE-U32
    THEN
    i 1+ TO i
  REPEAT
  IMG-FID @ CLOSE-FILE DROP
  0 IMG-FID !
  ." SAVE-IMAGE: " TGT-SIZE . ." code +" dlen . ." data +"
  HOST-RELOC-N @ . ." host +" PTR-RELOC-N @ . ." ptr -> " name u TYPE CR
  ;

\ Slide one absolute pointer cell from emit bases to load bases.
: IMG-REBASE-CELL  ( addr -- )
  {: a | v -- :}
  a @ TO v
  v IMG-CODE-BASE @ U< 0= IF
    v IMG-CODE-BASE @ IMG-CODE-LEN @ + U< IF
      v IMG-CODE-BASE @ - TGT-ORG @ +  a !  EXIT
    THEN
  THEN
  IMG-DATA-LEN @ IF
    v IMG-DATA-BASE @ U< 0= IF
      v IMG-DATA-BASE @ IMG-DATA-LEN @ + U< IF
        v IMG-DATA-BASE @ - TGT-DATA-ORG @ +  a !
      THEN
    THEN
  THEN ;

: IMG-REBASE  ( -- )
  {: | i off spc a -- :}
  \ Applied after LOAD fills PTR-RELOC-* from the file (see below).
  0 TO i
  BEGIN  i PTR-RELOC-N @ <  WHILE
    i CELLS PTR-RELOC-OFF + @ TO a
    a IMG-REBASE-CELL
    i 1+ TO i
  REPEAT ;

\ LOAD-IMAGE ( c-addr u -- )
\ Allocates fresh code/data, restores HOST-RELOC-* as absolute .quad sites,
\ leaves image RW and unbound.  Then TGT-RUN-LOADED or HOST-BIND + TGT-RUN-AT.
: LOAD-IMAGE  ( c-addr u -- )
  {: name u | codeu datau entryn relocn flags i off slot cbase dbase ptrn spc -- :}
  name u R/O BIN OPEN-FILE IF
    DROP
    ." LOAD-IMAGE: OPEN-FILE failed for " name u TYPE CR ABORT
  THEN
  IMG-FID !
  PAD 8 IMG-READ
  PAD 8 EMIT-MAGIC 8 COMPARE IF
    IMG-FID @ CLOSE-FILE DROP
    ." LOAD-IMAGE: bad magic (want 64EMIT02)" CR ABORT
  THEN
  IMG-READ-U64 TO flags
  IMG-READ-U64 TO codeu
  IMG-READ-U64 TO datau
  IMG-READ-U64 TO entryn
  IMG-READ-U64 TO relocn
  IMG-READ-U64 TO cbase
  IMG-READ-U64 TO dbase
  flags IMG-FLAGS !
  codeu IMG-CODE-LEN !
  datau IMG-DATA-LEN !
  entryn IMG-ENTRY-OFF !
  relocn IMG-RELOC-N !
  cbase IMG-CODE-BASE !
  dbase IMG-DATA-BASE !
  flags EMIT-F-UNBOUND AND 0= IF
    ." LOAD-IMAGE: warning — flags lack unbound bit" CR
  THEN
  relocn #HOST-RELOC U> IF
    ." LOAD-IMAGE: too many relocs" CR ABORT
  THEN
  \ Arena at least code size (TGT-OPEN closes previous image).
  codeu 4096 MAX TGT-OPEN
  TGT-ORG @ codeu IMG-READ
  TGT-ORG @ codeu + TGT-END !
  TGT-END @ TGT-DP !
  datau IF
    datau 4096 MAX TGT-DATA-OPEN
    TGT-DATA-ORG @ datau IMG-READ
    TGT-DATA-ORG @ datau + TGT-DATA-DP !
    datau TGT-DATA-BYTES !
  ELSE
    TGT-DATA-CLOSE
    0 TGT-DATA-BYTES !
  THEN
  HOST-RELOC-CLEAR
  0 TO i
  BEGIN  i relocn <  WHILE
    IMG-READ-U32 TO off
    IMG-READ-U32 TO slot
    TGT-ORG @ off +  i CELLS HOST-RELOC-OFF + !
    slot  i CELLS HOST-RELOC-SLOT + !
    1 HOST-RELOC-N +!
    i 1+ TO i
  REPEAT
  IMG-READ-U64 TO ptrn
  ptrn #PTR-RELOC U> IF
    ." LOAD-IMAGE: too many ptr relocs" CR ABORT
  THEN
  PTR-RELOC-CLEAR
  0 TO i
  BEGIN  i ptrn <  WHILE
    IMG-READ-U32 TO off
    IMG-READ-U32 TO spc
    spc IF
      TGT-DATA-ORG @ off +
    ELSE
      TGT-ORG @ off +
    THEN
    i CELLS PTR-RELOC-OFF + !
    spc i PTR-RELOC-SPC + C!
    1 PTR-RELOC-N +!
    i 1+ TO i
  REPEAT
  IMG-FID @ CLOSE-FILE DROP
  0 IMG-FID !
  IMG-REBASE
  \ No host xt map after load — run via TGT-RUN-LOADED.
  0 TGT-MAPN !
  HOST-APP-DISCOVER
  ." LOAD-IMAGE: " codeu . ." code +" datau . ." data +"
  relocn . ." host +" ptrn . ." ptr entry@" entryn U. CR
  ;

: TGT-RUN-LOADED  ( -- )
  TGT-ORG @ 0= IF  ." TGT-RUN-LOADED: no image" CR ABORT  THEN
  TGT-ORG @ IMG-ENTRY-OFF @ + TGT-RUN-AT ;

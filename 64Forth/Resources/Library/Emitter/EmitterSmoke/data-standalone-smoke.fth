\ data-standalone-smoke.fth — Phase 1: /EMIT-STANDALONE copies DATA into target.
\ Lives under Library/Emitter/EmitterSmoke. Does not modify tetra.fth.
\ Public domain.
\
\ Canonical: Xcode Resources/Library/Emitter (Documents/64Forth/Library is a symlink).
\ Prefer:  FROMLIB FLOAD Emitter/EmitterSmoke/data-standalone-smoke.fth
\ Agent:   …/64Forth --agent -f $HOME/Documents/64Forth/Library/Emitter/EmitterSmoke/data-standalone-smoke.fth

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS
S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED

\ Capture GRAPHICS xts before console-only search order.
['] MAIN  VALUE XT-MAIN
['] G-BUF VALUE XT-GBUF

\ Console IO — GRAPHICS shadows EMIT/TYPE/.
ONLY FORTH ALSO SYSVOC ALSO EMITTER

CR .( === hostdata MAIN build — identity imports === ) CR
/EMIT-HOSTDATA
XT-MAIN TGT-BUILD
CR .( hostdata written ) TGT-SIZE . CR
XT-GBUF MAP-FIND  XT-GBUF = .
CR .( G-BUF identity flag — expect -1 ) CR

CR .( === standalone MAIN build — copy DATA === ) CR
/EMIT-STANDALONE
XT-MAIN TGT-BUILD
CR .( standalone written ) TGT-SIZE . CR
CR .( data-bytes ) TGT-DATA-BYTES @ . CR
XT-GBUF MAP-FIND DUP XT-GBUF <> .
CR .( G-BUF relocated flag — expect -1 ) CR
HEX
CR .( mapped ) DUP U. CR
CR .( host   ) XT-GBUF U. CR
CR .( code   ) TGT-ORG @ U. TGT-END @ U. CR
CR .( data   ) TGT-DATA-ORG @ U. TGT-DATA-DP @ U. CR
DECIMAL

\ Expect G-BUF new xt inside the RW data segment
DUP TGT-DATA-ORG @ U< 0= . CR .( >=DATA-ORG flag ) CR
DUP TGT-DATA-DP @ U< . CR .( <DATA-DP flag ) CR
DROP

CR .( DONE data-standalone-smoke ) CR

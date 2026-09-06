\ emitter.fth — build the turnkey slicer (load into EMITTER vocabulary).
\ Public domain.
\
\ EMITTER and the native-helper rechain are created at cold start
\ (Kernel/vocemit.fth). This file only compiles the slicer sources into
\ EMITTER and leaves FORTH as CURRENT with EMITTER on the search order.
\
\ High-level stand-alone packaging lives in FORTH: EMIT-APP / EMIT-APP-TO
\ (see app.fth). Load, compile your entry word normally, then:
\   ' MAIN EMIT-APP
\
\   FROMLIB FLOAD Emitter/emitter.fth
\   ALSO EMITTER          \ if a prior ONLY cleared it

\ SYSVOC holds (LOOP)/(+LOOP)/(?DO)/(DO) etc. used by the slicer sources.
\ Do not ALSO GRAPHICS here — it shadows TYPE/EMIT/CR and breaks the slicer.
\ Phase 2a finds (APP-*) via SEARCH-WORDLIST on the GRAPHICS wid (reloc.fth).
ONLY FORTH ALSO SYSVOC ALSO EMITTER DEFINITIONS

FROMLIB FLOAD Emitter/reach.fth
FROMLIB FLOAD Emitter/target.fth
FROMLIB FLOAD Emitter/reloc.fth
FROMLIB FLOAD Emitter/run.fth
FROMLIB FLOAD Emitter/save.fth
FROMLIB FLOAD Emitter/app.fth

\ app.fth leaves FORTH as CURRENT with EMITTER on the search order.
CR .( emitter loaded — EMITTER slicer + FORTH EMIT-APP.) CR

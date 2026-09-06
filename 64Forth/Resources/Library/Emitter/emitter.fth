\ emitter.fth — build the turnkey slicer (load into EMITTER vocabulary).
\ Public domain.
\
\ EMITTER and the native-helper rechain are created at cold start
\ (Kernel/vocemit.fth). This file only compiles the slicer sources into
\ EMITTER and leaves FORTH as CURRENT with EMITTER on the search order.
\
\ High-level “compile a real program” entry points are not written yet;
\ when they appear they should be defined in FORTH and call into EMITTER.
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

\ Leave FORTH as CURRENT; keep EMITTER (and SYSVOC under it) for clients.
ONLY FORTH DEFINITIONS
ALSO SYSVOC ALSO EMITTER

CR .( emitter loaded — words are in the EMITTER vocabulary.) CR

\ dbg-pause.fth — Forth ITC DEBUG pause UI (phase 2)
\ Loaded from debugger.fth into DEBUGGER (ALSO SYSVOC for kernel helpers).
\ Autoload arms DBG-PAUSE-INSTALL. Kernel calls DBG-PAUSE-XT when set;
\ 0 keeps asm _debug_pause UI. Revert: 0 DBG-PAUSE-XT !  or DBG-CLEAR-HOOKS.

\ Help line (ASCII; matches asm str_dbg_keys intent).
: DBG-TYPE-HELP  ( -- )
  ." [F6/Space/o/Return=over F7/i=into(I>>) F8=out Esc/q=abort Cmd-Shift-Y/g=go h=help]"
;

: DBG-PRINT-STACKS-UI  ( -- )
  DBG-.SR  CR
;

: DBG-PRINT-TOKEN-UI  ( -- )
  0 DBG-LINE-COL !
  DBG-XT-INTOABLE? IF  ." I>> "  ELSE  ." >> "  THEN
  DBG-PRINT-NAME
  DBG-PRINT-INLINE
  SPACE
  DBG-CURSOR-ON
;

\ Intro once; else post-step S/R for the word that just finished.
: DBG-PAUSE-PREAMBLE  ( -- )
  DBG-NEED-INTRO @ IF
    0 DBG-NEED-INTRO !
    DBG-MIDLINE @ IF  0 DBG-MIDLINE !  CR  THEN
    DBG-TYPE-HELP CR
    DBG-PRINT-STACKS-UI
  ELSE
    DBG-NEED-STACKS @ IF
      0 DBG-NEED-STACKS !
      DBG-HELP-SHOWN @ IF
        0 DBG-HELP-SHOWN !
        CR  DBG-PRINT-STACKS-UI
      ELSE
        DBG-PRINT-STACKS-UI
      THEN
    THEN
  THEN
;

: DBG-PAUSE-HELP  ( -- )
  DBG-HELP-SHOWN @ IF  EXIT  THEN
  DBG-CURSOR-OFF
  DBG-TYPE-HELP
  -1 DBG-HELP-SHOWN !
  DBG-CURSOR-ON
;

\ Decode EKEY → mode. Wheel keys are saved in DBG-PAUSE-KEY.
\   0 ignore/retry   1 over   2 into   3 out
\   4 go             5 abort  6 wheel  7 help
0 CONSTANT DBG-MOD-IGNORE
1 CONSTANT DBG-MOD-OVER
2 CONSTANT DBG-MOD-INTO
3 CONSTANT DBG-MOD-OUT
4 CONSTANT DBG-MOD-GO
5 CONSTANT DBG-MOD-ABORT
6 CONSTANT DBG-MOD-WHEEL
7 CONSTANT DBG-MOD-HELP

VARIABLE DBG-PAUSE-KEY

: DBG-CH-EQ  ( c c1 c2 -- flag )  \ true if c equals c1 or c2
  ROT DUP >R = SWAP R> = OR
;

: DBG-PAUSE-DECODE-FKEY  ( k -- mode )
  CASE
    K-F6 OF  DBG-MOD-OVER  ENDOF
    K-F7 OF  DBG-MOD-INTO  ENDOF
    K-F8 OF  DBG-MOD-OUT   ENDOF
    DBG-MOD-IGNORE SWAP
  ENDCASE
;

: DBG-PAUSE-DECODE-CHAR  ( c -- mode )
  \ Drop leftover CR/LF from the DEBUG command line once.
  DBG-SKIP-NL @ IF
    DUP 10 = OVER 13 = OR IF  DROP  DBG-MOD-IGNORE EXIT  THEN
    0 DBG-SKIP-NL !
  THEN
  DUP [CHAR] h [CHAR] H DBG-CH-EQ IF  DROP  DBG-MOD-HELP  EXIT  THEN
  DUP 134 = OVER [CHAR] g [CHAR] G DBG-CH-EQ OR IF
    DROP  DBG-MOD-GO  EXIT
  THEN
  DUP 27 = OVER [CHAR] q [CHAR] Q DBG-CH-EQ OR IF
    DROP  DBG-MOD-ABORT  EXIT
  THEN
  DUP BL = OVER 13 = OR OVER [CHAR] o [CHAR] O DBG-CH-EQ OR IF
    DROP  DBG-MOD-OVER  EXIT
  THEN
  DUP [CHAR] i [CHAR] I DBG-CH-EQ IF  DROP  DBG-MOD-INTO  EXIT  THEN
  \ Wheel / resize wake (host specials).
  DUP 3 = OVER 7 = OR OVER 0 = OR IF
    DBG-PAUSE-KEY !  DBG-MOD-WHEEL  EXIT
  THEN
  DROP  DBG-MOD-IGNORE
;

: DBG-PAUSE-DECODE  ( u -- mode )
  DUP EKEY>FKEY IF
    NIP  DBG-PAUSE-DECODE-FKEY  EXIT
  THEN
  EKEY>CHAR IF
    DBG-PAUSE-DECODE-CHAR
  ELSE
    DROP  DBG-MOD-IGNORE
  THEN
;

: DBG-PAUSE-UI  ( -- )
  \ Match asm order: post-step S/R (pad to col 23) + >> word + cursor,
  \ then editor sync/HL. Sync before print poisoned DBG-LINE-COL / pad.
  DBG-PAUSE-PREAMBLE
  DBG-PRINT-TOKEN-UI
  [DEFINED] DBG-VIEW-UPDATE [IF]  DBG-VIEW-UPDATE  [THEN]
  BEGIN
    EKEY DBG-PAUSE-DECODE
    CASE
      DBG-MOD-IGNORE OF  FALSE  ENDOF
      DBG-MOD-HELP   OF  DBG-PAUSE-HELP  FALSE  ENDOF
      DBG-MOD-WHEEL  OF  DBG-PAUSE-KEY @ DBG-WHEEL-DO  FALSE  ENDOF
      DBG-MOD-OVER   OF  DBG-STEP-OVER  TRUE  ENDOF
      DBG-MOD-INTO   OF  DBG-STEP-INTO  TRUE  ENDOF
      DBG-MOD-OUT    OF  DBG-STEP-OUT   TRUE  ENDOF
      DBG-MOD-GO     OF  DBG-GO         TRUE  ENDOF
      DBG-MOD-ABORT  OF  DBG-ABORT-SESSION  TRUE  ENDOF
      FALSE SWAP
    ENDCASE
  UNTIL
;

\ Phase 3: arm Forth key policy only (short call_xt; asm still prints/waits).
: DBG-KEY-INSTALL  ( -- )
  ['] DBG-PAUSE-DECODE DBG-KEY-XT !
;

: DBG-KEY-UNINSTALL  ( -- )
  0 DBG-KEY-XT !
;

\ Phase 2 full UI — Autoload default (asm fallback: 0 DBG-PAUSE-XT !).
: DBG-PAUSE-INSTALL  ( -- )
  ['] DBG-PAUSE-UI IS DBG-PAUSE
  ['] DBG-PRINT-TOKEN-UI IS DBG-PRINT-TOKEN
  ['] DBG-PRINT-STACKS-UI IS DBG-PRINT-STACKS
  ['] DBG-PAUSE-UI DBG-SET-PAUSE
;

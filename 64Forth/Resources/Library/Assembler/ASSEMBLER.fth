\ Assembler/ASSEMBLER.fth — 64Forth interactive CODE / END-CODE
\ Not loaded by 64TCOM. Requires the ASMARM64 toolkit.
\
\ Just enter the following line to add the assembler to the
\ dictionary. CODE is automatically added to the FORTH vocabulary,
\ and also automatically adds the ASMARM64 vocabulary to the
\ search order. END-CODE ends an assembler definition and
\ automatically compiles NEXT at the end of the instructions,
\ along with restoring the search ordr to the FORTH vocabulary.
\
\   FROMLIB FLOAD Assembler/ASSEMBLER.fth
\
\ NOTE: BEcause the assembler lives in ASMARM.fth, we do not want to
\ create a new vocabulary ASSEMBLER because ASSEMBLER has already
\ been defined as a synonym for the vocabulary ASMARM64.
\
\ Public domain.

FORTH DEFINITIONS
DECIMAL

[UNDEFINED] ASM-CLEAR [IF]
  S" Assembler/asmarm64.fth" FROMLIB INCLUDED
[THEN]

[UNDEFINED] LAST [IF]
  S" HOST-CODE: LAST required to patch CFA" TYPE CR
  \\S
[THEN]

\ Kernel ITC aliases (64Forth inner interpreter — not TCOM leaves)
\ x19 = IP   x20 = TOS   x21 = W (CFA)   x22 = DSP   x28 = debug flag

ALSO ASMARM64 DEFINITIONS

\ NEXT without the cbnz x28 / next_debug (JIT page cannot reach that label)
DOC" NEXT, ( -- ) emit ITC NEXT: fetch next xt and branch to its code"
: NEXT,  ( -- )
  $F8408675 W,          \ LDR X21, [X19], #8
  $F94002A1 W,          \ LDR X1,  [X21]
  $D61F0020 W,          \ BR  X1
  ;
  
ONLY FORTH DEFINITIONS
ALSO ASMARM64

VARIABLE CODE-CFA               \ CFA of the CODE word being built

DOC" CODE ( -- ) define a kernel-style CODE word; assemble until END-CODE"
: CODE  ( -- )
  CREATE
  LAST CODE-CFA !            \ LAST is the new CFA (64Forth header)
  ASM-CLEAR  ALIGN4-T
  ALSO ASMARM64 DEFINITIONS
  TRUE TO ?ASM-ACTIVE
  LL-INIT
  BTI-C,                       \ Apple landing pad
  ;

DOC" END-CODE ( -- ) emit NEXT, make RX copy, set CFA, leave assembler"
: END-CODE  ( -- )
  NEXT,
  ASM-MAKE-EXEC                 \ ( -- exec-addr ) entry = offset 0
  CODE-CFA @ !                  \ CFA cell → native entry
  ?ASM-ACTIVE IF
    PREVIOUS FORTH DEFINITIONS
    FALSE TO ?ASM-ACTIVE
  THEN
  ;

: C;  ( -- )  END-CODE ; IMMEDIATE



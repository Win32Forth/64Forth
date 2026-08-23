\ ASMARM64.fth — Forth-style AArch64 assembler for 64TCOM + 64Forth
\ Synced Aug 23, 2026 3:16 PM — keep 64TCOMARM64/ASMARM64.fth and Library/Assembler/asmarm64.fth identical.
\
\ Public domain. Dual-load toolkit (Phase 3.2).
\
\ Two homes (keep identical — see Synced stamp above):
\   64TCOMARM64/ASMARM64.fth
\       Loaded by FLOAD TARGETARM64.fth (pack emitters for OPT/LIB).
\   64Forth Resources/Library/Assembler/asmarm64.fth
\       Loaded only via FROMLIB on interactive 64Forth — NOT by TCOM.
\
\ Backend selection (not \ANS/\TCOM — pack flips those after INCLUDE):
\   Pack:  T-CODE-BASE defined → C,-T / HERE-T target image
\   Host:  no T-CODE-BASE → host ASM buffer + MARKER overlay / DISCARD
\ Docs: STATUSASM64.md  ASMARM64.md  ASMARMTESTS.fth → ASM-TESTS
\
\ ABI (subroutine-threaded Forth):
\   X0 = TOS   X19 = DSP   X1 = scratch   X16 = call   X30 = LR
\
\ Emit model: HERE-T is a *code offset* (taddr) on both backends.
\ Host: ASM-BASE@ + taddr = absolute address; ASM-ENTRY maps for CALL-NATIVE.

FORTH DEFINITIONS
DECIMAL

\ ----- Dual-load line directives (if not already present) -----
[UNDEFINED] DIRECTIVE [IF]
: SKIP-REST  ( -- )
  BEGIN
    >IN @ SOURCE NIP >= IF EXIT THEN
    SOURCE DROP >IN @ + C@
    DUP 10 = OVER 13 = OR IF  DROP 1 >IN +! EXIT  THEN
    DROP 1 >IN +!
  AGAIN
  ;
: DIRECTIVE  ( flag "<spaces>name" -- )
  CREATE , IMMEDIATE
  DOES> @ 0= IF  SKIP-REST  THEN
  ;
[THEN]
[UNDEFINED] \ANS [IF]
TRUE  DIRECTIVE \ANS
FALSE DIRECTIVE \TCOM
[THEN]

[UNDEFINED] TCOM-ANEW [IF]
: TCOM-ANEW  ( "<spaces>name" -- )
  >IN @
  BL WORD FIND IF
    DROP OVER >IN ! FORGET
  ELSE
    DROP
  THEN
  >IN !  CREATE
  ;
[THEN]

[UNDEFINED] TCOM-ABORT [IF]
: TCOM-ABORT  ( c-addr u -- )  TYPE CR ABORT ;
[THEN]

[UNDEFINED] U>= [IF]
: U>=  ( u1 u2 -- flag )  U< 0= ;
[THEN]
[UNDEFINED] U<= [IF]
: U<=  ( u1 u2 -- flag )  U> 0= ;
[THEN]

\ Detect pack (64HOST) vs standalone 64Forth host load.
\ NOTE: TARGETARM64 flips \ANS/\TCOM *after* including this file, so do not
\ use \ANS/\TCOM here to choose the emit backend.
[DEFINED] T-CODE-BASE [IF]
[ELSE]
\ Discard lives *before* the overlay marker so restoring the dictionary
\ does not cut this word. EVALUATE: free buffers, then run MARKER.
: ASMARM64-DISCARD  ( -- )
  S" ASM-FREE-EXEC ASM-FREE-BUF ASMARM64-OVERLAY" EVALUATE
  S" ASMARM64-DISCARD: overlay removed." TYPE CR
  ;

\ ----- ANS / host overlay: buffer + emit API + discardable marker -----
MARKER ASMARM64-OVERLAY

TRUE VALUE ASMARM64-HOST?

[UNDEFINED] SETASSEM [IF]
DEFER SETASSEM
DEFER A;
DEFER END-CODE
: (ASM-STUB-NOOP)  ( -- )  ;
' (ASM-STUB-NOOP) IS SETASSEM
' (ASM-STUB-NOOP) IS A;
' (ASM-STUB-NOOP) IS END-CODE
[THEN]

65536 CONSTANT ASM-DEFAULT-SIZE
5 CONSTANT ASM-PROT-RX

VARIABLE ASM-BASE          \ host addr of RW assemble buffer (0 = none)
VARIABLE ASM-DP            \ emit offset (HERE-T)
VARIABLE ASM-LIMIT         \ buffer size in bytes
VARIABLE ASM-EXEC          \ ALLOCATE-EXEC base (0 = none)
VARIABLE ASM-EXEC-LEN

0 ASM-BASE !
0 ASM-DP !
0 ASM-LIMIT !
0 ASM-EXEC !
0 ASM-EXEC-LEN !

: ASM-FREE-EXEC  ( -- )
  ASM-EXEC @ IF
    ASM-EXEC @ ASM-EXEC-LEN @ FREE-EXEC DROP
    0 ASM-EXEC !  0 ASM-EXEC-LEN !
  THEN
  ;

: ASM-FREE-BUF  ( -- )
  ASM-BASE @ IF
    ASM-BASE @ FREE DROP
    0 ASM-BASE !  0 ASM-DP !  0 ASM-LIMIT !
  THEN
  ;

: ASM-ALLOC  ( u -- )
  ASM-FREE-EXEC  ASM-FREE-BUF
  DUP ALLOCATE IF
    DROP S" ASM-ALLOC failed" TCOM-ABORT
  THEN
  ASM-BASE !
  ASM-LIMIT !
  0 ASM-DP !
  ;

: ASM-ENSURE  ( -- )
  ASM-BASE @ 0= IF  ASM-DEFAULT-SIZE ASM-ALLOC  THEN
  ;

: ASM-CLEAR  ( -- )  ASM-ENSURE  0 ASM-DP ! ;
: ASM-ORG    ( off -- )
  ASM-ENSURE
  DUP ASM-LIMIT @ U> IF S" ASM-ORG past limit" TCOM-ABORT THEN
  ASM-DP !
  ;

: ASM-USED   ( -- u )  ASM-DP @ ;
: ASM-ENTRY  ( taddr -- addr )  ASM-BASE @ + ;

: HERE-T  ( -- taddr )  ASM-ENSURE  ASM-DP @ ;

: C!-T  ( char taddr -- )
  ASM-ENSURE
  DUP ASM-LIMIT @ U>= IF S" C!-T out of range" TCOM-ABORT THEN
  ASM-BASE @ + C!
  ;

: C@-T  ( taddr -- char )
  ASM-ENSURE
  DUP ASM-LIMIT @ U>= IF S" C@-T out of range" TCOM-ABORT THEN
  ASM-BASE @ + C@
  ;

: C,-T  ( char -- )
  ASM-ENSURE
  ASM-DP @ ASM-LIMIT @ U>= IF S" ASM buffer full" TCOM-ABORT THEN
  ASM-DP @ C!-T          \ ( char taddr -- )
  1 ASM-DP +!
  ;

[UNDEFINED] T-CELL [IF]  8 CONSTANT T-CELL  [THEN]

\ Little-endian cell append (CALL-ABS / JMP-ABS .quad)
: ,-T  ( x -- )
  T-CELL 0 DO
    DUP $FF AND C,-T
    8 RSHIFT
  LOOP DROP
  ;

\ Copy assembled image to RX pages for CALL-NATIVE.
\ ( -- exec-addr )  exec-addr = start of copy (offset 0)
: ASM-MAKE-EXEC  ( -- exec-addr )
  ASM-ENSURE
  ASM-FREE-EXEC
  ASM-DP @ 0= IF S" ASM-MAKE-EXEC: empty" TCOM-ABORT THEN
  ASM-DP @ ALLOCATE-EXEC IF
    DROP S" ASM-MAKE-EXEC: ALLOCATE-EXEC failed" TCOM-ABORT
  THEN
  ASM-EXEC !
  ASM-DP @ ASM-EXEC-LEN !
  ASM-BASE @ ASM-EXEC @ ASM-DP @ MOVE
  ASM-EXEC @ ASM-DP @ ASM-PROT-RX MPROTECT IF
    ASM-FREE-EXEC
    S" ASM-MAKE-EXEC: MPROTECT RX failed" TCOM-ABORT
  THEN
  ASM-EXEC @ ASM-DP @ ICACHE-INVAL
  ASM-EXEC @
  ;

\ Run leaf at taddr (offset). Uses CALL-NATIVE-LEAF (built-in DSP; X0=0 in).
: ASM-RUN-LEAF  ( taddr -- x0' )
  >R ASM-MAKE-EXEC DROP R>
  ASM-EXEC @ + CALL-NATIVE-LEAF
  ;
: ASM-RUN  ( taddr -- x0' )  ASM-RUN-LEAF ;
[THEN]

\ Marker must not be named ASMARM64 — that name is the VOCABULARY below.
\ (TCOM-ANEW ASMARM64 then VOCABULARY ASMARM64 left a broken wid; ALSO failed.)
TCOM-ANEW ASMARM64-MOD

FORTH DEFINITIONS
DECIMAL

\ Pack path: host flag lives after marker (reload-safe).
[DEFINED] ASMARM64-HOST? [IF]
[ELSE]
FALSE VALUE ASMARM64-HOST?
[THEN]

VOCABULARY ASMARM64
: [ASMARM64]  ( -- )  ASMARM64 ; IMMEDIATE

\ Lifecycle / temps stay in FORTH so SETASSEM/END-CODE always find them.
FALSE VALUE ?ASM-ACTIVE

VARIABLE A64-I
VARIABLE A64-D
VARIABLE A64-H
VARIABLE A64-N
VARIABLE A64-M
VARIABLE A64-T
VARIABLE A64-A
VARIABLE A64-R2

\ Emitters, registers, and structured asm go in ASMARM64 (not FORTH).
\ ALSO keeps ASMARM64 on the search order so later words can find earlier ones.
ALSO ASMARM64 DEFINITIONS

: (REG)  ( n -- n )  $1F AND ;

: W,  ( u32 -- )
  DUP $FF AND C,-T
  8 RSHIFT DUP $FF AND C,-T
  8 RSHIFT DUP $FF AND C,-T
  8 RSHIFT $FF AND C,-T
  ;

: ALIGN4-T  ( -- )
  BEGIN HERE-T 3 AND WHILE  0 C,-T  REPEAT
  ;

: PATCH-W  ( u32 taddr -- )
  OVER $FF AND OVER C!-T
  OVER 8 RSHIFT $FF AND OVER 1 + C!-T
  OVER 16 RSHIFT $FF AND OVER 2 + C!-T
  SWAP 24 RSHIFT $FF AND SWAP 3 + C!-T
  ;

: W@-T  ( taddr -- u32 )
  DUP C@-T
  OVER 1 + C@-T 8 LSHIFT OR
  OVER 2 + C@-T 16 LSHIFT OR
  SWAP 3 + C@-T 24 LSHIFT OR
  ;

\ ----- registers -----
0 CONSTANT X0   1 CONSTANT X1   2 CONSTANT X2   3 CONSTANT X3
4 CONSTANT X4   5 CONSTANT X5   6 CONSTANT X6   7 CONSTANT X7
8 CONSTANT X8   9 CONSTANT X9  10 CONSTANT X10 11 CONSTANT X11
12 CONSTANT X12 13 CONSTANT X13 14 CONSTANT X14 15 CONSTANT X15
16 CONSTANT X16 17 CONSTANT X17 18 CONSTANT X18 19 CONSTANT X19
20 CONSTANT X20 21 CONSTANT X21 22 CONSTANT X22 23 CONSTANT X23
24 CONSTANT X24 25 CONSTANT X25 26 CONSTANT X26 27 CONSTANT X27
28 CONSTANT X28 29 CONSTANT X29 30 CONSTANT X30
31 CONSTANT XZR
31 CONSTANT SP

\ ----- basic -----
: NOP,   ( -- )  $D503201F W, ;
\ BTI landing pad (HINT). Required on some Apple exec pages for BL/BR targets;
\ executes as NOP if BTI is not enforced.
\ Optional landing pad; default NOP so native BLR/BL is not required for demos.
\ BTI C landing pad (HINT #32). Acts as NOP if BTI not enforced.
: BTI,   ( -- )  $D503245F W, ;
: BTI-C, ( -- )  $D503245F W, ;
: BTI-J, ( -- )  $D503249F W, ;
: BTI-JC, ( -- ) $D50324DF W, ;
: RET,   ( -- )  $D65F03C0 W, ;
: RET-X, ( xn -- )  (REG) 5 LSHIFT $D65F0000 OR W, ;
: BLR-X, ( xn -- )  (REG) 5 LSHIFT $D63F0000 OR W, ;
: BR-X,  ( xn -- )  (REG) 5 LSHIFT $D61F0000 OR W, ;

\ SVC #imm16  — encoding 0xD4000001 | (imm16 << 5)
\ Darwin/macOS user SVC uses #0x80 with X16 = BSD syscall number.
: SVC,  ( imm16 -- )
  $FFFF AND 5 LSHIFT $D4000001 OR W,
  ;

\ ----- move / logic / arith -----
: MOVZ-X,  ( imm16 xd hw -- )
  A64-H ! A64-D ! A64-I !
  A64-H @ 3 U> IF S" MOVZ hw 0..3" TCOM-ABORT THEN
  $D2800000 A64-H @ 21 LSHIFT OR
  A64-I @ $FFFF AND 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

: MOVK-X,  ( imm16 xd hw -- )
  A64-H ! A64-D ! A64-I !
  A64-H @ 3 U> IF S" MOVK hw 0..3" TCOM-ABORT THEN
  $F2800000 A64-H @ 21 LSHIFT OR
  A64-I @ $FFFF AND 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

: MOV-X-IMM64,  ( imm64 xd -- )
  (REG) A64-D !
  DUP $FFFF AND            A64-D @ 0 MOVZ-X,
  DUP 16 RSHIFT $FFFF AND  A64-D @ 1 MOVK-X,
  DUP 32 RSHIFT $FFFF AND  A64-D @ 2 MOVK-X,
      48 RSHIFT $FFFF AND  A64-D @ 3 MOVK-X,
  ;

: MOV-X-X,  ( xm xd -- )
  A64-D ! A64-M !
  $AA0003E0 A64-M @ (REG) 16 LSHIFT OR A64-D @ (REG) OR W,
  ;

: ORR-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $AA000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: AND-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $8A000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: EOR-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $CA000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: ADD-X-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $8B000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: SUB-X-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $CB000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: ADDS-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $AB000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: ADC-X,  ( xm xn xd -- )              \ Xd = Xn + Xm + C
  A64-D ! A64-N ! A64-M !
  $9A000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: SBC-X,  ( xm xn xd -- )              \ Xd = Xn - Xm - ~C
  A64-D ! A64-N ! A64-M !
  $DA000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: SUBS-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $EB000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: CMP-X,  ( xm xn -- )  XZR SUBS-X, ;

\ 0= on TOS (X0): MOV X1,X0; CMP X1,XZR; CSET X0,EQ
$EB1F003F CONSTANT (A64-CMP-X1-XZR)   \ CMP X1, XZR
$9A9F17E0 CONSTANT (A64-CSET-X0-EQ)   \ CSET X0, EQ

\ CSET Xd, cond  = CSINC Xd,XZR,XZR, invert(cond)
\ CSINC encoding needs bits[11:10]=01 (not CSEL's 00).
: CSET-X,  ( cond xd -- )
  A64-D !
  1 XOR $F AND 12 LSHIFT
  $9A9F07E0 OR
  A64-D @ (REG) OR W,
  ;

: T0=,  ( -- )
  X0 X1 MOV-X-X,
  (A64-CMP-X1-XZR) W,
  (A64-CSET-X0-EQ) W,
  X0 XZR X0 SUB-X-X,             \ Forth flag: 0 or -1 (not C 0/1)
  ;

: ADD-IMM,  ( imm12 xn xd -- )
  A64-D ! A64-N ! A64-I !
  $91000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: SUB-IMM,  ( imm12 xn xd -- )
  A64-D ! A64-N ! A64-I !
  $D1000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ 64-bit LSR Xd,Xn,#uimm (UBFM alias)
: LSR-IMM,  ( uimm xn xd -- )
  A64-D ! A64-N ! A64-I !
  A64-I @ 0= IF  A64-N @ A64-D @ MOV-X-X, EXIT  THEN
  A64-I @ 63 U> IF S" LSR-IMM 0..63" TCOM-ABORT THEN
  $D3400000
  A64-I @ $3F AND 16 LSHIFT OR        \ immr = shift
  63 10 LSHIFT OR                     \ imms = 63
  A64-N @ (REG) 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

\ LSL/LSR Xd, Xn, Xm  (shift count in Xm, bits 5:0)
: LSL-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $9AC02000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: LSR-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $9AC02400 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ 64-bit LSL Xd,Xn,#uimm (UBFM alias)
: LSL-IMM,  ( uimm xn xd -- )
  A64-D ! A64-N ! A64-I !
  A64-I @ 0= IF  A64-N @ A64-D @ MOV-X-X, EXIT  THEN
  A64-I @ 63 U> IF S" LSL-IMM 0..63" TCOM-ABORT THEN
  $D3400000
  64 A64-I @ - $3F AND 16 LSHIFT OR   \ immr
  63 A64-I @ - $3F AND 10 LSHIFT OR   \ imms
  A64-N @ (REG) 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

\ ASR Xd,Xn,#uimm (SBFM alias)
: ASR-IMM,  ( uimm xn xd -- )
  A64-D ! A64-N ! A64-I !
  A64-I @ 63 U> IF S" ASR-IMM 0..63" TCOM-ABORT THEN
  $93400000
  A64-I @ $3F AND 16 LSHIFT OR
  63 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

: ASR-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $9AC02800 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ UBFM Xd,Xn,immr,imms  (64-bit)
: UBFM-X,  ( immr imms xn xd -- )
  A64-D ! A64-N ! A64-I ! A64-H !
  $D3400000
  A64-H @ $3F AND 16 LSHIFT OR
  A64-I @ $3F AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

\ SBFM Xd,Xn,immr,imms  (64-bit)
: SBFM-X,  ( immr imms xn xd -- )
  A64-D ! A64-N ! A64-I ! A64-H !
  $93400000
  A64-H @ $3F AND 16 LSHIFT OR
  A64-I @ $3F AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

\ LDRB Xt,[Xn]  (zero-extend byte)
: LDRB-X,  ( xt xn -- )
  A64-N ! A64-D !
  $39400000 A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ STRB Xt,[Xn]
: STRB-X,  ( xt xn -- )
  A64-N ! A64-D !
  $39000000 A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ MUL Xd, Xn, Xm  — 64-bit multiply (alias MADD Xd,Xn,Xm,XZR)
: MUL-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $9B007C00 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ UDIV Xd, Xn, Xm  — unsigned divide
: UDIV-X,  ( xm xn xd -- )
  A64-D ! A64-N ! A64-M !
  $9AC00800 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ MSUB Xd, Xn, Xm, Xa  — Xd = Xa - Xn*Xm
: MSUB-X,  ( xm xa xn xd -- )
  A64-D ! A64-N ! A64-A ! A64-M !
  $9B008000 A64-M @ (REG) 16 LSHIFT OR
  A64-A @ (REG) 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ ADR Xd, #0 — Xd := address of this instruction (relocatable base recovery)
: ADR-X0,  ( xd -- )
  (REG) $10000000 OR W,
  ;

\ Emit: X16 := image base (runtime). Uses X17. PC-relative ADR - taddr.
\ base = ADR_result - taddr_of_ADR
: (BASE-X16,)  ( -- )
  ALIGN4-T
  HERE-T A64-T !                 \ taddr of ADR
  X16 ADR-X0,
  A64-T @ X17 MOV-X-IMM64,
  X17 X16 X16 SUB-X-X,           \ X16 = X16 - X17
  ;

\ X0 = dest taddr → BR to base+X0 (relocatable BRANCH helper)
: (TADDR-BR,)  ( -- )
  (BASE-X16,)
  X0 X16 X16 ADD-X-X,
  X16 BR-X,
  ;

\ ----- load/store -----
: (IMM9)  ( n -- u )  DUP 0< IF $200 + THEN $1FF AND ;

: STR-PRE,  ( xt xn simm -- )
  (IMM9) A64-I ! A64-N ! A64-D !
  $F8000C00 A64-I @ 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: LDR-POST,  ( xt xn simm -- )
  (IMM9) A64-I ! A64-N ! A64-D !
  $F8400400 A64-I @ 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: LDR-X0,  ( xt xn -- )
  A64-N ! A64-D !
  $F9400000 A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: STR-X0,  ( xt xn -- )
  A64-N ! A64-D !
  $F9000000 A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: LDR-OFF,  ( xt xn imm-bytes -- )
  DUP 7 AND IF S" LDR-OFF needs 8-aligned offset" TCOM-ABORT THEN
  3 RSHIFT A64-I ! A64-N ! A64-D !
  $F9400000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: STR-OFF,  ( xt xn imm-bytes -- )
  DUP 7 AND IF S" STR-OFF needs 8-aligned offset" TCOM-ABORT THEN
  3 RSHIFT A64-I ! A64-N ! A64-D !
  $F9000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: LDR64-PC+8,   ( xn -- )  (REG) $58000000 OR 2 5 LSHIFT OR W, ;
: LDR64-PC+12,  ( xn -- )  (REG) $58000000 OR 3 5 LSHIFT OR W, ;

: LDR64-LIT,  ( xn imm19 -- )
  A64-I ! A64-D !
  $58000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ General LDR/STR pre/post (64-bit); simm byte offset -256..255
: LDR-PRE,  ( xt xn simm -- )
  (IMM9) A64-I ! A64-N ! A64-D !
  $F8400C00 A64-I @ 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: STR-POST,  ( xt xn simm -- )
  (IMM9) A64-I ! A64-N ! A64-D !
  $F8000400 A64-I @ 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ LDR/STR Xt,[Xn,Xm]  (64-bit, UXTX #0 / no extend shift)
: LDR-REG,  ( xt xn xm -- )
  A64-M ! A64-N ! A64-D !
  $F8606800 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: STR-REG,  ( xt xn xm -- )
  A64-M ! A64-N ! A64-D !
  $F8206800 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ ----- LDP / STP (64-bit pairs; imm in bytes, multiple of 8, -512..504) -----
: (IMM7-PAIR)  ( n -- u )
  DUP 7 AND IF S" LDP/STP offset must be 8-aligned" TCOM-ABORT THEN
  8 /                            \ signed scale (avoid logical RSHIFT on negatives)
  DUP -64 < OVER 63 > OR IF S" LDP/STP imm7 range" TCOM-ABORT THEN
  DUP 0< IF $80 + THEN $7F AND
  ;

: STP-OFF,  ( xt1 xt2 xn imm-bytes -- )
  (IMM7-PAIR) A64-I ! A64-N ! A64-R2 ! A64-D !
  $A9000000 A64-I @ 15 LSHIFT OR
  A64-R2 @ (REG) 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: LDP-OFF,  ( xt1 xt2 xn imm-bytes -- )
  (IMM7-PAIR) A64-I ! A64-N ! A64-R2 ! A64-D !
  $A9400000 A64-I @ 15 LSHIFT OR
  A64-R2 @ (REG) 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: STP-PRE,  ( xt1 xt2 xn imm-bytes -- )
  (IMM7-PAIR) A64-I ! A64-N ! A64-R2 ! A64-D !
  $A9800000 A64-I @ 15 LSHIFT OR
  A64-R2 @ (REG) 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: LDP-POST,  ( xt1 xt2 xn imm-bytes -- )
  (IMM7-PAIR) A64-I ! A64-N ! A64-R2 ! A64-D !
  $A8C00000 A64-I @ 15 LSHIFT OR
  A64-R2 @ (REG) 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ ----- ADR / ADRP (imm = byte displacement from this insn) -----
: (ADR-IMM)  ( imm -- immlo immhi )
  $1FFFFF AND                    \ 21-bit signed field
  DUP $3 AND SWAP 2 RSHIFT $7FFFF AND
  ;

: ADR,  ( imm xd -- )
  A64-D ! (ADR-IMM) A64-I ! A64-H !
  $10000000
  A64-H @ 29 LSHIFT OR
  A64-I @ 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

: ADRP,  ( imm-pages xd -- )   \ imm = page count (target_page - pc_page)
  A64-D ! (ADR-IMM) A64-I ! A64-H !
  $90000000
  A64-H @ 29 LSHIFT OR
  A64-I @ 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;

\ ----- CSEL / CSINC -----
: CSEL-X,  ( xm xn cond xd -- )   \ Xd = cond ? Xn : Xm
  A64-D ! A64-I ! A64-N ! A64-M !
  $9A800000 A64-M @ (REG) 16 LSHIFT OR
  A64-I @ $F AND 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: CSINC-X,  ( xm xn cond xd -- )  \ Xd = cond ? Xn : Xm+1
  A64-D ! A64-I ! A64-N ! A64-M !
  $9A800400 A64-M @ (REG) 16 LSHIFT OR
  A64-I @ $F AND 12 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ ----- W-register suite (32-bit sf=0) -----
0 CONSTANT W0   1 CONSTANT W1   2 CONSTANT W2   3 CONSTANT W3
4 CONSTANT W4   5 CONSTANT W5   6 CONSTANT W6   7 CONSTANT W7
8 CONSTANT W8   9 CONSTANT W9  10 CONSTANT W10 11 CONSTANT W11
12 CONSTANT W12 13 CONSTANT W13 14 CONSTANT W14 15 CONSTANT W15
16 CONSTANT W16 17 CONSTANT W17 18 CONSTANT W18 19 CONSTANT W19
20 CONSTANT W20 21 CONSTANT W21 22 CONSTANT W22 23 CONSTANT W23
24 CONSTANT W24 25 CONSTANT W25 26 CONSTANT W26 27 CONSTANT W27
28 CONSTANT W28 29 CONSTANT W29 30 CONSTANT W30
31 CONSTANT WZR

: MOVZ-W,  ( imm16 wd hw -- )
  A64-H ! A64-D ! A64-I !
  A64-H @ 1 U> IF S" MOVZ-W hw 0..1" TCOM-ABORT THEN
  $52800000 A64-H @ 21 LSHIFT OR
  A64-I @ $FFFF AND 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;
: MOVK-W,  ( imm16 wd hw -- )
  A64-H ! A64-D ! A64-I !
  A64-H @ 1 U> IF S" MOVK-W hw 0..1" TCOM-ABORT THEN
  $72800000 A64-H @ 21 LSHIFT OR
  A64-I @ $FFFF AND 5 LSHIFT OR
  A64-D @ (REG) OR W,
  ;
: MOV-W-IMM32,  ( imm32 wd -- )
  A64-D !
  DUP $FFFF AND            A64-D @ 0 MOVZ-W,
       16 RSHIFT $FFFF AND A64-D @ 1 MOVK-W,
  ;
: MOV-W-W,  ( wm wd -- )
  A64-D ! A64-M !
  $2A0003E0 A64-M @ (REG) 16 LSHIFT OR A64-D @ (REG) OR W,
  ;
: ORR-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $2A000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: AND-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $0A000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: EOR-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $4A000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: ADD-W-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $0B000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: SUB-W-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $4B000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: ADDS-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $2B000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: SUBS-W,  ( wm wn wd -- )
  A64-D ! A64-N ! A64-M !
  $6B000000 A64-M @ (REG) 16 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: CMP-W,  ( wm wn -- )  WZR SUBS-W, ;
: ADD-W-IMM,  ( imm12 wn wd -- )
  A64-D ! A64-N ! A64-I !
  $11000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: SUB-W-IMM,  ( imm12 wn wd -- )
  A64-D ! A64-N ! A64-I !
  $51000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: LDR-W-OFF,  ( wt xn imm-bytes -- )
  DUP 3 AND IF S" LDR-W-OFF needs 4-aligned offset" TCOM-ABORT THEN
  2 RSHIFT A64-I ! A64-N ! A64-D !
  $B9400000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: STR-W-OFF,  ( wt xn imm-bytes -- )
  DUP 3 AND IF S" STR-W-OFF needs 4-aligned offset" TCOM-ABORT THEN
  2 RSHIFT A64-I ! A64-N ! A64-D !
  $B9000000 A64-I @ $FFF AND 10 LSHIFT OR
  A64-N @ (REG) 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: CBZ-W,  ( wt imm19 -- )
  A64-I ! A64-D !
  $34000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ (REG) OR W,
  ;
: CBNZ-W,  ( wt imm19 -- )
  A64-I ! A64-D !
  $35000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ ----- branches -----
: B-IMM,   ( imm26 -- )  $3FFFFFF AND $14000000 OR W, ;
: BL-IMM,  ( imm26 -- )  $3FFFFFF AND $94000000 OR W, ;

0 CONSTANT EQ  1 CONSTANT NE
2 CONSTANT CS  2 CONSTANT HS
3 CONSTANT CC  3 CONSTANT LO
4 CONSTANT MI  5 CONSTANT PL
6 CONSTANT VS  7 CONSTANT VC
8 CONSTANT HI  9 CONSTANT LS
10 CONSTANT GE 11 CONSTANT LT
12 CONSTANT GT 13 CONSTANT LE
14 CONSTANT AL

: B.COND,  ( imm19 cond -- )
  A64-D ! A64-I !
  $54000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ $F AND OR W,
  ;

: CBNZ-X,  ( xt imm19 -- )
  A64-I ! A64-D !
  $B5000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

: CBZ-X,  ( xt imm19 -- )
  A64-I ! A64-D !
  $B4000000 A64-I @ $7FFFF AND 5 LSHIFT OR A64-D @ (REG) OR W,
  ;

\ In-image call (Phase 3.5 — preserves LR so colon RET works after BLR):
\   STP X30,XZR,[SP,#-16]!
\   LDR X16,[PC+16]     ; .quad at +20 from LDR (= +16 from this LDR)
\   BLR X16
\   LDP X30,XZR,[SP],#16
\   B +3                ; skip 8-byte .quad (from B: +1=quad, +2=mid, +3=after)
\   .quad taddr         ; TARGET OFFSET (not host). Native/Mach-O fixup adds base.
\
\ Why STP/LDP: bare BLR overwrites X30; a following RET then jumps to the
\ instruction after BLR forever (SIM OK because it uses a separate R-stack).
\ Why B+3 not B+2: imm is in instructions from B itself; .quad is 2 words,
\ so landing after it is +3 from B (B+2 lands mid-quad → SIGILL).
\ Chain cell for SYM-COMPILE-REF is the .quad (HERE-T T-CELL -).

$A9BF7FFE CONSTANT (A64-STP-X30-XZR-SP)   \ STP X30, XZR, [SP, #-16]!
$A8C17FFE CONSTANT (A64-LDP-X30-XZR-SP)   \ LDP X30, XZR, [SP], #16

: CALL-ABS,  ( taddr -- )
  ALIGN4-T
  \ .quad at HERE+20 must be 8-aligned → HERE ≡ 4 (mod 8)
  HERE-T 7 AND 0= IF  NOP,  THEN
  (A64-STP-X30-XZR-SP) W,
  X16 4 LDR64-LIT,                 \ imm19=4 → PC+16 → .quad
  X16 BLR-X,
  (A64-LDP-X30-XZR-SP) W,
  3 B-IMM,                         \ skip .quad (must be +3, not +2)
  ,-T                              \ taddr offset (NOT THERE host addr)
  ;

: JMP-ABS,  ( taddr -- )
  ALIGN4-T
  HERE-T 7 AND 0= IF  NOP,  THEN
  X16 LDR64-PC+12,
  X16 BR-X,
  3 B-IMM,
  ,-T                                 \ taddr offset
  ;

\ ----- patch helpers -----
\ imm = (dest - taddr) / 4.  With ( dest taddr ) on stack, 2DUP - gives dest-taddr.

: PATCH-B  ( dest taddr -- )
  2DUP - 4 /
  $3FFFFFF AND $14000000 OR
  SWAP PATCH-W
  DROP
  ;

: PATCH-BCOND  ( dest taddr -- )
  DUP W@-T $F AND A64-D !
  2DUP - 4 /
  $7FFFF AND 5 LSHIFT $54000000 OR A64-D @ OR
  SWAP PATCH-W
  DROP
  ;

\ Patch CBZ/CBNZ at taddr to branch to dest (keeps Rt + B4/B5 opcode)
: PATCH-CBZ  ( dest taddr -- )
  DUP W@-T $1F AND A64-D !                 \ Rt
  DUP W@-T $FF000000 AND A64-I !           \ $B4000000 or $B5000000
  2DUP - 4 /
  $7FFFF AND 5 LSHIFT A64-I @ OR A64-D @ OR
  SWAP PATCH-W
  DROP
  ;

\ ----- structured control (asm) -----
\ Named AHEAD, (with comma) so it does not clash with Forth tools AHEAD (immediate).
: AHEAD,  ( -- orig )
  ALIGN4-T  HERE-T  0 B-IMM,
  ;

: THEN,  ( orig -- )
  HERE-T SWAP PATCH-B
  ;

: AGAIN,  ( dest -- )
  ALIGN4-T
  HERE-T - 4 / B-IMM,
  ;

\ AIF, : branch if condition FALSE to skip (user supplies skip cond)
\ e.g. after CMP, AIF, NE  means skip when not equal
: AIF,  ( cond -- orig )
  ALIGN4-T  HERE-T SWAP  0 SWAP B.COND,
  ;

: ATHEN,  ( orig -- )
  HERE-T SWAP PATCH-BCOND
  ;

: AELSE,  ( orig1 -- orig2 )
  AHEAD, SWAP ATHEN,
  ;

\ ----- Forth-ABI control (TOS = flag in X0) — for T: … ;T graphs -----
\ TIF/TELSE/TTHEN use a private control stack so host DATA stack pollution
\ (common during TSRC-INCLUDE) cannot bury branch origins → B #0 hangs.

32 CONSTANT #TCS
CREATE TCS  #TCS CELLS ALLOT
VARIABLE TCSP
16 CONSTANT #TLEAVE
CREATE TLEAVE-SITE  #TLEAVE CELLS ALLOT
8 CONSTANT #TLEAVE-NEST
CREATE TLEAVE-MARK  #TLEAVE-NEST CELLS ALLOT
VARIABLE TLEAVE-N
VARIABLE TLEAVE-SP
0 TLEAVE-N !
0 TLEAVE-SP !

: TLEAVE-RESET  ( -- )  0 TLEAVE-N !  0 TLEAVE-SP ! ;

: TCS-CLEAR  ( -- )  0 TCSP !  TLEAVE-RESET ;
: TCS-PUSH  ( x -- )
  TCSP @ #TCS U>= IF S" TIF control stack overflow" TCOM-ABORT THEN
  TCSP @ CELLS TCS + !  1 TCSP +!
  ;
: TCS-POP  ( -- x )
  TCSP @ 0= IF S" TIF control stack underflow" TCOM-ABORT THEN
  -1 TCSP +!  TCSP @ CELLS TCS + @
  ;

TCS-CLEAR

: TIF  ( -- )
  \ MOV-X-X, is (xm xd): X0 X1 = MOV X1,X0 (flag TOS → X1)
  X0 X1 MOV-X-X,
  X0 X19 8 LDR-POST,             \ drop flag; new TOS
  ALIGN4-T
  HERE-T TCS-PUSH                \ CBZ site
  X1 0 CBZ-X,                    \ if flag==0 skip true part (imm patched later)
  ;

\ Resolve TIF's CBZ or TELSE's B (auto-detect opcode)
: TTHEN  ( -- )
  TCS-POP
  DUP W@-T 24 RSHIFT $FF AND $14 = IF
    HERE-T SWAP PATCH-B
  ELSE
    HERE-T SWAP PATCH-CBZ
  THEN
  ;

: TELSE  ( -- )
  ALIGN4-T HERE-T 0 B-IMM,       \ branch around else-part
  TCS-POP                        \ if-orig (CBZ)
  HERE-T SWAP PATCH-CBZ          \ IF's CBZ → start of else
  TCS-PUSH                       \ ahead-orig for TTHEN
  ;

\ BEGIN / UNTIL / AGAIN / WHILE / REPEAT — nestable via TLOOP-STACK
8 CONSTANT #TLOOP
CREATE TLOOP-STACK  #TLOOP CELLS ALLOT
VARIABLE TLOOP-SP
0 TLOOP-SP !
VARIABLE TLOOP-DEST                     \ mirror of current top (compat)

: TLOOP-PUSH  ( addr -- )
  TLOOP-SP @ #TLOOP >= IF
    DROP S" ASMARM64: BEGIN nest too deep" TYPE CR TCOM-ABORT
  THEN
  DUP TLOOP-DEST !
  TLOOP-STACK TLOOP-SP @ CELLS + !
  1 TLOOP-SP +!
  ;

: TLOOP-POP  ( -- addr )
  TLOOP-SP @ 0= IF
    S" ASMARM64: UNTIL/AGAIN/REPEAT without BEGIN" TYPE CR TCOM-ABORT
  THEN
  -1 TLOOP-SP +!
  TLOOP-STACK TLOOP-SP @ CELLS + @
  TLOOP-SP @ IF
    TLOOP-STACK TLOOP-SP @ 1- CELLS + @ TLOOP-DEST !
  ELSE
    0 TLOOP-DEST !
  THEN
  ;

: TBEGIN  ( -- )
  ALIGN4-T HERE-T TLOOP-PUSH
  ;

: TUNTIL  ( -- )
  \ flag TOS → X1; restore under to X0; CBZ X1,dest
  X0 X1 MOV-X-X,
  X0 X19 8 LDR-POST,
  ALIGN4-T
  TLOOP-POP HERE-T - 4 /           \ imm19 = (dest - HERE) / 4
  X1 SWAP CBZ-X,
  ;

: TAGAIN  ( -- )
  ALIGN4-T
  TLOOP-POP HERE-T - 4 / B-IMM,
  ;

\ TWHILE: if flag==0 skip to after TREPEAT; else continue (flag dropped)
\ CBZ origin on TCS (not host data stack) — same hygiene as TIF/TELSE.
\ TREPEAT: B back to BEGIN; patch WHILE's CBZ to fall-through after REPEAT
: TWHILE  ( -- )
  X0 X1 MOV-X-X,
  X0 X19 8 LDR-POST,
  ALIGN4-T
  HERE-T TCS-PUSH                    \ CBZ site
  X1 0 CBZ-X,
  ;

: TREPEAT  ( -- )
  ALIGN4-T
  TLOOP-POP HERE-T - 4 / B-IMM,      \ back to matching BEGIN
  TCS-POP HERE-T SWAP PATCH-CBZ      \ false WHILE → here
  ;

\ Count in X0 from 0 until X0==3. Result X0=3.
\   n=0
\ L: n += 1
\    if (n - 3) != 0 goto L
\ Machine (after 4-insn MOV#0):
\   91000400  ADD X0,X0,#1
\   AA0003E1  MOV X1,X0
\   D1000C21  SUB X1,X1,#3
\   B5FFFFA1  CBNZ X1,#-3     (imm19 = -3 → back to ADD)
\ No patch. No stack effects left for caller.
: TLOOP-TO-3,  ( -- )
  0 X0 MOV-X-IMM64,
  ALIGN4-T HERE-T TLOOP-DEST !
  1 X0 X0 ADD-IMM,                 \ n++
  X0 X1 MOV-X-X,                   \ X1 = n
  3 X1 X1 SUB-IMM,                 \ X1 = n - 3
  ALIGN4-T
  TLOOP-DEST @ HERE-T - 4 /        \ imm19 = (head - cbnz) / 4  (= -3)
  X1 SWAP CBNZ-X,
  ;

\ ----- local labels 0..15 -----
16 CONSTANT #LLAB
CREATE LL-POS  #LLAB CELLS ALLOT
CREATE LL-FWD  #LLAB CELLS ALLOT

: LL-INIT  ( -- )
  0 BEGIN DUP #LLAB < WHILE
    -1 OVER CELLS LL-POS + !
    -1 OVER CELLS LL-FWD + !
    1+
  REPEAT DROP
  ;

\ Note: cannot be named L: — that is 64DIR library define. Use LL: / BR>LL.
: LL:  ( n -- )   \ define local label n at HERE-T
  DUP #LLAB U>= IF S" label 0..15" TCOM-ABORT THEN
  A64-T !
  HERE-T A64-T @ CELLS LL-POS + !
  A64-T @ CELLS LL-FWD + @
  DUP -1 <> IF
    HERE-T SWAP PATCH-B
    -1 A64-T @ CELLS LL-FWD + !
  ELSE DROP THEN
  ;

: BR>LL  ( n -- )  \ B to local label n (back or one forward site)
  DUP #LLAB U>= IF S" label 0..15" TCOM-ABORT THEN
  A64-T !
  ALIGN4-T
  A64-T @ CELLS LL-POS + @
  DUP -1 = IF
    DROP
    HERE-T  0 B-IMM,
    A64-T @ CELLS LL-FWD + !
  ELSE
    HERE-T - 4 / B-IMM,
  THEN
  ;

\ ----- Forth ABI helpers -----
: LIT-PUSH-X0,  ( n -- )
  X0 X19 -8 STR-PRE,
  X0 MOV-X-IMM64,
  ;

: LIT-X0,  ( n -- )  X0 MOV-X-IMM64, ;

4096 CONSTANT #RSTACK                     \ Forth RP bytes below DSP

: DSP-INIT,  ( host-dsp-top -- )
  \ X19 = DSP; X20 = RP (same gap as SIM #SIM-RSTACK)
  DUP X19 MOV-X-IMM64,
  #RSTACK - X20 MOV-X-IMM64,
  0 X0 MOV-X-IMM64,
  ;

\ ----- DO / LOOP / +LOOP / I / J (RP = X20; bias = 1<<63) -----
$444F0001 CONSTANT DO-SYS                 \ TCS marker

: TDO-NEST  ( -- )
  TLEAVE-SP @ #TLEAVE-NEST U>= IF
    S" DO nest too deep" TCOM-ABORT
  THEN
  TLEAVE-N @ TLEAVE-SP @ CELLS TLEAVE-MARK + !
  1 TLEAVE-SP +!
  ;

: TDO-FRAME  ( -- )
  X0 X1 MOV-X-X,                         \ X1 = index
  X2 X19 8 LDR-POST,                     \ X2 = limit; drop
  X0 X19 8 LDR-POST,                     \ new TOS
  $8000000000000000 X3 MOV-X-IMM64,      \ bias
  X3 X2 X2 ADD-X-X,                      \ limit'
  X2 X1 X1 SUB-X-X,                      \ index' = index - limit'
  X2 X20 -8 STR-PRE,                     \ push limit'
  X1 X20 -8 STR-PRE,                     \ push index'
  ALIGN4-T HERE-T TCS-PUSH               \ loop head
  DO-SYS TCS-PUSH
  ;

: TDO  ( -- )
  TDO-NEST
  TDO-FRAME
  ;

VARIABLE TQDO-NE

: (TLEAVE-B)  ( -- )
  TLEAVE-N @ #TLEAVE U>= IF S" too many LEAVE" TCOM-ABORT THEN
  ALIGN4-T HERE-T
  0 B-IMM,
  TLEAVE-N @ CELLS TLEAVE-SITE + !
  1 TLEAVE-N +!
  ;

: TQDO  ( -- )
  \ ?DO: if limit==index drop both and skip to after LOOP (no RP frame)
  TDO-NEST
  X1 X19 LDR-X0,                         \ X1=limit
  X0 X1 X2 SUB-X-X,                      \ X2 = limit - index
  ALIGN4-T HERE-T TQDO-NE !              \ CBZ site
  X2 0 CBZ-X,
  ALIGN4-T HERE-T  0 B-IMM,              \ B to TDO-FRAME
  >R
  HERE-T TQDO-NE @ PATCH-CBZ             \ equal → drop/skip
  X0 X19 8 LDR-POST,
  X0 X19 8 LDR-POST,
  TLEAVE-SP @ 0= IF S" ?DO without nest" TCOM-ABORT THEN
  (TLEAVE-B)
  R> HERE-T SWAP PATCH-B                 \ not equal → frame
  TDO-FRAME
  ;

: TLEAVE-PATCH  ( -- )
  TLEAVE-SP @ 0= IF  EXIT  THEN
  -1 TLEAVE-SP +!
  TLEAVE-SP @ CELLS TLEAVE-MARK + @
  BEGIN  DUP TLEAVE-N @ < WHILE
    HERE-T OVER CELLS TLEAVE-SITE + @ PATCH-B
    1+
  REPEAT
  TLEAVE-N !
  ;

: TLEAVE  ( -- )
  TLEAVE-SP @ 0= IF S" LEAVE without DO" TCOM-ABORT THEN
  16 X20 X20 ADD-IMM,                    \ UNLOOP
  (TLEAVE-B)
  ;

: TLOOP  ( -- )
  TCS-POP DO-SYS <> IF S" LOOP without DO" TCOM-ABORT THEN
  TCS-POP >R                             \ dest
  X1 X20 0 LDR-OFF,                      \ index'  (LDR Xt,[Xn,#0])
  1 X2 MOV-X-IMM64,
  X2 X1 X1 ADDS-X,                       \ index' += 1
  X1 X20 0 STR-OFF,
  ALIGN4-T
  R@ HERE-T - 4 / VC B.COND,             \ continue if no overflow
  16 X20 X20 ADD-IMM,                    \ UNLOOP
  TLEAVE-PATCH
  R> DROP
  ;

: T+LOOP  ( -- )
  TCS-POP DO-SYS <> IF S" +LOOP without DO" TCOM-ABORT THEN
  TCS-POP >R
  X0 X1 MOV-X-X,                         \ n
  X0 X19 8 LDR-POST,                     \ drop n
  X2 X20 0 LDR-OFF,                      \ index'
  X1 X2 X2 ADDS-X,                       \ index' += n
  X2 X20 0 STR-OFF,
  ALIGN4-T
  R@ HERE-T - 4 / VC B.COND,
  16 X20 X20 ADD-IMM,
  TLEAVE-PATCH
  R> DROP
  ;

: TI,  ( -- )
  X0 X19 -8 STR-PRE,
  X1 X20 0 LDR-OFF,                      \ index'
  X2 X20 8 LDR-OFF,                      \ limit'
  X2 X1 X0 ADD-X-X,                      \ I
  ;

: TJ,  ( -- )
  X0 X19 -8 STR-PRE,
  X1 X20 16 LDR-OFF,                     \ outer index'
  X2 X20 24 LDR-OFF,                     \ outer limit'
  X2 X1 X0 ADD-X-X,
  ;

\ Zero local-label tables now (LL-INIT lives in ASMARM64; search order has it).
LL-INIT

\ Host-facing words and SETASSEM hooks live in FORTH.
ONLY FORTH DEFINITIONS
ALSO ASMARM64

\ Kernel ships an empty ASSEMBLER vocabulary. Make ASSEMBLER select ASMARM64
\ so ASSEMBLER WORDS / ASSEMBLER DEFINITIONS see the toolkit.
: ASSEMBLER  ( -- )  ASMARM64 ;

\ Host smoke / regression suite lives in Assembler/ASMARMTESTS.fth
\   FROMLIB FLOAD Assembler/ASMARMTESTS.fth  →  ASM-TESTS

: (SETASSEM)  ( -- )
  TRUE TO ?ASM-ACTIVE
  ALSO ASMARM64 DEFINITIONS
  LL-INIT
  ;
' (SETASSEM) IS SETASSEM

: (A;)  ( -- )  ;
' (A;) IS A;

: (END-CODE)  ( -- )
  ?ASM-ACTIVE IF PREVIOUS FORTH DEFINITIONS FALSE TO ?ASM-ACTIVE THEN
  ;
' (END-CODE) IS END-CODE

: C;  ( -- )  END-CODE ; IMMEDIATE

: .ASMARM64  ( -- )
  S" ASMARM64 3.2 toolkit: dual-load TCOM + 64Forth host buffer" TYPE CR
  S"   X/W regs  shifts/bitfield  ADR/ADRP  LDP/STP  CSEL  BTI" TYPE CR
  S"   LL: BR>LL  AHEAD,/AIF,  CALL-ABS  Forth-ABI TIF… TDO…" TYPE CR
  S"   Vocab: ASMARM64 (ASSEMBLER selects it).  SETASSEM … END-CODE" TYPE CR
  ASMARM64-HOST? IF
    S"   host: ASM-CLEAR ASM-RUN-LEAF ASMARM64-DISCARD; tests: ASMARMTESTS.fth" TYPE CR
  THEN
  ;

\ Pack stub (host path already defined ASMARM64-DISCARD before the overlay).
[DEFINED] ASMARM64-DISCARD [IF]
[ELSE]
: ASMARM64-DISCARD  ( -- )
  S" ASMARM64-DISCARD: pack load — reload TARGETARM64 or restart" TYPE CR
  ;
[THEN]

[DEFINED] ASM-ENSURE [IF]
ASM-ENSURE
S" ASMARM64 loaded (3.2 host toolkit).  ASMARM64 WORDS  or  ASSEMBLER WORDS" TYPE CR
[ELSE]
S" ASMARM64 loaded (3.2 pack assembler)." TYPE CR
[THEN]

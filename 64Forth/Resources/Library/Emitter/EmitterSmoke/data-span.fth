\ data-span.fth — inspect CREATE/VALUE layout for Emitter data copy.
\ Public domain.

ONLY FORTH DEFINITIONS DECIMAL
FROMLIB FLOAD Emitter/emitter.fth
ALSO GRAPHICS
S" /Users/thomaszimmer/Documents/64TCOM/64TCOMARM64/tetra/tetra.fth" INCLUDED
ONLY FORTH ALSO SYSVOC ALSO EMITTER

: .CELL  ( addr -- )  HEX DUP U. SPACE @ U. DECIMAL CR ;

: SHOW-DATA  ( xt -- )
  DUP NAME>STRING TYPE CR
  ."   cfa@ " DUP .CELL
  ."   +8   " DUP 8 + .CELL
  ."   +16  " DUP 16 + .CELL
  DUP DODOES? IF
    ."   does_ip xt-ish " DUP 8 + @ HEX U. DECIMAL CR
  THEN
  DROP ;

CR .( FIGURE.NO VALUE ) CR  ['] FIGURE.NO SHOW-DATA
CR .( G-COLS VALUE ) CR    ['] G-COLS SHOW-DATA
CR .( G-BUF CREATE ) CR    ['] G-BUF SHOW-DATA
CR .( CURR CREATE ) CR     ['] CURR SHOW-DATA
CR .( FIGURE CREATE ) CR   ['] FIGURE SHOW-DATA

\ G-BUF size: 80*25 bytes after PFA
CR .( G-BUF pfa size bytes ) G-COLS G-ROWS * . CR
\ FIGURE: 7 figures * 8 cells * 8 = 448 bytes?
CR .( FIGURE cells ) 7 8 * . CR

CR .( DONE data-span ) CR

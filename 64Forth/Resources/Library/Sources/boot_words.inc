// ============================================================================
// Boot word catalog — macro + table bookends
// ============================================================================
// BOOT_WORD rows live next to their CODE implementations in forth.s so
// LOCATE/VIEW land on the real primitive (same line as the assembly).
//
// Runtime still walks a contiguous table: each BOOT_WORD appends one
// 4-quad row to __DATA,__bootword; boot_word_table is the section start.
//
//   BOOT_WORD "NAME", "help stack comment", imm, CodeLabel
// CodeLabel:
//   ... implementation ...
//
// imm: 0 = normal, 1 = IMMEDIATE
// ============================================================================

//   BOOT_WORD "NAME", "help", imm, CodeLabel, CodeEndLabel
// CodeLabel:
//   ...
// CodeEndLabel:

.macro BOOT_WORD name, help, imm, code, end=0
    .pushsection __DATA,__bootword,regular
    .quad .Lbw_n\@, .Lbw_h\@, \imm, \code, \end
    .popsection
    .pushsection __TEXT,__cstring,cstring_literals
.Lbw_n\@:
    .asciz "\name"
.Lbw_h\@:
    .asciz "\help"
    .popsection
.endm

// Table start (rows emitted by BOOT_WORD throughout forth.s)
.section __DATA,__bootword,regular
.align 3
.globl _boot_word_table
_boot_word_table:
boot_word_table:

// Return to text for the rest of forth.s after .include
.text

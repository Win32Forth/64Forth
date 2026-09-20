// ============================================================================
// Boot word catalog — macro + table bookends
// ============================================================================
// BOOT_WORD rows live next to their CODE implementations in forth.s so
// LOCATE/VIEW land on the real primitive (same line as the assembly).
//
// ld64 may reorder/pad atoms in __bootword, so a stride-40 walk is unsafe.
// Each BOOT_WORD emits:
//   - cstrings for name/help
//   - a 5-quad row in __DATA,__bootword
//   - one packed pointer in __DATA,__bootptr → that row
// _boot_kernel walks section$start$__DATA$__bootptr .. section$end$.
//
// Define cstrings first, then the row, then the pointer — all with the same
// \@ so local labels stay consistent across .pushsection.
//
//   BOOT_WORD "NAME", "help stack comment", flags, CodeLabel
// CodeLabel:
//   ... implementation ...
// ============================================================================

.macro BOOT_WORD name, help, flags, code, end=0
    .pushsection __TEXT,__cstring,cstring_literals
.Lbw_n\@:
    .asciz "\name"
.Lbw_h\@:
    .asciz "\help"
    .popsection
    .pushsection __DATA,__bootword,regular
    .align 3
.Lbw_row\@:
    .quad .Lbw_n\@, .Lbw_h\@, \flags, \code, \end
    .popsection
    .pushsection __DATA,__bootptr,regular
    .align 3
    .quad .Lbw_row\@
    .popsection
.endm

.text

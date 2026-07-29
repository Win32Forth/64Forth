// ============================================================================
// COLON_WORD — document a high-level definition built by the interpreter
// ============================================================================
// Usage (in assembly, before / among forth_init .ascii chunks):
//
//   DEPTH is CODE (XDEPTH) in forth.s / boot_words.inc
//
// Or one-shot when body fits in one string (no nested double-quotes in help):
//
//   COLON_WORD_S "BL ( -- c ) blank character", ": BL 32 ; "
//
// Name for FIND comes from the definition (second token after ':').
// Help should start with that same name for SEE/HELP one-line display.
// Use IMMEDIATE inside the definition source when needed.
// ============================================================================

// Set pending help from a C string address, then fall through to following .ascii
// which is interpreted later as part of forth_init_str.
// Implementation: COLON_WORD emits a zstring + a tiny Forth snippet using SETDOC.
//
// Because help text often contains parentheses and quotes, prefer COLON_WORD
// (separate help .asciz + DOC via SETDOC from address) when quotes appear.

// COLON_WORD help  — emit help zstring; call from a Forth prelude is not automatic.
// For init-string integration use DOC" ... " before : NAME, or COLON_WORD_S.

.macro COLON_WORD_S help, body
    .ascii "S\" \help\" SETDOC "
    .ascii "\body"
    .ascii " "
.endm

// Document-only helper: plant help zstring for manual SETDOCZ if added later.
.macro COLON_DOC help
    .section __TEXT,__cstring,cstring_literals
.Lcolon_doc\@:
    .asciz "\help"
    .previous
.endm

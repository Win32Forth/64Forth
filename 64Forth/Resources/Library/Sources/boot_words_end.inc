// ============================================================================
// Boot word table end (sentinel) + boot helper C strings
// ============================================================================

// Null name* ends _boot_kernel walk of __DATA,__bootword
.section __DATA,__bootword,regular
.quad 0, 0, 0, 0

.equ BOOT_WORD_COUNT, 266

// Empty help used by : / CREATE / :NONAME
.section __TEXT,__cstring,cstring_literals
.align 3
boot_h_empty:
    .asciz ""

// C strings for _boot_cache_cfa
boot_cmp_lit: .asciz "LIT"
boot_cmp_exit: .asciz "EXIT"
boot_cmp_slit: .asciz "(S\")"
boot_cmp_cstr: .asciz "(C\")"
boot_cmp_type: .asciz "TYPE"
boot_cmp_branch: .asciz "BRANCH"
boot_cmp_0branch: .asciz "0BRANCH"
boot_cmp_does_rt: .asciz "(DOES>)"
boot_cmp_catch_ok: .asciz "(CATCH-OK)"
boot_cmp_local_init: .asciz "(LOCAL-INIT)"
boot_cmp_local_at: .asciz "(LOCAL@)"
boot_cmp_local_store: .asciz "(LOCAL!)"
boot_cmp_flit: .asciz "FLIT"
boot_cmp_execute: .asciz "EXECUTE"
boot_cmp_comma: .asciz ","

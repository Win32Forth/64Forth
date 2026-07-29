// ============================================================================
// PickleForth - A Forth kernel for ARM64 (Apple Silicon)
// ============================================================================
// Registers:
//   x20 = TOS  (Top of Data Stack)
//   x19 = IP   (Instruction Pointer)
//   x21 = W    (Working - current dict entry pointer)
//   x22 = DSP  (Data Stack, grows down)
//   x23 = RSP  (Return Stack, grows down)
//   x24 = &latest (pointer to variable holding newest dict entry)
//
// Register discipline (important):
//   VM state lives in x19-x24, which are AAPCS64 callee-saved.
//   Helpers that use them MUST save/restore (see SAVE_VM / RESTORE_VM).
//
//   Darwin ARM64 unix syscalls (svc #0x80): the kernel preserves x1-x28
//   and only returns a result in x0 (and sets NZCV.C on error). So raw
//   syscalls do NOT corrupt the Forth VM registers. The real hazard is
//   assembly helpers that temporarily borrow x19-x24 without saving them.
//
// Dictionary header format (built at runtime; grows up with HERE):
//   HFA:  counted HELP (stack pic + text), pad 8 (empty = count 0)
//   NFA:  counted NAME (uppercase), pad 8
//   LFA:  LINK  = previous CFA (or 0)     @ CFA-16  >LINK
//   FFA:  FLAGS @ CFA-8: low32 NFA_OFF, bits32-62 HFA_OFF, bit63 IMM
//   CFA:  CODE (** xt **)                 >CODE (= xt)
//   BODY: @ CFA+8                         >BODY
//
// LATEST = CFA. NEXT: W = CFA from *IP; br *W.
// _header_build for BOOT_WORD and : / CREATE. SETDOC/DOC" set pending help.
//
// ----------------------------------------------------------------------------
// ANS Forth 2012 compatibility
// ----------------------------------------------------------------------------
// Cell size: 64-bit (8 bytes). Flags: true = -1, false = 0.
//
// CORE (6.1) — word names: complete (all required Core names are present).
// This is NOT a claim of formal ANS System compliance: semantics, environmental
// restrictions, and the Hayes / forth2012-test-suite have not been certified.
// ENVIRONMENT? answers CORE true, CORE-EXT true, FLOORED false.
//
// Core coverage (by area; stack comments intended to match ANS):
//   Stack:    DUP DROP SWAP OVER ROT PICK ?DUP 2DUP 2DROP 2SWAP 2OVER DEPTH
//   Return:   >R R> R@
//   Arith:    + - * / MOD /MOD 1+ 1- NEGATE ABS MIN MAX LSHIFT RSHIFT
//             */ */MOD  (symmetric intermediate divide via SM/REM)
//   Double:   S>D 2* 2/ 2@ 2! UM* M* UM/MOD SM/REM FM/MOD
//   Logic:    AND OR XOR INVERT
//   Compare:  = <> < > U< 0= 0< 0<> 0> >= <= WITHIN TRUE FALSE
//   Memory:   @ ! C@ C! C, +! FILL ERASE MOVE CELL+ CELLS CHAR+ CHARS
//             ALIGN ALIGNED
//   Parse:    WORD PARSE CHAR [CHAR] BL >NUMBER
//   Comments: \  (   (plus common \S stop-load)
//   I/O:      EMIT KEY CR TYPE SPACE SPACES . U. ACCEPT
//   Strings:  S" ." COUNT
//   Numeric:  BASE DECIMAL HEX  pictured <# # #S #> HOLD SIGN
//   Compile:  : ; CREATE VARIABLE CONSTANT , ALLOT DP HERE
//             LITERAL ' ['] EXECUTE RECURSE IMMEDIATE [ ] POSTPONE
//   Control:  IF ELSE THEN BEGIN UNTIL AGAIN WHILE REPEAT EXIT
//             DO LOOP +LOOP I J LEAVE UNLOOP DOES>
//   Source:   SOURCE >IN EVALUATE REFILL SOURCE-ID
//   Search:   FIND ENVIRONMENT?
//   Outer:    QUIT ABORT ABORT"
//   Except:   CATCH THROW  (Exception word set; used by ABORT path)
//
// Implementation choices / differences (still ANS-legal where noted):
//   xt from ' / FIND / [']  = CFA (code-field address). ANS xt is opaque.
//   / MOD /MOD              = symmetric (toward zero), ARM sdiv; FLOORED false.
//   >BODY                   = after name for any xt (used by SEE on colon words);
//                             ANS text is oriented toward CREATE bodies.
//   FIND                    = case-insensitive names.
//   INCLUDE                 = loads whole file into one SOURCE (REFILL is false
//                             for file/EVALUATE sources; true only for terminal).
//   \S                      = pin >IN to end of current SOURCE (file stop);
//                             console multi-line paste stopped via host flag.
//   Header layout           = link | flags|len | code | name | body  (see above).
//
// ----------------------------------------------------------------------------
// CORE EXT (6.2) — word names: complete (all required Core Ext names present).
// ----------------------------------------------------------------------------
// ANS Core Extensions word set — implemented in PickleForth:
//   .(  :NONAME  ?DO
//   2>R  2R>  2R@
//   <>  0<>  0>  AGAIN
//   BUFFER:  C"  COMPILE,  [COMPILE]
//   CASE  OF  ENDOF  ENDCASE
//   DEFER  DEFER!  DEFER@  IS  ACTION-OF
//   ERASE  FALSE  TRUE  HEX
//   HOLDS  MARKER
//   NIP  TUCK  PICK  PAD  PARSE  PARSE-NAME
//   REFILL  SOURCE-ID  UNUSED  WITHIN
//   ROLL  U>  U.R
//   S\"   SAVE-INPUT  RESTORE-INPUT
//   VALUE  TO
//   \          (line comment; also used as Core Ext)
//
// Related non-Core-Ext but present (File / tools / common):
//   CMOVE  CMOVE>  INCLUDE  (FLOAD is an alias of INCLUDE)
//   \S / \s     stop remainder of current INCLUDE/FLOAD SOURCE, or remainder
//               of a multi-line console paste (TZForth / F-PC model; immediate)
//
// ENVIRONMENT? returns CORE-EXT true (names present; not a formal ANS certificate).
//
// ----------------------------------------------------------------------------
// PickleForth extensions (not ANS Core / Core Ext)
// ----------------------------------------------------------------------------
//   >CODE >NAME >FLAGS >LINK NAME>STRING DOCOL? DOCON-ADDR CELL
//   SP0 SP@ SP!           stack probes (DEPTH and ABORT use these)
//   LATEST                DP is ANS-style; LATEST is system
//   LIT BRANCH 0BRANCH and *-ADDR plumbing
//   ALIAS SEE WORDS .S DUMP FORGET ANEW USER-DICT REDEF-WARNING
//   FILE-ECHO ON OFF      echo INCLUDE/FLOAD source lines when FILE-ECHO is on
//   .FREE GROWMEMORYMB MS@ ELAPSED .ELAPSED CONTAINS
//   Line editor + history; "undefined:" and stack error reporting
//   SIGSEGV/SIGBUS recovery back to QUIT
//
// Implementation notes:
//   - Indirect threaded; colon cells hold dictionary entry addresses (xts)
//   - Prefer high-level Forth in forth_init_str; assembly when needed
//   - CREATE body: does_ip at +0, user PFA at +8 (DOVAR / DODOES / DOCON)
//   - No stack checks inside primitives (speed); outer interpreter checks
//     DSP between words; memory faults recover via signal handler
// ============================================================================

.text
.align 4

// ============================================================================
// Macros
// ============================================================================
.macro NEXT
    ldr x21, [x19], #8          // W = CFA (xt)
    ldr x1, [x21]               // code field at CFA
    br x1
.endm

// Debug version of NEXT
.macro DEBUG_NEXT
    ldr x21, [x19], #8
    ldr x1, [x21]
    // Store crash diagnostics and write to stderr
    stp x0, x1, [sp, #-16]!
    adrp x0, next_diag@page
    add x0, x0, next_diag@pageoff
    str x19, [x0]
    str x21, [x0, #8]
    str x1, [x0, #16]
    // Write to stderr (fd=2)
    mov x0, #2
    adr next_diag@page
    add x1, x1, next_diag@pageoff
    mov x2, #24
    mov x16, #4
    svc #0x80
    ldp x0, x1, [sp], #16
    br x1
.endm

.macro DPUSH
    str x20, [x22, #-8]!
    mov x20, x0
.endm

.macro DPOP
    mov x0, x20
    ldr x20, [x22], #8
.endm

.macro RPUSH reg=x19
    str \reg, [x23, #-8]!
.endm

.macro RPOP reg=x19
    ldr \reg, [x23], #8
.endm

// Save/restore full VM register set across bl/svc that might borrow them.
// Call AFTER any intentional TOS/DSP updates so those changes survive.
.macro SAVE_VM
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
.endm

.macro RESTORE_VM
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
.endm

// ============================================================================
// Entry Point — terminal cold start (do not call from SwiftUI host)
// ============================================================================
.globl _kernel_cold_start
_kernel_cold_start:
    // Terminal mode (infinite QUIT loop after bootstrap)
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    str  xzr, [x0]

    bl _kernel_cold_common

    // Print welcome via raw SVC
    mov x0, #1
    adrp x1, str_hello@page
    add x1, x1, str_hello@pageoff
    mov x2, #19                    // "PickleForth v0.4.0\n"
    mov x16, #4
    svc #0x80

    // Initialize Forth from init string via SOURCE / >IN
    adrp x0, forth_init_str@page
    add x0, x0, forth_init_str@pageoff
    mov x1, x0
    mov x2, #0
1:
    ldrb w3, [x1, x2]
    cbz w3, 2f
    add x2, x2, #1
    b 1b
2:
    mov x1, x2                      // len
    bl _set_source
    b _interpret_loop

// Shared cold bootstrap: stacks, LATEST, HERE, fault handlers, boot dict.
// Clobbers VM regs; leaves x20/x22/x23/x24 ready for interpret.
_kernel_cold_common:
    stp x29, x30, [sp, #-16]!
    adrp x22, data_stack@page
    add  x22, x22, data_stack@pageoff
    add  x22, x22, #4096      // DSP starts at TOP of stack (grows down)
    adrp x23, return_stack@page
    add  x23, x23, return_stack@pageoff
    add  x23, x23, #2048      // RSP starts at TOP of stack (grows down)

    // x24 = address of latest_var (pointer to variable holding newest dict entry)
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff

    // Initialize TOS (empty stack)
    mov  x20, #0

    // LATEST empty until boot catalog is built
    str  xzr, [x24]

    // HERE = user_dict_area
    adrp x0, here_ptr@page
    add  x0, x0, here_ptr@pageoff
    adrp x1, user_dict_area@page
    add  x1, x1, user_dict_area@pageoff
    str  x1, [x0]

    bl _install_fault_handlers
    bl _boot_kernel
    // Search-Order defaults: CURRENT = FORTH wordlist (&latest_var), order = (FORTH)
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    adrp x1, current_var@page
    add  x1, x1, current_var@pageoff
    str  x0, [x1]
    adrp x1, search_order@page
    add  x1, x1, search_order@pageoff
    str  x0, [x1]
    mov  x0, #1
    adrp x1, search_order_n@page
    add  x1, x1, search_order_n@pageoff
    str  x0, [x1]
    ldp x29, x30, [sp], #16
    ret

// ============================================================================
// Embeddable C ABI (Phase 1) — used by Swift KernelBridge
//   kernel_init(void) -> int
//   kernel_eval(const char *line, size_t n) -> int
//   kernel_set_emit(void (*fn)(int c))
//   kernel_set_key(int (*fn)(void))
// Returns: 0 ok, 1 BYE requested, -1 fault/error, -2 not initialized
// ============================================================================

// void kernel_set_emit(void (*fn)(int c))
.globl _kernel_set_emit
_kernel_set_emit:
    adrp x1, emit_hook@page
    add  x1, x1, emit_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_key(int (*fn)(void))
.globl _kernel_set_key
_kernel_set_key:
    adrp x1, key_hook@page
    add  x1, x1, key_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_key_q(int (*fn)(void)) — KEY? non-blocking availability
.globl _kernel_set_key_q
_kernel_set_key_q:
    adrp x1, key_q_hook@page
    add  x1, x1, key_q_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_time_date(void (*fn)(int64_t out[6]))
.globl _kernel_set_time_date
_kernel_set_time_date:
    adrp x1, time_date_hook@page
    add  x1, x1, time_date_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_file_op(file_op_fn)
.globl _kernel_set_file_op
_kernel_set_file_op:
    adrp x1, file_op_hook@page
    add  x1, x1, file_op_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_fromlib(void (*fn)(void))
.globl _kernel_set_fromlib
_kernel_set_fromlib:
    adrp x1, fromlib_hook@page
    add  x1, x1, fromlib_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_fromlib_clear(void (*fn)(void)) — disarm FROMLIB (REQUIRE skip)
.globl _kernel_set_fromlib_clear
_kernel_set_fromlib_clear:
    adrp x1, fromlib_clear_hook@page
    add  x1, x1, fromlib_clear_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_end_include(void (*fn)(void)) — file INCLUDE SOURCE finished
.globl _kernel_set_end_include
_kernel_set_end_include:
    adrp x1, end_include_hook@page
    add  x1, x1, end_include_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_load_file(int (*fn)(const char*, size_t, const char**, size_t*))
// path_len==0 → bare FLOAD/INCLUDE (host may show open panel).
.globl _kernel_set_load_file
_kernel_set_load_file:
    adrp x1, load_file_hook@page
    add  x1, x1, load_file_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_resolve_key(int (*)(path, path_len, out, out_max, out_len*))
.globl _kernel_set_resolve_key
_kernel_set_resolve_key:
    adrp x1, resolve_key_hook@page
    add  x1, x1, resolve_key_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_last_load_key(int (*)(out, out_max, out_len*))
.globl _kernel_set_last_load_key
_kernel_set_last_load_key:
    adrp x1, last_load_key_hook@page
    add  x1, x1, last_load_key_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_chdir(void (*fn)(const char *path, size_t n))
// n==0 → bare CHDIR (host folder picker).
.globl _kernel_set_chdir
_kernel_set_chdir:
    adrp x1, chdir_hook@page
    add  x1, x1, chdir_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_pwd(void (*fn)(void))
.globl _kernel_set_pwd
_kernel_set_pwd:
    adrp x1, pwd_hook@page
    add  x1, x1, pwd_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_dir(void (*fn)(const char *path, size_t n))
// n==0 → list logical cwd (or Library if FROMLIB armed).
.globl _kernel_set_dir
_kernel_set_dir:
    adrp x1, dir_hook@page
    add  x1, x1, dir_hook@pageoff
    str  x0, [x1]
    ret

// void kernel_set_edit(void (*fn)(const char *path, size_t n))
// n==0 → open panel; named → system editor + cwd (FROMLIB ok).
.globl _kernel_set_edit
_kernel_set_edit:
    adrp x1, edit_hook@page
    add  x1, x1, edit_hook@pageoff
    str  x0, [x1]
    ret

.globl _kernel_set_allocate
_kernel_set_allocate:
    adrp x1, alloc_hook@page
    add  x1, x1, alloc_hook@pageoff
    str  x0, [x1]
    ret

.globl _kernel_set_free
_kernel_set_free:
    adrp x1, free_hook@page
    add  x1, x1, free_hook@pageoff
    str  x0, [x1]
    ret

.globl _kernel_set_bi_mul
_kernel_set_bi_mul:
    adrp x1, bi_mul_hook@page
    add  x1, x1, bi_mul_hook@pageoff
    str  x0, [x1]
    ret

.globl _kernel_set_bi_divmod
_kernel_set_bi_divmod:
    adrp x1, bi_divmod_hook@page
    add  x1, x1, bi_divmod_hook@pageoff
    str  x0, [x1]
    ret

.globl _kernel_set_bi_isqrt
_kernel_set_bi_isqrt:
    adrp x1, bi_isqrt_hook@page
    add  x1, x1, bi_isqrt_hook@pageoff
    str  x0, [x1]
    ret

// int kernel_take_repl_batch_stop(void)
// Return 1 if \S ran on the console SOURCE (SOURCE-ID 0) since last take, else 0.
// Clears the sticky flag (TZForth clearReplBatchStop / replBatchStopRequested).
.globl _kernel_take_repl_batch_stop
_kernel_take_repl_batch_stop:
    adrp x1, repl_batch_stop@page
    add  x1, x1, repl_batch_stop@pageoff
    ldr  x0, [x1]
    str  xzr, [x1]
    ret

// void kernel_on_memory_fault(int sig)
// Host or kernel signal handler entry: recover via siglongjmp to active setjmp
// (kernel_eval / QUIT). Async-signal-safe (no emit_hook here).
.globl _kernel_on_memory_fault
_kernel_on_memory_fault:
    // Sticky note for host after recovery (read via kernel_take_fault_flag)
    adrp x0, fault_pending@page
    add  x0, x0, fault_pending@pageoff
    mov  x1, #1
    str  x1, [x0]
    // stderr note (may be invisible in GUI; host also prints after evaluate returns -1)
    mov  x0, #2
    adrp x1, str_memfault@page
    add  x1, x1, str_memfault@pageoff
    mov  x2, #20
    mov  x16, #4
    svc  #0x80
    adrp x0, quit_jmpbuf@page
    add  x0, x0, quit_jmpbuf@pageoff
    mov  x1, #1
    bl   _siglongjmp               // does not return

// int kernel_take_fault_flag(void) — 1 if a memory fault recovered since last take
.globl _kernel_take_fault_flag
_kernel_take_fault_flag:
    adrp x1, fault_pending@page
    add  x1, x1, fault_pending@pageoff
    ldr  x0, [x1]
    str  xzr, [x1]
    ret

// int kernel_init(void)
// Build dictionary + interpret forth_init_str, then return (no QUIT loop).
.globl _kernel_init
_kernel_init:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    // C frame for return from interpreter (must be set before any early exit)
    mov  x0, sp
    adrp x1, embed_c_sp@page
    add  x1, x1, embed_c_sp@pageoff
    str  x0, [x1]

    // Already initialized?
    adrp x0, kernel_inited@page
    add  x0, x0, kernel_inited@pageoff
    ldr  x1, [x0]
    cbnz x1, _kinit_already

    // Mark embed mode
    mov  x1, #1
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    str  x1, [x0]

    bl _kernel_cold_common

    // Persist VM + mark inited before interpret (init string may call embed return)
    bl _vm_save
    mov  x1, #1
    adrp x0, kernel_inited@page
    add  x0, x0, kernel_inited@pageoff
    str  x1, [x0]

    // Fault recovery → return to C
    adrp x0, quit_jmpbuf@page
    add  x0, x0, quit_jmpbuf@pageoff
    mov  x1, #1
    bl   _sigsetjmp
    cbz  x0, 1f
    bl   _vm_reset_stacks
    bl   _emit_memfault_msg
    mov  x0, #-1
    b    _embed_ret_x0
1:
    // Interpret bootstrap colon definitions (no terminal hello)
    adrp x0, forth_init_str@page
    add  x0, x0, forth_init_str@pageoff
    mov  x1, x0
    mov  x2, #0
2:
    ldrb w3, [x1, x2]
    cbz  w3, 3f
    add  x2, x2, #1
    b    2b
3:
    mov  x1, x2
    bl   _set_source
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    str  xzr, [x0]
    b    _interpret_loop

_kinit_already:
    mov  x0, #0
    b    _embed_ret_x0

// int kernel_eval(const char *line, size_t n)
.globl _kernel_eval
_kernel_eval:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    // C frame for return (before any early exit)
    mov  x2, sp
    adrp x3, embed_c_sp@page
    add  x3, x3, embed_c_sp@pageoff
    str  x2, [x3]

    // Save args (setjmp / helpers clobber x0-x1)
    adrp x2, eval_arg_ptr@page
    add  x2, x2, eval_arg_ptr@pageoff
    str  x0, [x2]
    adrp x2, eval_arg_len@page
    add  x2, x2, eval_arg_len@pageoff
    str  x1, [x2]

    // Require kernel_init
    adrp x2, kernel_inited@page
    add  x2, x2, kernel_inited@pageoff
    ldr  x2, [x2]
    cbnz x2, 1f
    mov  x0, #-2
    b    _embed_ret_x0
1:
    mov  x1, #1
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    str  x1, [x0]

    bl   _vm_load

    adrp x0, quit_jmpbuf@page
    add  x0, x0, quit_jmpbuf@pageoff
    mov  x1, #1
    bl   _sigsetjmp
    cbz  x0, 2f
    // Recovered from SIGSEGV/SIGBUS (or host kernel_on_memory_fault)
    bl   _vm_reset_stacks
    bl   _emit_memfault_msg        // console-visible (emit_hook), not only stderr
    bl   _vm_save
    mov  x0, #-1
    b    _embed_ret_x0
2:
    // Copy line into input_buffer (max 1023 + NUL)
    adrp x0, eval_arg_ptr@page
    add  x0, x0, eval_arg_ptr@pageoff
    ldr  x0, [x0]
    adrp x1, eval_arg_len@page
    add  x1, x1, eval_arg_len@pageoff
    ldr  x1, [x1]
    adrp x2, input_buffer@page
    add  x2, x2, input_buffer@pageoff
    mov  x3, #1023
    cmp  x1, x3
    csel x1, x3, x1, hi
    mov  x3, #0
    cbz  x0, 4f
3:
    cmp  x3, x1
    b.hs 4f
    ldrb w4, [x0, x3]
    strb w4, [x2, x3]
    add  x3, x3, #1
    b    3b
4:
    strb wzr, [x2, x3]             // NUL
    mov  x0, x2
    mov  x1, x3
    bl   _set_source
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    str  xzr, [x0]
    b    _interpret_loop

// Save TOS/DSP/RSP for next kernel_eval (registers restored to C on return)
_vm_save:
    adrp x0, vm_tos@page
    add  x0, x0, vm_tos@pageoff
    str  x20, [x0]
    adrp x0, vm_dsp@page
    add  x0, x0, vm_dsp@pageoff
    str  x22, [x0]
    adrp x0, vm_rsp@page
    add  x0, x0, vm_rsp@pageoff
    str  x23, [x0]
    ret

_vm_load:
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff
    adrp x0, vm_tos@page
    add  x0, x0, vm_tos@pageoff
    ldr  x20, [x0]
    adrp x0, vm_dsp@page
    add  x0, x0, vm_dsp@pageoff
    ldr  x22, [x0]
    adrp x0, vm_rsp@page
    add  x0, x0, vm_rsp@pageoff
    ldr  x23, [x0]
    // If never saved (0), reset stacks
    cbnz x22, 1f
    b    _vm_reset_stacks
1:
    ret

_vm_reset_stacks:
    adrp x22, data_stack@page
    add  x22, x22, data_stack@pageoff
    add  x22, x22, #4096
    mov  x20, #0
    adrp x23, return_stack@page
    add  x23, x23, return_stack@pageoff
    add  x23, x23, #2048
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff
    adrp x0, throw_handler@page
    add  x0, x0, throw_handler@pageoff
    str  xzr, [x0]
    adrp x0, state_var@page
    add  x0, x0, state_var@pageoff
    str  xzr, [x0]
    adrp x0, source_sp@page
    add  x0, x0, source_sp@pageoff
    str  xzr, [x0]
    ret

// First-time outer defaults (same as first terminal QUIT iteration)
_embed_redef_boot_once:
    adrp x0, redef_boot_done@page
    add  x0, x0, redef_boot_done@pageoff
    ldr  x1, [x0]
    cbnz x1, 1f
    mov  x1, #1
    str  x1, [x0]
    adrp x0, redef_warn@page
    add  x0, x0, redef_warn@pageoff
    mov  x1, #-1
    str  x1, [x0]
    // Clear residual stack from bootstrap only once
    adrp x22, data_stack@page
    add  x22, x22, data_stack@pageoff
    add  x22, x22, #4096
    mov  x20, #0
1:
    ret

// Return from embed interpret: print ok path lands here after _write_stdout
_embed_finish:
    bl   _embed_redef_boot_once
    bl   _vm_save
    mov  x0, #0
    b    _embed_ret_x0

// QUIT / uncaught THROW in embed mode (no " ok")
_embed_quit_return:
    bl   _embed_redef_boot_once
    bl   _vm_save
    mov  x0, #0
    b    _embed_ret_x0

// BYE in embed mode
_embed_bye_return:
    bl   _vm_save
    mov  x0, #1
    b    _embed_ret_x0

// Restore C callee-saved and return status in x0
_embed_ret_x0:
    adrp x1, embed_c_sp@page
    add  x1, x1, embed_c_sp@pageoff
    ldr  x1, [x1]
    mov  sp, x1
    ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x23, x24, [sp, #48]
    ldp  x25, x26, [sp, #64]
    ldp  x27, x28, [sp, #80]
    ldp  x29, x30, [sp], #96
    ret

// ---------------------------------------------------------------------------
// Fault recovery: SIGSEGV / SIGBUS → siglongjmp to kernel_eval/QUIT setjmp
// (TZForth-style soft recover; process stays alive). Uses sigaction so the
// handler is not reset after the first delivery (BSD signal() semantics).
// Under Xcode LLDB also needs: process handle SIGSEGV -p true -s false
// (see .lldbinit-64forth + scheme customLLDBInitFile).
// ---------------------------------------------------------------------------
// Darwin arm64 struct sigaction is 16 bytes: handler@0, sa_mask@8, sa_flags@12
.equ SA_NODEFER_FLAG, 16
.equ SIGSEGV_N, 11
.equ SIGBUS_N, 10

_install_fault_handlers:
    stp x29, x30, [sp, #-16]!
    adrp x0, fault_handlers_on@page
    add  x0, x0, fault_handlers_on@pageoff
    ldr  x1, [x0]
    cbnz x1, 1f
    mov  x1, #1
    str  x1, [x0]
    // Build sigaction on stack
    sub  sp, sp, #16
    adrp x0, _kernel_on_memory_fault@page
    add  x0, x0, _kernel_on_memory_fault@pageoff
    str  x0, [sp]                  // sa_handler
    str  wzr, [sp, #8]             // sa_mask = 0
    mov  w0, #SA_NODEFER_FLAG
    str  w0, [sp, #12]             // sa_flags
    mov  x0, #SIGSEGV_N
    mov  x1, sp
    mov  x2, #0                    // oact = NULL
    bl   _sigaction
    mov  x0, #SIGBUS_N
    mov  x1, sp
    mov  x2, #0
    bl   _sigaction
    add  sp, sp, #16
1:
    ldp x29, x30, [sp], #16
    ret

// ============================================================================
// DOCOL / DOEXIT / DOVAR
// ============================================================================
// xt = CFA = x21. Body always at CFA+8. CREATE: does_ip @ CFA+8, PFA @ CFA+16.
// Header layout (low → high):
//   HFA: counted HELP + pad 8
//   NFA: counted NAME (UC) + pad 8
//   LFA: LINK (prev CFA)     @ CFA-16
//   FFA: FLAGS               @ CFA-8
//   CFA: CODE
//   BODY                     @ CFA+8
// FLAGS: bits 0-31 NFA_OFF, bits 32-62 HFA_OFF, bit 63 IMMEDIATE
.equ NFA_OFF_MASK, 0xFFFFFFFF
.equ HFA_OFF_MASK, 0x7FFFFFFF
.equ FLAG_IMM, 0x8000000000000000   // bit 63

.macro DICT_BODY_ADDR dst, cfa
    add \dst, \cfa, #8
.endm

DOCOL:
    RPUSH
    add x19, x21, #8               // IP = body (CFA+8)
    NEXT

DOEXIT:
    // Pop locals frame if this EXIT matches the frame's return depth
    bl _local_frame_try_exit
    RPOP
    NEXT

DOVAR:
    // Push user PFA = CFA+16 (does_ip lives at CFA+8)
    str x20, [x22, #-8]!
    add x20, x21, #16
    NEXT

DOCON:
    str x20, [x22, #-8]!
    ldr x20, [x21, #16]            // value at PFA (CFA+16)
    NEXT

// DODOES: push PFA (CFA+16), run high-level fragment at [CFA+8]
DODOES:
    RPUSH
    ldr x19, [x21, #8]             // does_ip
    add x0, x21, #16               // PFA
    str x20, [x22, #-8]!
    mov x20, x0
    NEXT

// ============================================================================
// Dictionary header builder (runtime) + kernel boot from structured records
// ============================================================================
// _header_build:
//   x0=name addr, x1=name len, x2=help addr, x3=help len, x4=code addr, x5=imm(0/1)
//   Builds: HFA help | NFA name | LFA link | FFA flags | CFA code
//   HERE → CFA+8. Links into CURRENT wordlist head. Returns x0 = CFA.
//   Names UPPERCASE. Help always written (empty = count 0 + pad 8).
// ============================================================================
.align 4
_header_build:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0                    // name
    mov x20, x1                    // nlen
    mov x21, x2                    // help
    mov x22, x3                    // hlen
    mov x23, x4                    // code
    str x5, [sp, #-16]!            // imm

    // CURRENT wordlist head cell (wid); fallback to latest_var
    adrp x24, current_var@page
    add  x24, x24, current_var@pageoff
    ldr  x24, [x24]
    cbnz x24, 0f
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff
0:

    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x6, [x0]                   // HERE
    mov x8, x6                     // HFA

    // --- counted help first, pad 8 (always at least empty record) ---
    cmp x22, #255
    b.ls 1f
    mov x22, #255
1:
    strb w22, [x6], #1
    mov x2, #0
2:
    cmp x2, x22
    b.ge 3f
    ldrb w3, [x21, x2]
    strb w3, [x6], #1
    add x2, x2, #1
    b 2b
3:
    sub x2, x6, x8
4:
    tst x2, #7
    b.eq 5f
    strb wzr, [x6], #1
    add x2, x2, #1
    b 4b
5:
    // --- counted name (uppercase), pad 8 ---
    mov x7, x6                     // NFA
    cmp x20, #255
    b.ls 6f
    mov x20, #255
6:
    strb w20, [x6], #1
    mov x2, #0
7:
    cmp x2, x20
    b.ge 8f
    ldrb w3, [x19, x2]
    cmp w3, #'a'
    b.lo 71f
    cmp w3, #'z'
    b.hi 71f
    sub w3, w3, #32
71:
    strb w3, [x6], #1
    add x2, x2, #1
    b 7b
8:
    sub x2, x6, x7
9:
    tst x2, #7
    b.eq 10f
    strb wzr, [x6], #1
    add x2, x2, #1
    b 9b
10:
    // --- LFA ---
    ldr x1, [x24]
    str x1, [x6], #8
    // --- FFA placeholder ---
    str xzr, [x6], #8
    // --- CFA ---
    mov x0, x6                     // CFA
    str x23, [x6], #8
    // FLAGS = NFA_OFF | (HFA_OFF << 32) | IMM<<63
    sub x1, x0, x7                 // NFA_OFF
    sub x2, x0, x8                 // HFA_OFF
    and x2, x2, #0x7FFFFFFF
    lsl x2, x2, #32
    orr x1, x1, x2
    ldr x5, [sp], #16              // imm
    cbz x5, 11f
    mov x2, #1
    lsl x2, x2, #63                // FLAG_IMM
    orr x1, x1, x2
11:
    str x1, [x0, #-8]
    adrp x2, here_ptr@page
    add x2, x2, here_ptr@pageoff
    str x6, [x2]
    str x0, [x24]                  // LATEST = CFA
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _take_pending_help: -> x2=help addr, x3=hlen; clears pending (empty if none)
_take_pending_help:
    adrp x0, pending_help_addr@page
    add x0, x0, pending_help_addr@pageoff
    ldr x2, [x0]
    adrp x1, pending_help_len@page
    add x1, x1, pending_help_len@pageoff
    ldr x3, [x1]
    str xzr, [x0]
    str xzr, [x1]
    cbnz x2, 1f
    adrp x2, boot_h_empty@page
    add x2, x2, boot_h_empty@pageoff
    mov x3, #0
1:
    ret

// strlen: x0=zstr -> x0=len
_strlen:
    mov x1, x0
    mov x0, #0
1:
    ldrb w2, [x1, x0]
    cbz w2, 2f
    add x0, x0, #1
    b 1b
2:
    ret

// _boot_kernel: walk boot_word_table, build headers, cache important CFAs
_boot_kernel:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!

    // boot_word_table rows: name*, help*, imm, code*  (code from BOOT_WORD ... XDUP)
    adrp x19, boot_word_table@page
    add x19, x19, boot_word_table@pageoff
_bk_loop:
    ldr x20, [x19], #8             // name ptr
    cbz x20, _bk_done
    ldr x21, [x19], #8             // help ptr
    ldr x22, [x19], #8             // imm
    ldr x4, [x19], #8              // code (e.g. XDUP)
    // name len
    mov x0, x20
    bl _strlen
    mov x1, x0                     // nlen
    mov x0, x20                    // name
    // help len
    stp x0, x1, [sp, #-16]!
    mov x0, x21
    bl _strlen
    mov x3, x0                     // hlen
    ldp x0, x1, [sp], #16
    mov x2, x21                    // help
    // x4 = code already
    mov x5, x22                    // imm
    bl _header_build               // x0 = CFA
    mov x21, x0                    // cfa for cache
    mov x0, x20                    // name z
    bl _boot_cache_cfa
    b _bk_loop
_bk_done:
    // restart trampoline CFA cell
    adrp x0, XRESTART@page
    add x0, x0, XRESTART@pageoff
    adrp x1, restart_cfa@page
    add x1, x1, restart_cfa@pageoff
    str x0, [x1]
    adrp x0, restart_cell@page
    add x0, x0, restart_cell@pageoff
    adrp x1, restart_cfa@page
    add x1, x1, restart_cfa@pageoff
    str x1, [x0]

    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _boot_cache_cfa: x0 = name C string, x21 = cfa
// Fills cfa_* cells for names needed by the assembler.
_boot_cache_cfa:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x19, x0                    // name
    mov x20, x21                   // cfa
    // LIT
    adrp x1, boot_cmp_lit@page
    add x1, x1, boot_cmp_lit@pageoff
    bl _zcmp
    cbnz x0, 1f
    adrp x2, cfa_lit@page
    add x2, x2, cfa_lit@pageoff
    str x20, [x2]
    b 9f
1:  mov x0, x19
    adrp x1, boot_cmp_exit@page
    add x1, x1, boot_cmp_exit@pageoff
    bl _zcmp
    cbnz x0, 2f
    adrp x2, cfa_exit@page
    add x2, x2, cfa_exit@pageoff
    str x20, [x2]
    b 9f
2:  mov x0, x19
    adrp x1, boot_cmp_slit@page
    add x1, x1, boot_cmp_slit@pageoff
    bl _zcmp
    cbnz x0, 3f
    adrp x2, cfa_slit@page
    add x2, x2, cfa_slit@pageoff
    str x20, [x2]
    b 9f
3:  mov x0, x19
    adrp x1, boot_cmp_cstr@page
    add x1, x1, boot_cmp_cstr@pageoff
    bl _zcmp
    cbnz x0, 4f
    adrp x2, cfa_cstr@page
    add x2, x2, cfa_cstr@pageoff
    str x20, [x2]
    b 9f
4:  mov x0, x19
    adrp x1, boot_cmp_type@page
    add x1, x1, boot_cmp_type@pageoff
    bl _zcmp
    cbnz x0, 5f
    adrp x2, cfa_type@page
    add x2, x2, cfa_type@pageoff
    str x20, [x2]
    b 9f
5:  mov x0, x19
    adrp x1, boot_cmp_branch@page
    add x1, x1, boot_cmp_branch@pageoff
    bl _zcmp
    cbnz x0, 6f
    adrp x2, cfa_branch@page
    add x2, x2, cfa_branch@pageoff
    str x20, [x2]
    b 9f
6:  mov x0, x19
    adrp x1, boot_cmp_0branch@page
    add x1, x1, boot_cmp_0branch@pageoff
    bl _zcmp
    cbnz x0, 7f
    adrp x2, cfa_0branch@page
    add x2, x2, cfa_0branch@pageoff
    str x20, [x2]
    b 9f
7:  mov x0, x19
    adrp x1, boot_cmp_does_rt@page
    add x1, x1, boot_cmp_does_rt@pageoff
    bl _zcmp
    cbnz x0, 8f
    adrp x2, cfa_does_rt@page
    add x2, x2, cfa_does_rt@pageoff
    str x20, [x2]
    b 9f
8:  mov x0, x19
    adrp x1, boot_cmp_catch_ok@page
    add x1, x1, boot_cmp_catch_ok@pageoff
    bl _zcmp
    cbnz x0, 81f
    adrp x2, cfa_catch_ok@page
    add x2, x2, cfa_catch_ok@pageoff
    str x20, [x2]
    b 9f
81: mov x0, x19
    adrp x1, boot_cmp_local_init@page
    add x1, x1, boot_cmp_local_init@pageoff
    bl _zcmp
    cbnz x0, 82f
    adrp x2, cfa_local_init@page
    add x2, x2, cfa_local_init@pageoff
    str x20, [x2]
    b 9f
82: mov x0, x19
    adrp x1, boot_cmp_local_at@page
    add x1, x1, boot_cmp_local_at@pageoff
    bl _zcmp
    cbnz x0, 83f
    adrp x2, cfa_local_at@page
    add x2, x2, cfa_local_at@pageoff
    str x20, [x2]
    b 9f
83: mov x0, x19
    adrp x1, boot_cmp_local_store@page
    add x1, x1, boot_cmp_local_store@pageoff
    bl _zcmp
    cbnz x0, 9f
    adrp x2, cfa_local_store@page
    add x2, x2, cfa_local_store@pageoff
    str x20, [x2]
9:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _zcmp: x0=a, x1=b -> x0=0 if equal
_zcmp:
1:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, w3
    b.ne 2f
    cbnz w2, 1b
    mov x0, #0
    ret
2:
    mov x0, #1
    ret

// ============================================================================
// Stack Primitives
// ============================================================================
// Note: no per-primitive stack checks (performance). The outer interpreter
// validates the data stack between words via _check_stack.
XDUP:
    str x20, [x22, #-8]!
    NEXT

// ?DUP ( x -- x x | 0 ) duplicate TOS if nonzero
XQDUP:
    cbz x20, _qdup_done
    str x20, [x22, #-8]!
_qdup_done:
    NEXT

XDROP:
    ldr x20, [x22], #8
    NEXT

XSWAP:
    ldr x0, [x22]
    str x20, [x22]
    mov x20, x0
    NEXT

XOVER:
    str x20, [x22, #-8]!
    ldr x20, [x22, #8]
    NEXT

XROT:
    ldr x0, [x22]
    ldr x1, [x22, #8]
    str x0, [x22, #8]
    str x20, [x22]
    mov x20, x1
    NEXT

XNIP:
    ldr x0, [x22], #8
    NEXT

XTUCK:
    ldr x0, [x22]
    str x20, [x22, #-8]!
    str x0, [x22]
    NEXT

XPICK:
    lsl x0, x20, #3
    ldr x0, [x22, x0]
    mov x20, x0
    NEXT

// ROLL ( xu xu-1 ... x0 u -- xu-1 ... x0 xu )
// u=0 no-op; u=1 SWAP; u=2 ROT.
XROLL:
    mov x1, x20                    // u
    ldr x20, [x22], #8             // pop u; TOS = x0
    cbz x1, _roll_done
    // Under TOS: [DSP+0]=x1 ... [DSP+(u-1)*8]=xu
    sub x2, x1, #1
    lsl x2, x2, #3                 // (u-1)*8
    ldr x3, [x22, x2]              // xu
    mov x0, x20                    // save old x0
    // shift slots [u-1]..[1] <- [u-2]..[0]
    mov x4, x2
1:
    cbz x4, 2f
    sub x5, x4, #8
    ldr x6, [x22, x5]
    str x6, [x22, x4]
    mov x4, x5
    b 1b
2:
    str x0, [x22]                  // [0] = old x0
    mov x20, x3                    // TOS = xu
_roll_done:
    NEXT

XTOR:
    str x20, [x23, #-8]!
    ldr x20, [x22], #8
    NEXT

XRTO:
    DPUSH
    ldr x0, [x23], #8
    mov x20, x0
    NEXT

XRFETCH:
    DPUSH
    ldr x0, [x23]
    mov x20, x0
    NEXT

// 2>R ( x1 x2 -- ) ( R: -- x1 x2 )  must be CODE (colon would clobber IP)
X2TOR:
    ldr x0, [x22], #8              // x1
    str x0, [x23, #-8]!            // R: x1
    str x20, [x23, #-8]!           // R: x1 x2
    ldr x20, [x22], #8
    NEXT

// 2R> ( -- x1 x2 ) ( R: x1 x2 -- )
X2RTO:
    str x20, [x22, #-8]!
    ldr x0, [x23], #8              // x2
    ldr x1, [x23], #8              // x1
    str x1, [x22, #-8]!
    mov x20, x0
    NEXT

// 2R@ ( -- x1 x2 ) ( R: x1 x2 -- x1 x2 )
X2RFETCH:
    str x20, [x22, #-8]!
    ldr x0, [x23]                  // x2
    ldr x1, [x23, #8]              // x1
    str x1, [x22, #-8]!
    mov x20, x0
    NEXT

// ============================================================================
// Arithmetic
// ============================================================================
XPLUS:
    ldr x0, [x22], #8
    add x20, x20, x0
    NEXT

XMINUS:
    ldr x0, [x22], #8
    sub x20, x0, x20
    NEXT

XSTAR:
    ldr x0, [x22], #8
    mul x20, x20, x0
    NEXT

XSLASH:
    ldr x0, [x22], #8
    sdiv x20, x0, x20
    NEXT

XMOD:
    ldr x0, [x22], #8
    sdiv x1, x0, x20
    msub x20, x1, x20, x0
    NEXT

XSLMOD:
    ldr x0, [x22], #8
    sdiv x1, x0, x20
    msub x2, x1, x20, x0
    str x2, [x22, #-8]!
    mov x20, x1
    NEXT

XONEPLUS:
    add x20, x20, #1
    NEXT

XONEMINUS:
    sub x20, x20, #1
    NEXT

XNEGATE:
    neg x20, x20
    NEXT

XABS:
    cmp x20, #0
    csneg x20, x20, x20, ge
    NEXT

XMIN:
    ldr x0, [x22], #8
    cmp x0, x20
    csel x20, x0, x20, lt
    NEXT

XMAX:
    ldr x0, [x22], #8
    cmp x0, x20
    csel x20, x0, x20, gt
    NEXT

// ============================================================================
// Logic / Bitwise
// ============================================================================
XAND:
    ldr x0, [x22], #8
    and x20, x20, x0
    NEXT

XORR:
    ldr x0, [x22], #8
    orr x20, x20, x0
    NEXT

XXOR:
    ldr x0, [x22], #8
    eor x20, x20, x0
    NEXT

XINVERT:
    mvn x20, x20
    NEXT

XLSHIFT:
    ldr x0, [x22], #8
    lsl x20, x0, x20
    NEXT

XRSHIFT:
    ldr x0, [x22], #8
    lsr x20, x0, x20
    NEXT

// ============================================================================
// Comparison
// ============================================================================
// Comparisons return standard Forth flags: 0 (false) or -1 (true)
XEQUAL:
    ldr x0, [x22], #8
    cmp x0, x20
    csetm x20, eq
    NEXT

XNEQUAL:
    ldr x0, [x22], #8
    cmp x0, x20
    csetm x20, ne
    NEXT

XLESS:
    ldr x0, [x22], #8
    cmp x0, x20
    csetm x20, lt
    NEXT

XGREATER:
    ldr x0, [x22], #8
    cmp x0, x20
    csetm x20, gt
    NEXT

XULESS:
    ldr x0, [x22], #8
    cmp x0, x20
    csetm x20, lo
    NEXT

// U> ( u1 u2 -- flag )  unsigned greater
XUGREATER:
    ldr x0, [x22], #8              // u1
    cmp x0, x20
    csetm x20, hi
    NEXT

XZEQUAL:
    cmp x20, #0
    csetm x20, eq
    NEXT

XZLESS:
    cmp x20, #0
    csetm x20, lt
    NEXT

// 0<> ( x -- flag )
XZNOTEQUAL:
    cmp x20, #0
    csetm x20, ne
    NEXT

// 0> ( n -- flag )
XZGREATER:
    cmp x20, #0
    csetm x20, gt
    NEXT

// WITHIN ( n1|u1 n2|u2 n3|u3 -- flag )
// ANS: n2 <= n1 < n3, using unsigned wrap: (n1-n2) U< (n3-n2)
XWITHIN:
    ldr x2, [x22], #8              // n2
    ldr x1, [x22], #8              // n1
    // x20 = n3
    sub x1, x1, x2                 // n1 - n2
    sub x20, x20, x2               // n3 - n2
    cmp x1, x20
    csetm x20, lo
    NEXT

// TRUE is all-bits-set (-1) per standard Forth
XTRUE:
    DPUSH
    mov x20, #-1
    NEXT

XFALSE:
    DPUSH
    mov x20, #0
    NEXT

// ============================================================================
// Memory
// ============================================================================
XFETCH:
    ldr x20, [x20]
    NEXT

// ! ( x addr -- ) store x at addr  [TOS=addr, second=x]
XSTORE:
    ldr x0, [x22], #8      // x0 = value
    str x0, [x20]          // *addr = value
    ldr x20, [x22], #8
    NEXT

XCFETCH:
    ldrb w20, [x20]
    NEXT

// C! ( char addr -- ) store char at addr
XCSTORE:
    ldr x0, [x22], #8      // x0 = char
    strb w0, [x20]         // *addr = char
    ldr x20, [x22], #8
    NEXT

XPLUSSTORE:
    ldr x0, [x22], #8
    ldr x1, [x20]
    add x1, x1, x0
    str x1, [x20]
    ldr x20, [x22], #8
    NEXT

XCELL:
    DPUSH
    mov x20, #8
    NEXT

XCELLS:
    lsl x20, x20, #3
    NEXT

XBL:
    DPUSH
    mov x20, #32
    NEXT

// ============================================================================
// I/O
// ============================================================================
// Helpers (_putchar etc.) only touch x0-x18/x29/x30; Darwin svc preserves
// x19-x28. We still SAVE_VM around bl so a future helper cannot clobber the VM.
XEMIT:
    mov x0, x20
    ldr x20, [x22], #8
    SAVE_VM
    bl _putchar
    RESTORE_VM
    NEXT

XKEY:
    SAVE_VM
    bl _getchar
    // char in x0; restore VM then push
    RESTORE_VM
    DPUSH               // also does mov x20, x0
    NEXT

// KEY? ( -- flag )  true if a character is available (does not read it)
XKEYQ:
    SAVE_VM
    adrp x1, key_q_hook@page
    add  x1, x1, key_q_hook@pageoff
    ldr  x1, [x1]
    cbz  x1, 1f
    blr  x1                        // int (*)(void) → non-zero if ready
    b    2f
1:
    mov  x0, #0
2:
    RESTORE_VM
    str  x20, [x22, #-8]!
    cmp  x0, #0
    csetm x20, ne                  // Forth true = -1
    NEXT

XCR:
    SAVE_VM
    mov x0, #10
    bl _putchar
    RESTORE_VM
    NEXT

XDOT:
    mov x0, x20
    ldr x20, [x22], #8
    SAVE_VM
    bl _print_signed
    mov x0, #32
    bl _putchar
    RESTORE_VM
    NEXT

XUDOT:
    mov x0, x20
    ldr x20, [x22], #8
    SAVE_VM
    bl _print_unsigned
    RESTORE_VM
    NEXT

XDOTS:
    SAVE_VM
    bl _print_dots
    RESTORE_VM
    NEXT

// .( ( -- ) IMMEDIATE — parse until ')' and TYPE (Core Ext). Boot CODE so AutoLoad
// works even if high-level forth_init aborts before the colon definition of .(.
XDOTPAREN:
    mov  w7, #41                   // ')'
    stp  x29, x30, [sp, #-16]!
    bl   _parse_quote              // → x2=c-addr, x5=u
    mov  x0, x2
    mov  x1, x5
    ldp  x29, x30, [sp], #16
    str  x20, [x22, #-8]!
    str  x0, [x22, #-8]!           // addr under
    mov  x20, x1                   // u TOS
    b    XTYPE

// TYPE ( addr u -- ) write u bytes at addr to stdout (host emit hook when set)
XTYPE:
    mov x2, x20            // x2 = u (length)
    ldr x1, [x22], #8      // x1 = addr
    ldr x20, [x22], #8
    cbz x2, _type_done
    SAVE_VM
    mov x0, x1
    mov x1, x2
    bl _write_stdout
    RESTORE_VM
_type_done:
    NEXT

// ============================================================================
// Control Flow
// ============================================================================
XBranch:
    ldr x0, [x19]
    add x19, x19, x0
    NEXT

X0Branch:
    cbz x20, _0br_true
    ldr x20, [x22], #8
    add x19, x19, #8
    NEXT
_0br_true:
    ldr x20, [x22], #8
    ldr x0, [x19]
    add x19, x19, x0
    NEXT

XLit:
    str x20, [x22, #-8]!
    ldr x20, [x19], #8
    NEXT

// ============================================================================
// Compilation Primitives
// ============================================================================

// DP ( -- a-addr )  address of the dictionary pointer cell (ANS-style)
XDP:
    str x20, [x22, #-8]!
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    mov x20, x0
    NEXT

// HERE ( -- addr ) push current dictionary pointer (also : HERE DP @ ;)
XHERE:
    DPUSH
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x20, [x0]
    NEXT

// ALLOT ( n -- ) advance HERE by n bytes
// Bounds-check against logical dict end (user_dict_size_cell); grow via GROWMEMORYMB.
XALLOT:
    mov x0, x20                    // n
    ldr x20, [x22], #8
    adrp x1, here_ptr@page
    add x1, x1, here_ptr@pageoff
    ldr x2, [x1]                   // HERE
    add x3, x2, x0                 // candidate HERE
    // lower bound = start of user dictionary
    adrp x4, user_dict_area@page
    add x4, x4, user_dict_area@pageoff
    cmp x3, x4
    b.lo _allot_under
    // upper bound = start + logical size
    adrp x5, user_dict_size_cell@page
    add x5, x5, user_dict_size_cell@pageoff
    ldr x5, [x5]
    add x5, x4, x5                 // end
    cmp x3, x5
    b.hi _allot_over
    str x3, [x1]
    NEXT
_allot_under:
    adrp x0, str_allot_under@page
    add  x0, x0, str_allot_under@pageoff
    b    _allot_fail
_allot_over:
    adrp x0, str_allot_over@page
    add  x0, x0, str_allot_over@pageoff
_allot_fail:
    // print message via host emit, then abort to QUIT
    bl   _print_string_svc
    b    _error_abandon

// , ( x -- ) compile cell at HERE
XCOMMA:
    mov x0, x20
    ldr x20, [x22], #8
    bl _compile_cell
    NEXT

// FIND ( c-addr -- c-addr 0 | xt 1 | xt -1 )  ANS Core
// c-addr is a counted string. 1 = immediate, -1 = non-immediate.
XFIND:
    mov x2, x20                 // c-addr (counted)
    ldrb w1, [x2]               // u = count
    add x0, x2, #1              // address of name chars
    bl _find_word
    cbz x0, _xfind_not
    // x0 = CFA, x1 = FLAGS; IMM = bit 63
    tst x1, x1                  // set N from MSB? use explicit
    mov x2, #1
    lsl x2, x2, #63
    tst x1, x2
    mov x4, #1
    mov x5, #-1
    csel x4, x4, x5, ne         // immediate -> 1, else -1
    mov x20, x0                 // xt = CFA
    str x20, [x22, #-8]!
    mov x20, x4                 // flag
    NEXT
_xfind_not:
    str x20, [x22, #-8]!        // c-addr under 0
    mov x20, #0
    NEXT

// SEARCH-WORDLIST ( c-addr u wid -- 0 | xt 1 | xt -1 )
// Find name in a single wordlist. c-addr is character address (not counted).
// Stack in:  ... PREV  c-addr  u  wid(TOS)
// miss out:  ... PREV  0
// hit out:   ... PREV  xt  flag   (flag 1=immediate, -1=normal)
XSEARCH_WORDLIST:
    mov  x9, x20                   // wid
    ldr  x8, [x22], #8             // u
    ldr  x7, [x22], #8             // c-addr → [x22]=PREV under
    cbz  x9, _swl_zero
    cbz  x8, _swl_zero
    ldr  x21, [x9]                 // latest CFA in this wordlist
_swl_loop:
    cbz  x21, _swl_zero
    ldr  x2, [x21, #-8]            // FLAGS
    and  x3, x2, #0xFFFFFFFF       // NFA_OFF
    sub  x4, x21, x3               // NFA
    ldrb w3, [x4], #1              // name length
    cmp  x3, x8
    b.ne _swl_next
    mov  x5, #0
_swl_cmp:
    cmp  x5, x8
    b.hs _swl_match
    ldrb w6, [x4, x5]
    ldrb w7, [x7, x5]
    cmp  w7, #'a'
    b.lo 1f
    cmp  w7, #'z'
    b.hi 1f
    sub  w7, w7, #32
1:
    cmp  w6, w7
    b.ne _swl_next
    add  x5, x5, #1
    b    _swl_cmp
_swl_match:
    mov  x2, #1
    lsl  x2, x2, #63
    ldr  x1, [x21, #-8]
    tst  x1, x2
    mov  x4, #1
    mov  x5, #-1
    csel x4, x4, x5, ne            // 1=imm, -1=normal
    str  x21, [x22, #-8]!          // push xt (PREV stays under)
    mov  x20, x4
    NEXT
_swl_next:
    ldr  x21, [x21, #-16]          // LFA at CFA-16
    b    _swl_loop
_swl_zero:
    mov  x20, #0
    NEXT

// ' ( "name" -- xt )  xt = CFA
XTICK:
    bl _next_word
    cbz x1, _tick_fail
    bl _find_word
    cbz x0, _tick_fail
    DPUSH
    mov x20, x0                 // CFA
    NEXT
_tick_fail:
    // Must use emit_hook path (not raw write) so the SwiftUI console shows it.
    // word_scratch is still the failed name (NUL-terminated by _next_word).
    bl   _report_undefined
    b    _do_quit

// EXECUTE ( xt -- )  xt = CFA
XEXECUTE:
    mov x21, x20                   // W = CFA
    ldr x20, [x22], #8
    ldr x1, [x21]                  // code at CFA
    br x1

// LITERAL ( x -- ) immediate: compile LIT + value
// Use C stack for temp — never the Forth return stack (x23), which may hold
// DOCOL frames when LITERAL runs inside an immediate colon word (e.g. ELSE).
XLITERAL:
    stp x29, x30, [sp, #-16]!
    str x20, [sp, #-16]!           // save literal value
    // Compile LIT entry address
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    // Compile the literal value
    ldr x0, [sp], #16
    bl _compile_cell
    ldr x20, [x22], #8             // drop original TOS (value consumed)
    ldp x29, x30, [sp], #16
    NEXT

// IMMEDIATE ( -- ) mark last defined word in CURRENT wordlist as immediate
XIMMEDIATE:
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    ldr  x0, [x0]                  // latest CFA in CURRENT
    b    2f
1:
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    ldr  x0, [x0]
2:
    cbz  x0, 3f
    ldr  x1, [x0, #-8]             // FLAGS
    mov  x2, #1
    lsl  x2, x2, #63               // FLAG_IMM bit 63
    orr  x1, x1, x2
    str  x1, [x0, #-8]
3:
    NEXT

// SETDOC ( c-addr u -- )  pending help for next : / CREATE / :NONAME
// Skips leading blanks so DOC" text" works with a space after DOC".
XSETDOC:
    mov x1, x20                    // u
    ldr x0, [x22], #8              // c-addr
    ldr x20, [x22], #8
1:
    cbz x1, 2f
    ldrb w2, [x0]
    cmp w2, #32
    b.eq 3f
    cmp w2, #9
    b.ne 2f
3:
    add x0, x0, #1
    sub x1, x1, #1
    b 1b
2:
    adrp x2, pending_help_addr@page
    add x2, x2, pending_help_addr@pageoff
    str x0, [x2]
    adrp x2, pending_help_len@page
    add x2, x2, pending_help_len@pageoff
    str x1, [x2]
    NEXT

// : ( "name" -- ) start colon definition
XCOLON:
    adrp x0, noname_xt@page
    add x0, x0, noname_xt@pageoff
    str xzr, [x0]
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    bl _next_word
    cbz x1, _colon_fail
    mov x19, x0
    mov x20, x1
    mov x0, x19
    mov x1, x20
    bl _warn_redef
    // name x19/x20, help from pending (or empty), code=DOCOL
    bl _take_pending_help          // x2/x3 help (clobbers x0/x1)
    mov x0, x19                    // restore name
    mov x1, x20
    adrp x4, DOCOL@page
    add x4, x4, DOCOL@pageoff
    mov x5, #0
    bl _header_build
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    mov x1, #1
    str x1, [x0]
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    NEXT
_colon_fail:
    adrp x0, str_quest@page
    add  x0, x0, str_quest@pageoff
    mov  x1, #2
    bl   _write_stdout
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _do_quit

// :NONAME
// :NONAME ( -- ) start nameless colon definition; ; leaves xt
XNONAME:
    // empty name + pending/empty help + DOCOL
    stp x29, x30, [sp, #-16]!
    bl _take_pending_help          // x2/x3 = help
    adrp x0, boot_h_empty@page
    add x0, x0, boot_h_empty@pageoff
    mov x1, #0                     // empty name
    adrp x4, DOCOL@page
    add x4, x4, DOCOL@pageoff
    mov x5, #0
    bl _header_build
    ldp x29, x30, [sp], #16
    adrp x1, noname_xt@page
    add x1, x1, noname_xt@pageoff
    str x0, [x1]
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    mov x1, #1
    str x1, [x0]
    NEXT

// ; ( -- ) immediate: end colon definition; after :NONAME leaves xt
XSEMI:
    // Compile EXIT entry address
    adrp x0, cfa_exit@page
    add x0, x0, cfa_exit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    // Clear compile-time local name table
    bl _local_compile_reset
    // Set state to interpret mode
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    str xzr, [x0]
    // :NONAME → leave xt
    adrp x0, noname_xt@page
    add x0, x0, noname_xt@pageoff
    ldr x1, [x0]
    cbz x1, _semi_done
    str xzr, [x0]
    str x20, [x22, #-8]!
    mov x20, x1
_semi_done:
    NEXT

// CREATE ( "name" -- ) header with DOVAR; does_ip at CFA+8, PFA at CFA+16
XCREATE:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    bl _next_word
    cbz x1, _create_fail
    mov x19, x0
    mov x20, x1
    mov x0, x19
    mov x1, x20
    bl _warn_redef
    bl _take_pending_help          // x2/x3 help (clobbers x0/x1)
    mov x0, x19
    mov x1, x20
    adrp x4, DOVAR@page
    add x4, x4, DOVAR@pageoff
    mov x5, #0
    bl _header_build               // HERE = CFA+8
    // reserve does_ip cell (0); user PFA follows
    adrp x1, here_ptr@page
    add x1, x1, here_ptr@pageoff
    ldr x0, [x1]
    str xzr, [x0], #8
    str x0, [x1]
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    NEXT
_create_fail:
    adrp x0, str_quest@page
    add  x0, x0, str_quest@pageoff
    mov  x1, #2
    bl   _write_stdout
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    b _do_quit

// ============================================================================
// Interpreter Words
// ============================================================================
XSTATE:
    DPUSH
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    mov x20, x0
    NEXT

XBASE:
    DPUSH
    adrp x0, base_var@page
    add x0, x0, base_var@pageoff
    mov x20, x0
    NEXT

// BLK / SCR / BLOCK-FILE — system variables for the Block word set
XBLK:
    DPUSH
    adrp x0, blk_var@page
    add x0, x0, blk_var@pageoff
    mov x20, x0
    NEXT

XSCR:
    DPUSH
    adrp x0, scr_var@page
    add x0, x0, scr_var@pageoff
    mov x20, x0
    NEXT

XBLOCK_FILE:
    DPUSH
    adrp x0, block_file_var@page
    add x0, x0, block_file_var@pageoff
    mov x20, x0
    NEXT

XBLOCK_BUF:
    DPUSH
    adrp x0, block_buf@page
    add x0, x0, block_buf@pageoff
    mov x20, x0
    NEXT

XBLOCK_NR:
    DPUSH
    adrp x0, block_nr@page
    add x0, x0, block_nr@pageoff
    mov x20, x0
    NEXT

XBLOCK_UPD:
    DPUSH
    adrp x0, block_upd@page
    add x0, x0, block_upd@pageoff
    mov x20, x0
    NEXT

XRBRA:
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    mov x1, #1
    str x1, [x0]
    NEXT

XLBRA:
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    str xzr, [x0]
    NEXT

XBYE:
    b _quit_exit

// FROMLIB / FROM-LIBRARY ( -- )  arm host path resolve to Resources/Library
XFROMLIB:
    adrp x0, fromlib_hook@page
    add  x0, x0, fromlib_hook@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    SAVE_VM
    blr  x0
    RESTORE_VM
1:
    NEXT

// CHDIR ( -- )  optional name: change cwd; bare → host folder picker (TZForth-style)
XCHDIR:
    bl _next_word                  // x0=scratch, x1=len (0 if bare)
    // Preserve bare/named in x25 before SAVE_VM (x1 is not VM-saved)
    mov  x25, x1
    SAVE_VM
    adrp x2, chdir_hook@page
    add  x2, x2, chdir_hook@pageoff
    ldr  x9, [x2]
    cbz  x9, 1f
    mov  x1, x25                   // path len (0 = bare dialog)
    cbz  x1, 2f
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    b    3f
2:
    mov  x0, #0                    // bare: no path (do not pass stale scratch)
    mov  x1, #0
3:
    blr  x9
1:
    RESTORE_VM
    NEXT

// PWD ( -- )  print logical cwd via host
XPWD:
    adrp x0, pwd_hook@page
    add  x0, x0, pwd_hook@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    SAVE_VM
    blr  x0
    RESTORE_VM
1:
    NEXT

// DIR ( -- )  optional path/filespec; bare lists cwd (FROMLIB → Library)
XDIR:
    bl _next_word
    mov  x25, x1
    SAVE_VM
    adrp x2, dir_hook@page
    add  x2, x2, dir_hook@pageoff
    ldr  x9, [x2]
    cbz  x9, 1f
    mov  x1, x25
    cbz  x1, 2f
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    b    3f
2:
    mov  x0, #0
    mov  x1, #0
3:
    blr  x9
1:
    RESTORE_VM
    NEXT

// EDIT ( -- ) name|dialog  open in system text editor (TZForth-style)
// Bare → open panel; named (or "quoted path") → resolve, open, chdir to folder.
// FROMLIB EDIT resolves under Library without permanently changing session cwd.
XEDIT:
    bl   _next_filespec            // x25=len (0 = bare); word_scratch if named
    SAVE_VM
    adrp x2, edit_hook@page
    add  x2, x2, edit_hook@pageoff
    ldr  x9, [x2]
    cbz  x9, 1f
    mov  x1, x25
    cbz  x1, 2f
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    b    3f
2:
    mov  x0, #0
    mov  x1, #0
3:
    blr  x9
1:
    RESTORE_VM
    NEXT

// ============================================================================
// File load: INCLUDE / FLOAD / INCLUDED / REQUIRED / REQUIRE / .INCLUDED
// ============================================================================
// ANS-shaped:
//   INCLUDED  ( c-addr u -- )  always load named file (string on stack)
//   REQUIRED  ( c-addr u -- )  load once (registry; prefers absolute path keys)
//   REQUIRE   ( "name" -- )    high-level: PARSE-NAME REQUIRED
//   INCLUDE   ( "name"|bare|"quoted path" -- ) always load
//   FLOAD     alias of INCLUDE
//   .INCLUDED ( -- )           list load-once registry
//
// Registry keys: after a successful host load, the absolute standardized path
// (from last_load_key_hook) is registered. REQUIRED resolves the name via
// resolve_key_hook first so FROMLIB FLOAD and later REQUIRE match.
// ============================================================================
.equ INCL_MAX, 64
.equ INCL_NAME, 256

// INCLUDE / FLOAD ( "filename" | bare | "quoted path" -- )  always load
XINCLUDE:
    bl   _next_filespec            // x25=len; word_scratch filled (0 = bare)
    b    _include_with_len

// INCLUDED ( c-addr u -- )  always load from string
XINCLUDED:
    mov  x1, x20                   // u
    ldr  x0, [x22], #8             // c-addr
    ldr  x20, [x22], #8
    bl   _copy_to_word_scratch
    b    _include_with_len

// REQUIRED ( c-addr u -- )  load once
XREQUIRED:
    mov  x1, x20
    ldr  x0, [x22], #8
    ldr  x20, [x22], #8
    cbz  x1, _required_empty
    bl   _copy_to_word_scratch     // typed name in word_scratch, x25=len
    // Try host absolute resolve first (consumes FROMLIB)
    bl   _resolve_abs_key          // x0=1 if absolute key now in pending/scratch
    // Check registry (pending has key to check)
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    adrp x1, include_name_len@page
    add  x1, x1, include_name_len@pageoff
    ldr  x1, [x1]
    cbz  x1, 1f
    bl   _included_find_buf
    cbnz x0, _require_skip
1:
    // Also check original typed name (if different / no resolve)
    // word_scratch still holds load path (absolute if resolve succeeded)
    bl   _include_save_name
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    adrp x1, include_name_len@page
    add  x1, x1, include_name_len@pageoff
    ldr  x1, [x1]
    bl   _included_find_buf
    cbnz x0, _require_skip
    b    _include_with_len

_required_empty:
    adrp x0, str_quest@page
    add  x0, x0, str_quest@pageoff
    mov  x1, #2
    bl   _write_stdout
    b    _error_abandon

_require_skip:
    bl   _fromlib_clear
    NEXT

// .INCLUDED ( -- ) list registry
XDOT_INCLUDED:
    SAVE_VM
    adrp x0, str_included_hdr@page
    add  x0, x0, str_included_hdr@pageoff
    bl   _print_string_svc
    adrp x0, included_count@page
    add  x0, x0, included_count@pageoff
    ldr  x19, [x0]                 // count
    cbz  x19, 8f
    mov  x20, #0                   // i
1:
    cmp  x20, x19
    b.hs 9f
    mov  x0, #32
    bl   _putchar
    mov  x0, #32
    bl   _putchar
    mov  x0, #INCL_NAME
    mul  x0, x0, x20
    adrp x1, included_names@page
    add  x1, x1, included_names@pageoff
    add  x1, x1, x0
    ldrb w2, [x1], #1              // len; x1 → chars
    // TYPE len bytes
    mov  x3, #0
2:
    cmp  x3, x2
    b.hs 3f
    ldrb w0, [x1, x3]
    stp  x1, x2, [sp, #-16]!
    stp  x3, x20, [sp, #-16]!
    bl   _putchar
    ldp  x3, x20, [sp], #16
    ldp  x1, x2, [sp], #16
    add  x3, x3, #1
    b    2b
3:
    mov  x0, #10
    bl   _putchar
    add  x20, x20, #1
    b    1b
8:
    adrp x0, str_included_none@page
    add  x0, x0, str_included_none@pageoff
    bl   _print_string_svc
9:
    RESTORE_VM
    NEXT

// Shared loader. x25 = path len; name in word_scratch when x25 != 0.
_include_with_len:
    cbnz x25, 1f
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    str  xzr, [x0]
    b    2f
1:
    bl   _include_save_name        // typed / resolved path as provisional key
2:
    SAVE_VM
    stp  x25, x26, [sp, #-16]!
    mov  x26, x25

    adrp x0, load_file_hook@page
    add  x0, x0, load_file_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, _include_no_hook

    mov  x1, x26
    cbz  x1, 3f
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    b    4f
3:
    mov  x0, #0
    mov  x1, #0
4:
    sub  sp, sp, #16
    mov  x2, sp
    add  x3, sp, #8
    str  xzr, [sp]
    str  xzr, [sp, #8]
    blr  x9
    ldr  x25, [sp]
    ldr  x26, [sp, #8]
    add  sp, sp, #16
    cbnz x0, _include_fail_restore
    cbz  x25, _include_fail_restore
    bl   _push_source
    mov  x0, x25
    mov  x1, x26
    bl   _set_source
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    mov  x1, #1
    str  x1, [x0]
    // Prefer absolute last-load key for registry
    bl   _apply_last_load_key
    bl   _included_register_pending
    ldp  x25, x26, [sp], #16
    RESTORE_VM
    NEXT

_include_no_hook:
    cbnz x26, _include_syscall
    b    _include_fail_restore

_include_syscall:
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    mov  x1, #0
    mov  x2, #0
    mov  x16, #5
    svc  #0x80
    b.cs _include_fail_restore
    mov  x25, x0

    mov  x0, x25
    adrp x1, file_buffer@page
    add  x1, x1, file_buffer@pageoff
    mov  x2, #65536
    mov  x16, #3
    svc  #0x80
    mov  x26, x0

    mov  x0, x25
    mov  x16, #6
    svc  #0x80

    cmp  x26, #0
    b.le _include_done_restore
    adrp x0, file_buffer@page
    add  x0, x0, file_buffer@pageoff
    add  x0, x0, x26
    strb wzr, [x0]

_include_done_restore:
    bl   _push_source
    adrp x0, file_buffer@page
    add  x0, x0, file_buffer@pageoff
    mov  x1, x26
    cmp  x1, #0
    b.ge 2f
    mov  x1, #0
2:
    bl   _set_source
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    mov  x1, #1
    str  x1, [x0]
    bl   _included_register_pending
    ldp  x25, x26, [sp], #16
    RESTORE_VM
    NEXT

_include_fail_restore:
    ldp  x25, x26, [sp], #16
    RESTORE_VM
_include_fail:
    b    _error_abandon

// _next_filespec: like _next_word but supports "quoted paths with spaces"
// → x25=len, word_scratch filled; x25=0 if bare/EOF
_next_filespec:
    stp  x29, x30, [sp, #-16]!
    stp  x19, x20, [sp, #-16]!
    bl   _cursor_load
    mov  x19, x0
    bl   _source_end
    mov  x20, x0
1:  // skip blanks
    cmp  x19, x20
    b.hs 8f
    ldrb w0, [x19]
    cbz  w0, 8f
    cmp  w0, #32
    b.eq 2f
    cmp  w0, #9
    b.eq 2f
    cmp  w0, #10
    b.eq 2f
    cmp  w0, #13
    b.eq 2f
    b    3f
2:
    add  x19, x19, #1
    b    1b
3:
    cmp  w0, #'"'
    b.eq 4f
    // unquoted: set cursor then _next_word (must not restore LR before bl)
    mov  x0, x19
    bl   _cursor_store
    bl   _next_word
    mov  x25, x1
    ldp  x19, x20, [sp], #16
    ldp  x29, x30, [sp], #16
    ret
4:  // quoted
    add  x19, x19, #1              // skip opening "
    mov  x1, x19                   // start
5:
    cmp  x19, x20
    b.hs 6f
    ldrb w0, [x19]
    cbz  w0, 6f
    cmp  w0, #'"'
    b.eq 6f
    add  x19, x19, #1
    b    5b
6:
    sub  x2, x19, x1               // len
    cmp  x19, x20
    b.hs 7f
    ldrb w0, [x19]
    cmp  w0, #'"'
    b.ne 7f
    add  x19, x19, #1              // skip closing "
7:
    mov  x0, x19
    stp  x1, x2, [sp, #-16]!
    bl   _cursor_store
    ldp  x0, x1, [sp], #16         // src, len
    bl   _copy_to_word_scratch     // x25=len
    ldp  x19, x20, [sp], #16
    ldp  x29, x30, [sp], #16
    ret
8:
    mov  x0, x19
    bl   _cursor_store
    mov  x25, #0
    ldp  x19, x20, [sp], #16
    ldp  x29, x30, [sp], #16
    ret

// _resolve_abs_key: if resolve_key_hook set, replace word_scratch/x25 with absolute
// path and fill include_name_pending. Returns via x0=1 if absolute available.
// Leaves typed name in word_scratch if resolve fails.
_resolve_abs_key:
    stp  x29, x30, [sp, #-16]!
    adrp x0, resolve_key_hook@page
    add  x0, x0, resolve_key_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, 9f
    // provisional: save typed into pending for lookup even if resolve fails
    bl   _include_save_name
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    mov  x1, x25
    adrp x2, include_name_pending@page
    add  x2, x2, include_name_pending@pageoff
    mov  x3, #INCL_NAME
    sub  sp, sp, #16
    mov  x4, sp                    // out_len slot
    str  xzr, [sp]
    // args: path, path_len, out, out_max, out_len*
    // x0=path x1=len already; x2=out x3=max
    mov  x0, x0
    // reload path into x0
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    mov  x1, x25
    adrp x2, include_name_pending@page
    add  x2, x2, include_name_pending@pageoff
    mov  x3, #INCL_NAME - 1
    mov  x4, sp
    blr  x9
    ldr  x1, [sp]
    add  sp, sp, #16
    cbnz x0, 9f                    // fail
    cbz  x1, 9f
    // x1 = absolute len; host wrote absolute bytes into include_name_pending
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    str  x1, [x0]
    // copy absolute into word_scratch for the subsequent load
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    mov  x1, x1
    bl   _copy_to_word_scratch
    mov  x0, #1
    ldp  x29, x30, [sp], #16
    ret
9:
    // keep typed name in word_scratch / pending
    bl   _include_save_name
    mov  x0, #0
    ldp  x29, x30, [sp], #16
    ret

// _apply_last_load_key: if last_load_key_hook, overwrite pending with absolute
_apply_last_load_key:
    stp  x29, x30, [sp, #-16]!
    adrp x0, last_load_key_hook@page
    add  x0, x0, last_load_key_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, 9f
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    mov  x1, #INCL_NAME - 1
    sub  sp, sp, #16
    mov  x2, sp
    str  xzr, [sp]
    blr  x9
    ldr  x1, [sp]
    add  sp, sp, #16
    cbnz x0, 9f
    cbz  x1, 9f
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    str  x1, [x0]
9:
    ldp  x29, x30, [sp], #16
    ret

// _fromlib_clear
_fromlib_clear:
    stp  x29, x30, [sp, #-16]!
    adrp x0, fromlib_clear_hook@page
    add  x0, x0, fromlib_clear_hook@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    blr  x0
1:
    ldp  x29, x30, [sp], #16
    ret

// _copy_to_word_scratch: x0=src, x1=len → word_scratch + NUL, x25=clamped len
_copy_to_word_scratch:
    mov  x25, x1
    cmp  x25, #INCL_NAME - 1
    b.ls 1f
    mov  x25, #INCL_NAME - 1
1:
    mov  x2, #511
    cmp  x25, x2
    csel x25, x2, x25, hi
    adrp x2, word_scratch@page
    add  x2, x2, word_scratch@pageoff
    mov  x3, #0
2:
    cmp  x3, x25
    b.hs 3f
    ldrb w4, [x0, x3]
    strb w4, [x2, x3]
    add  x3, x3, #1
    b    2b
3:
    strb wzr, [x2, x3]
    ret

// _include_save_name: word_scratch[0..x25) → include_name_pending + len
_include_save_name:
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    mov  x1, x25
    cmp  x1, #INCL_NAME - 1
    b.ls 1f
    mov  x1, #INCL_NAME - 1
1:
    str  x1, [x0]
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    adrp x2, include_name_pending@page
    add  x2, x2, include_name_pending@pageoff
    mov  x3, #0
2:
    cmp  x3, x1
    b.hs 3f
    ldrb w4, [x0, x3]
    strb w4, [x2, x3]
    add  x3, x3, #1
    b    2b
3:
    strb wzr, [x2, x3]
    ret

// _included_find_buf: x0=buf, x1=len → x0=1 if registered (case-insensitive)
_included_find_buf:
    stp  x19, x20, [sp, #-16]!
    stp  x21, x22, [sp, #-16]!
    mov  x19, x0
    mov  x20, x1
    adrp x0, included_count@page
    add  x0, x0, included_count@pageoff
    ldr  x21, [x0]
    mov  x22, #0
1:
    cmp  x22, x21
    b.hs 8f
    mov  x0, #INCL_NAME
    mul  x0, x0, x22
    adrp x1, included_names@page
    add  x1, x1, included_names@pageoff
    add  x1, x1, x0
    ldrb w2, [x1], #1
    cmp  x2, x20
    b.ne 3f
    mov  x3, #0
2:
    cmp  x3, x20
    b.hs 9f
    ldrb w4, [x1, x3]
    ldrb w5, [x19, x3]
    cmp  w4, #'a'
    b.lo 21f
    cmp  w4, #'z'
    b.hi 21f
    sub  w4, w4, #32
21:
    cmp  w5, #'a'
    b.lo 22f
    cmp  w5, #'z'
    b.hi 22f
    sub  w5, w5, #32
22:
    cmp  w4, w5
    b.ne 3f
    add  x3, x3, #1
    b    2b
3:
    add  x22, x22, #1
    b    1b
8:
    mov  x0, #0
    b    10f
9:
    mov  x0, #1
10:
    ldp  x21, x22, [sp], #16
    ldp  x19, x20, [sp], #16
    ret

// _included_register_pending: add include_name_pending if new
_included_register_pending:
    stp  x29, x30, [sp, #-16]!
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    ldr  x1, [x0]
    cbz  x1, 9f
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    bl   _included_find_buf
    cbnz x0, 9f
    adrp x0, included_count@page
    add  x0, x0, included_count@pageoff
    ldr  x2, [x0]
    cmp  x2, #INCL_MAX
    b.hs 9f
    mov  x3, #INCL_NAME
    mul  x3, x3, x2
    adrp x4, included_names@page
    add  x4, x4, included_names@pageoff
    add  x4, x4, x3
    adrp x0, include_name_len@page
    add  x0, x0, include_name_len@pageoff
    ldr  x1, [x0]
    cmp  x1, #INCL_NAME - 1
    b.ls 1f
    mov  x1, #INCL_NAME - 1
1:
    strb w1, [x4], #1
    adrp x0, include_name_pending@page
    add  x0, x0, include_name_pending@pageoff
    mov  x3, #0
2:
    cmp  x3, x1
    b.hs 3f
    ldrb w5, [x0, x3]
    strb w5, [x4, x3]
    add  x3, x3, #1
    b    2b
3:
    adrp x0, included_count@page
    add  x0, x0, included_count@pageoff
    ldr  x2, [x0]
    add  x2, x2, #1
    str  x2, [x0]
9:
    ldp  x29, x30, [sp], #16
    ret

// ============================================================================
// High-Level Forth Support Primitives
// ============================================================================

// LATEST ( -- addr ) push address of latest_var (FORTH wordlist head cell)
XLATEST:
    DPUSH
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    mov  x20, x0
    NEXT

// CURRENT ( -- addr ) variable: compilation wordlist wid
XCURRENT:
    DPUSH
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    mov  x20, x0
    NEXT

// WORDLIST ( -- wid ) allot aligned head cell = 0
XWORDLIST:
    adrp x0, here_ptr@page
    add  x0, x0, here_ptr@pageoff
    ldr  x1, [x0]
    // align HERE
    add  x1, x1, #7
    and  x1, x1, #~7
    mov  x2, x1                    // wid = head cell addr
    str  xzr, [x1], #8
    str  x1, [x0]
    DPUSH
    mov  x20, x2
    NEXT

// FORTH-WORDLIST ( -- wid )
XFORTH_WORDLIST:
    DPUSH
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    mov  x20, x0
    NEXT

// GET-CURRENT ( -- wid )
XGET_CURRENT:
    DPUSH
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    ldr  x20, [x0]
    NEXT

// SET-CURRENT ( wid -- )
XSET_CURRENT:
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    str  x20, [x0]
    ldr  x20, [x22], #8
    NEXT

// GET-ORDER ( -- widn ... wid1 n )
XGET_ORDER:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x1, [x0]                  // n
    adrp x2, search_order@page
    add  x2, x2, search_order@pageoff
    // push order[n-1] ... order[0] then n
    mov  x3, x1
1:
    cbz  x3, 2f
    sub  x3, x3, #1
    ldr  x4, [x2, x3, lsl #3]
    str  x20, [x22, #-8]!
    mov  x20, x4
    b    1b
2:
    str  x20, [x22, #-8]!
    mov  x20, x1
    NEXT

// SET-ORDER ( widn ... wid1 n -- )  n=-1 → ONLY
XSET_ORDER:
    mov  x1, x20                   // n
    ldr  x20, [x22], #8
    cmp  x1, #-1
    b.eq XONLY
    cmp  x1, #0
    b.lt 1f
    cmp  x1, #8
    b.hi 1f
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    str  x1, [x0]
    adrp x2, search_order@page
    add  x2, x2, search_order@pageoff
    mov  x3, #0
2:
    cmp  x3, x1
    b.hs 3f
    str  x20, [x2, x3, lsl #3]
    ldr  x20, [x22], #8
    add  x3, x3, #1
    b    2b
3:
    NEXT
1:
    // invalid: leave empty-ish
    NEXT

// PUSH-ORDER ( wid -- ) prepend to search order
XPUSH_ORDER:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x1, [x0]
    cmp  x1, #8
    b.hs 1f
    adrp x2, search_order@page
    add  x2, x2, search_order@pageoff
    // shift up
    mov  x3, x1
2:
    cbz  x3, 3f
    sub  x3, x3, #1
    ldr  x4, [x2, x3, lsl #3]
    add  x5, x3, #1
    str  x4, [x2, x5, lsl #3]
    b    2b
3:
    str  x20, [x2]
    add  x1, x1, #1
    str  x1, [x0]
1:
    ldr  x20, [x22], #8
    NEXT

// DEFINITIONS ( -- ) CURRENT = search_order[0]
XDEFINITIONS:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    adrp x1, search_order@page
    add  x1, x1, search_order@pageoff
    ldr  x1, [x1]
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    str  x1, [x0]
1:
    NEXT

// ONLY ( -- ) search order = (FORTH-WORDLIST)
XONLY:
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    adrp x1, search_order@page
    add  x1, x1, search_order@pageoff
    str  x0, [x1]
    mov  x0, #1
    adrp x1, search_order_n@page
    add  x1, x1, search_order_n@pageoff
    str  x0, [x1]
    NEXT

// ALSO ( -- ) duplicate first search-order entry
XALSO:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x1, [x0]
    cbz  x1, 1f
    cmp  x1, #8
    b.hs 1f
    adrp x2, search_order@page
    add  x2, x2, search_order@pageoff
    ldr  x3, [x2]                  // top
    // shift
    mov  x4, x1
2:
    cbz  x4, 3f
    sub  x4, x4, #1
    ldr  x5, [x2, x4, lsl #3]
    add  x6, x4, #1
    str  x5, [x2, x6, lsl #3]
    b    2b
3:
    str  x3, [x2]
    add  x1, x1, #1
    str  x1, [x0]
1:
    NEXT

// PREVIOUS ( -- ) drop first search-order entry
XPREVIOUS:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x1, [x0]
    cmp  x1, #1
    b.ls 1f
    adrp x2, search_order@page
    add  x2, x2, search_order@pageoff
    mov  x3, #0
2:
    add  x4, x3, #1
    cmp  x4, x1
    b.hs 3f
    ldr  x5, [x2, x4, lsl #3]
    str  x5, [x2, x3, lsl #3]
    add  x3, x3, #1
    b    2b
3:
    sub  x1, x1, #1
    str  x1, [x0]
1:
    NEXT

// FORTH ( -- ) search_order[0] = FORTH-WORDLIST
XFORTH:
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    adrp x1, search_order@page
    add  x1, x1, search_order@pageoff
    str  x0, [x1]
    adrp x1, search_order_n@page
    add  x1, x1, search_order_n@pageoff
    ldr  x2, [x1]
    cbnz x2, 1f
    mov  x2, #1
    str  x2, [x1]
1:
    NEXT

// ORDER ( -- ) print search order and CURRENT (resolve VOCABULARY names)
XORDER:
    SAVE_VM
    adrp x0, str_search_order@page
    add  x0, x0, str_search_order@pageoff
    bl   _print_string_svc
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x19, [x0]
    adrp x20, search_order@page
    add  x20, x20, search_order@pageoff
    mov  x21, #0
1:
    cmp  x21, x19
    b.hs 2f
    ldr  x0, [x20, x21, lsl #3]    // wid
    bl   _print_wid_name
    mov  x0, #32
    bl   _putchar
    add  x21, x21, #1
    b    1b
2:
    mov  x0, #10
    bl   _putchar
    adrp x0, str_comp_wl@page
    add  x0, x0, str_comp_wl@pageoff
    bl   _print_string_svc
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    ldr  x0, [x0]
    bl   _print_wid_name
    mov  x0, #10
    bl   _putchar
    RESTORE_VM
    NEXT

// _print_wid_name: x0 = wid (wordlist head cell address)
// Prints FORTH, a VOCABULARY name (DODOES body == wid), or "wid".
_print_wid_name:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0                    // wid
    // FORTH wordlist?
    adrp x1, latest_var@page
    add  x1, x1, latest_var@pageoff
    cmp  x19, x1
    b.ne 1f
    adrp x0, str_forth_name@page
    add  x0, x0, str_forth_name@pageoff
    bl   _print_string_svc
    b    9f
1:
    // Scan FORTH chain for DODOES vocabulary whose PFA (CFA+16) == wid
    adrp x0, DODOES@page
    add  x0, x0, DODOES@pageoff
    mov  x22, x0                   // DODOES code addr
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    ldr  x21, [x0]                 // start CFA
2:
    cbz  x21, 8f
    ldr  x0, [x21]                 // code at CFA
    cmp  x0, x22
    b.ne 3f
    add  x0, x21, #16              // PFA = wordlist head for VOCABULARY
    cmp  x0, x19
    b.ne 3f
    // Found: print NFA name
    ldr  x0, [x21, #-8]            // FLAGS
    and  x0, x0, #0xFFFFFFFF       // NFA_OFF
    sub  x0, x21, x0               // NFA
    ldrb w1, [x0], #1              // count; x0 -> chars
    mov  x2, #0
4:
    cmp  x2, x1
    b.hs 9f
    ldrb w3, [x0, x2]
    // putchar
    stp  x0, x1, [sp, #-16]!
    stp  x2, x3, [sp, #-16]!
    mov  x0, x3
    bl   _putchar
    ldp  x2, x3, [sp], #16
    ldp  x0, x1, [sp], #16
    add  x2, x2, #1
    b    4b
3:
    ldr  x21, [x21, #-16]          // link
    b    2b
8:
    adrp x0, str_wid@page
    add  x0, x0, str_wid@pageoff
    bl   _print_string_svc
9:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret


// ============================================================================
// FORGET ( "name" -- ) — reclaim from name's CFA; prune ALL wordlist heads
// ============================================================================
// Finds name via search order (FIND). Refuses system/kernel words:
//   CFA < words_user_base (HERE after bootstrap; same fence as WORDS).
//   Fallback if fence unset: CFA < USER-DICT base.
// Rewinds HERE to the forgotten CFA. Prunes latest_var, current, search_order,
// and every VOCABULARY wordlist head found in the FORTH chain.
//
// Must SAVE_VM + forget_cut BSS: must not keep cut in x19 (IP for CODE words).
XFORGET:
    SAVE_VM
    bl   _next_word
    cbz  x1, 8f
    bl   _find_word
    cbz  x0, 9f
    // x0 = CFA (cut). Protect system dictionary (boot + forth_init_str).
    adrp x1, words_user_base@page
    add  x1, x1, words_user_base@pageoff
    ldr  x1, [x1]
    cbnz x1, 0f
    // Fence not set yet — never forget below physical dict base
    adrp x1, user_dict_area@page
    add  x1, x1, user_dict_area@pageoff
0:
    cmp  x0, x1
    b.lo 7f                        // protected (system word)
    // cut in BSS — free for entire routine (helpers clobber x0–x18)
    adrp x2, forget_cut@page
    add  x2, x2, forget_cut@pageoff
    str  x0, [x2]
    // HERE = cut
    adrp x1, here_ptr@page
    add  x1, x1, here_ptr@pageoff
    str  x0, [x1]
    // prune FORTH latest
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    adrp x1, forget_cut@page
    add  x1, x1, forget_cut@pageoff
    ldr  x1, [x1]
    bl   _prune_wid
    // prune CURRENT
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    adrp x1, forget_cut@page
    add  x1, x1, forget_cut@pageoff
    ldr  x1, [x1]
    bl   _prune_wid
1:
    // prune search_order entries
    adrp x2, search_order_n@page
    add  x2, x2, search_order_n@pageoff
    ldr  x2, [x2]
    adrp x3, search_order@page
    add  x3, x3, search_order@pageoff
    mov  x4, #0
2:
    cmp  x4, x2
    b.hs 3f
    ldr  x0, [x3, x4, lsl #3]
    cbz  x0, 21f
    adrp x1, forget_cut@page
    add  x1, x1, forget_cut@pageoff
    ldr  x1, [x1]
    stp  x2, x3, [sp, #-16]!
    stp  x4, xzr, [sp, #-16]!
    bl   _prune_wid
    ldp  x4, xzr, [sp], #16
    ldp  x2, x3, [sp], #16
21:
    add  x4, x4, #1
    b    2b
3:
    // Scan FORTH chain for DODOES vocabularies; prune their PFA (wid)
    adrp x0, DODOES@page
    add  x0, x0, DODOES@pageoff
    mov  x20, x0                   // DODOES code (TOS saved by SAVE_VM)
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    ldr  x21, [x0]                 // cfa walk
4:
    cbz  x21, 6f
    // Guard: CFA must be in user dict range (avoid following garbage links)
    adrp x0, user_dict_area@page
    add  x0, x0, user_dict_area@pageoff
    cmp  x21, x0
    b.lo 6f
    adrp x0, here_ptr@page
    add  x0, x0, here_ptr@pageoff
    ldr  x0, [x0]
    // After HERE=cut, chain heads are < cut; still allow walk of remaining dict
    // Use dict end (base+logical size) as upper bound for a valid CFA pointer
    adrp x1, user_dict_area@page
    add  x1, x1, user_dict_area@pageoff
    adrp x2, user_dict_size_cell@page
    add  x2, x2, user_dict_size_cell@pageoff
    ldr  x2, [x2]
    add  x1, x1, x2
    cmp  x21, x1
    b.hs 6f
    ldr  x0, [x21]
    cmp  x0, x20
    b.ne 5f
    add  x0, x21, #16              // wid = PFA
    adrp x1, forget_cut@page
    add  x1, x1, forget_cut@pageoff
    ldr  x1, [x1]
    stp  x20, x21, [sp, #-16]!
    bl   _prune_wid
    ldp  x20, x21, [sp], #16
5:
    ldr  x21, [x21, #-16]
    b    4b
6:
    RESTORE_VM
    NEXT
7:
    adrp x0, str_protected@page
    add  x0, x0, str_protected@pageoff
    bl   _print_string_svc
    RESTORE_VM
    NEXT
8:
    adrp x0, str_quest@page
    add  x0, x0, str_quest@pageoff
    mov  x1, #2
    bl   _write_stdout
    RESTORE_VM
    NEXT
9:
    bl   _report_undefined
    RESTORE_VM
    b    _error_abandon

// _prune_wid: x0 = wid (addr of head cell), x1 = cut CFA
// Unlink heads with CFA >= cut (newest-first chains grow with HERE).
_prune_wid:
    cbz  x0, 9f
1:
    ldr  x2, [x0]                  // head CFA
    cbz  x2, 9f
    cmp  x2, x1
    b.lo 9f
    ldr  x2, [x2, #-16]            // link
    str  x2, [x0]
    b    1b
9:
    ret

// ALLOCATE ( u -- a-addr ior )  libc malloc; ior 0 ok, -1 fail
// Host hook optional (same stack result). Never leave a null a-addr with ior 0.
XALLOCATE:
    adrp x0, host_tmp0@page
    add  x0, x0, host_tmp0@pageoff
    str  x20, [x0]                 // size
    SAVE_VM
    adrp x0, host_tmp0@page
    add  x0, x0, host_tmp0@pageoff
    ldr  x0, [x0]
    cbnz x0, 0f
    mov  x0, #1
0:
    // Always use libc malloc for reliability (host hook kept for future)
    bl   _malloc
    // x0 = ptr or 0
    adrp x1, host_tmp0@page
    add  x1, x1, host_tmp0@pageoff
    str  x0, [x1]
    mov  x2, #0                    // ior ok
    cbnz x0, 1f
    mov  x2, #-1
1:
    adrp x1, host_tmp1@page
    add  x1, x1, host_tmp1@pageoff
    str  x2, [x1]
    RESTORE_VM
    adrp x0, host_tmp0@page
    add  x0, x0, host_tmp0@pageoff
    ldr  x1, [x0]                  // a-addr
    adrp x0, host_tmp1@page
    add  x0, x0, host_tmp1@pageoff
    ldr  x2, [x0]                  // ior
    mov  x20, x1
    str  x20, [x22, #-8]!          // under: a-addr
    mov  x20, x2                   // TOS: ior
    NEXT

// FREE ( a-addr -- ior )
XFREE:
    adrp x0, host_tmp0@page
    add  x0, x0, host_tmp0@pageoff
    str  x20, [x0]
    SAVE_VM
    adrp x0, host_tmp0@page
    add  x0, x0, host_tmp0@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    bl   _free
1:
    RESTORE_VM
    mov  x20, #0                   // ior ok
    NEXT

// RESIZE ( a-addr1 u -- a-addr2 ior )  ANS Memory-Allocation
// a-addr1 may be 0 (like ALLOCATE). ior 0 ok, -1 fail (a-addr2 = a-addr1 on fail).
XRESIZE:
    // TOS = u, under = a-addr1
    mov  x1, x20                   // u
    ldr  x0, [x22], #8             // a-addr1
    // save for fail path
    adrp x2, host_tmp0@page
    add  x2, x2, host_tmp0@pageoff
    str  x0, [x2]                  // old ptr
    str  x1, [x2, #8]              // new size
    SAVE_VM
    adrp x2, host_tmp0@page
    add  x2, x2, host_tmp0@pageoff
    ldr  x0, [x2]
    ldr  x1, [x2, #8]
    cbnz x1, 0f
    mov  x1, #1                    // realloc(p,0) is free-ish; keep 1 byte
0:
    bl   _realloc                  // x0 = new ptr or 0
    adrp x1, host_tmp0@page
    add  x1, x1, host_tmp0@pageoff
    str  x0, [x1, #16]             // new ptr
    RESTORE_VM
    adrp x1, host_tmp0@page
    add  x1, x1, host_tmp0@pageoff
    ldr  x0, [x1, #16]             // new
    ldr  x2, [x1]                  // old
    cbnz x0, 1f
    // fail: leave old a-addr, ior -1
    mov  x20, x2
    str  x20, [x22, #-8]!
    mov  x20, #-1
    NEXT
1:
    mov  x20, x0
    str  x20, [x22, #-8]!
    mov  x20, #0
    NEXT

// BI-MUL ( a b r -- )
XBIMUL:
    adrp x3, host_tmp0@page
    add  x3, x3, host_tmp0@pageoff
    str  x20, [x3, #16]            // r at tmp2 — use three quads
    // host_tmp0,1,2 for a,b,r
    ldr  x1, [x22], #8
    ldr  x0, [x22], #8
    str  x0, [x3]                  // a
    str  x1, [x3, #8]              // b
    ldr  x20, [x22], #8
    SAVE_VM
    adrp x3, bi_mul_hook@page
    add  x3, x3, bi_mul_hook@pageoff
    ldr  x9, [x3]
    cbz  x9, 1f
    adrp x3, host_tmp0@page
    add  x3, x3, host_tmp0@pageoff
    ldr  x0, [x3]
    ldr  x1, [x3, #8]
    ldr  x2, [x3, #16]
    blr  x9
1:
    RESTORE_VM
    NEXT

// BI-DIVMOD ( num den quot rem work -- )
XBIDIVMOD:
    // TOS = work (ignored)
    ldr  x3, [x22], #8             // rem
    ldr  x2, [x22], #8             // quot
    ldr  x1, [x22], #8             // den
    ldr  x0, [x22], #8             // num
    ldr  x20, [x22], #8
    adrp x4, host_tmp0@page
    add  x4, x4, host_tmp0@pageoff
    str  x0, [x4]
    str  x1, [x4, #8]
    str  x2, [x4, #16]
    str  x3, [x4, #24]
    SAVE_VM
    adrp x0, bi_divmod_hook@page
    add  x0, x0, bi_divmod_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, 1f
    adrp x4, host_tmp0@page
    add  x4, x4, host_tmp0@pageoff
    ldr  x0, [x4]
    ldr  x1, [x4, #8]
    ldr  x2, [x4, #16]
    ldr  x3, [x4, #24]
    blr  x9                        // void (*)(num, den, quot, rem)
1:
    RESTORE_VM
    NEXT

// BI-ISQRT ( a r quot rem work t1 t2 -- )
XBIISQRT:
    // TOS = t2; discard t2,t1,work,rem,quot; keep a,r
    ldr  x0, [x22], #8             // t1
    ldr  x0, [x22], #8             // work
    ldr  x0, [x22], #8             // rem
    ldr  x0, [x22], #8             // quot
    ldr  x1, [x22], #8             // r
    ldr  x0, [x22], #8             // a
    ldr  x20, [x22], #8
    adrp x2, host_tmp0@page
    add  x2, x2, host_tmp0@pageoff
    str  x0, [x2]
    str  x1, [x2, #8]
    SAVE_VM
    adrp x0, bi_isqrt_hook@page
    add  x0, x0, bi_isqrt_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, 1f
    adrp x2, host_tmp0@page
    add  x2, x2, host_tmp0@pageoff
    ldr  x0, [x2]
    ldr  x1, [x2, #8]
    blr  x9                        // void (*)(a, r)
1:
    RESTORE_VM
    NEXT

// ============================================================================
// Locals (ANS-style minimal: {: … :}  TO  (LOCAL-INIT) (LOCAL@) (LOCAL!))
// Runtime frames in BSS; compile-time names for current definition.
// ============================================================================
.equ LOCAL_MAX, 32
.equ LOCAL_NAME_STR, 32
.equ LOCAL_FRAME_MAX, 16

// (LOCAL-INIT) ( nLocals nInit reverse -- )
XLOCAL_INIT:
    // TOS = reverse, then nInit, nLocals
    mov  x2, x20                   // reverse
    ldr  x1, [x22], #8             // nInit
    ldr  x0, [x22], #8             // nLocals
    ldr  x20, [x22], #8
    // Clamp
    cmp  x0, #LOCAL_MAX
    b.ls 1f
    mov  x0, #LOCAL_MAX
1:
    cmp  x1, x0
    b.ls 2f
    mov  x1, x0
2:
    adrp x3, local_frame_depth@page
    add  x3, x3, local_frame_depth@pageoff
    ldr  x4, [x3]
    cmp  x4, #LOCAL_FRAME_MAX
    b.hs 9f                        // overflow: drop inits and ignore
    // frame base = local_frames + depth * LOCAL_MAX * 8
    mov  x5, #LOCAL_MAX
    mul  x5, x5, x4
    lsl  x5, x5, #3
    adrp x6, local_frames@page
    add  x6, x6, local_frames@pageoff
    add  x6, x6, x5                // x6 = frame base
    // zero frame
    mov  x7, #0
3:
    cmp  x7, x0
    b.hs 4f
    str  xzr, [x6, x7, lsl #3]
    add  x7, x7, #1
    b    3b
4:
    // fill from stack
    cbz  x2, 5f                    // reverse?
    // reverse: pop into nInit-1 .. 0
    mov  x7, x1
6:
    cbz  x7, 7f
    sub  x7, x7, #1
    str  x20, [x6, x7, lsl #3]
    ldr  x20, [x22], #8
    b    6b
5:
    // forward: pop into 0 .. nInit-1
    mov  x7, #0
8:
    cmp  x7, x1
    b.hs 7f
    str  x20, [x6, x7, lsl #3]
    ldr  x20, [x22], #8
    add  x7, x7, #1
    b    8b
7:
    // record RSP marker and nLocals for this frame
    adrp x5, local_frame_rsp@page
    add  x5, x5, local_frame_rsp@pageoff
    str  x23, [x5, x4, lsl #3]
    adrp x5, local_frame_n@page
    add  x5, x5, local_frame_n@pageoff
    str  x0, [x5, x4, lsl #3]
    add  x4, x4, #1
    str  x4, [x3]
9:
    NEXT

// (LOCAL@) ( idx -- x )  replace TOS index with local value (do NOT drop under)
// Bugfix: an extra "pop under" dropped one stack cell per local fetch, so
// sequences like  bi BI-DATA  bi BI-CAP CELLS ERASE  lost the address and
// C!/ERASE faulted (bi-test after BI-CLEAR / any {: bi :} word using ERASE).
XLOCAL_AT:
    mov  x0, x20                   // idx (TOS)
    adrp x1, local_frame_depth@page
    add  x1, x1, local_frame_depth@pageoff
    ldr  x1, [x1]
    cbz  x1, 1f
    sub  x1, x1, #1
    mov  x2, #LOCAL_MAX
    mul  x2, x2, x1
    lsl  x2, x2, #3
    adrp x3, local_frames@page
    add  x3, x3, local_frames@pageoff
    add  x3, x3, x2
    // bounds
    adrp x2, local_frame_n@page
    add  x2, x2, local_frame_n@pageoff
    ldr  x2, [x2, x1, lsl #3]
    cmp  x0, x2
    b.hs 1f
    ldr  x20, [x3, x0, lsl #3]     // replace idx with value
    NEXT
1:
    mov  x20, #0
    NEXT

// (LOCAL!) ( x idx -- )
XLOCAL_STORE:
    mov  x0, x20                   // idx
    ldr  x1, [x22], #8             // x
    ldr  x20, [x22], #8
    adrp x2, local_frame_depth@page
    add  x2, x2, local_frame_depth@pageoff
    ldr  x2, [x2]
    cbz  x2, 1f
    sub  x2, x2, #1
    mov  x3, #LOCAL_MAX
    mul  x3, x3, x2
    lsl  x3, x3, #3
    adrp x4, local_frames@page
    add  x4, x4, local_frames@pageoff
    add  x4, x4, x3
    adrp x3, local_frame_n@page
    add  x3, x3, local_frame_n@pageoff
    ldr  x3, [x3, x2, lsl #3]
    cmp  x0, x3
    b.hs 1f
    str  x1, [x4, x0, lsl #3]
1:
    NEXT

// {:  immediate — parse args | vals -- outs :} then compile (LOCAL-INIT)
// MUST NOT clobber x19 (IP) / x20-x24 (VM). Phase lives in local_brace_phase.
XLOCAL_BRACE:
    // compile-only
    adrp x0, state_var@page
    add  x0, x0, state_var@pageoff
    ldr  x0, [x0]
    cbz  x0, 9f
    bl   _local_compile_reset
    // reverse init for {:
    mov  x0, #1
    adrp x1, local_init_reverse@page
    add  x1, x1, local_init_reverse@pageoff
    str  x0, [x1]
    adrp x1, local_brace_phase@page
    add  x1, x1, local_brace_phase@pageoff
    str  xzr, [x1]                 // phase 0=args 1=vals 2=skip
_lb_loop:
    bl   _next_word
    cbz  x1, _lb_done              // EOF
    // check :}
    cmp  x1, #2
    b.ne 1f
    ldrb w2, [x0]
    cmp  w2, #':'
    b.ne 1f
    ldrb w2, [x0, #1]
    cmp  w2, #'}'
    b.eq _lb_done
1:
    // |
    cmp  x1, #1
    b.ne 2f
    ldrb w2, [x0]
    cmp  w2, #'|'
    b.ne 2f
    mov  x2, #1
    adrp x3, local_brace_phase@page
    add  x3, x3, local_brace_phase@pageoff
    str  x2, [x3]
    b    _lb_loop
2:
    // --
    cmp  x1, #2
    b.ne 3f
    ldrb w2, [x0]
    cmp  w2, #'-'
    b.ne 3f
    ldrb w2, [x0, #1]
    cmp  w2, #'-'
    b.ne 3f
    mov  x2, #2
    adrp x3, local_brace_phase@page
    add  x3, x3, local_brace_phase@pageoff
    str  x2, [x3]
    b    _lb_loop
3:
    adrp x3, local_brace_phase@page
    add  x3, x3, local_brace_phase@pageoff
    ldr  x3, [x3]
    cmp  x3, #2
    b.eq _lb_loop                  // skip outs
    // add local name (x0/x1 still name)
    bl   _local_add_name
    adrp x3, local_brace_phase@page
    add  x3, x3, local_brace_phase@pageoff
    ldr  x3, [x3]
    cbnz x3, _lb_loop              // not args phase
    // phase args: bump init count
    adrp x2, local_init_count@page
    add  x2, x2, local_init_count@pageoff
    ldr  x3, [x2]
    add  x3, x3, #1
    str  x3, [x2]
    b    _lb_loop
_lb_done:
    bl   _local_finalize_compile
9:
    NEXT

// TO immediate — local store if name is local; else VALUE store
XTO_IMM:
    bl   _next_word
    cbz  x1, 9f
    // Save name
    stp  x0, x1, [sp, #-16]!
    adrp x2, state_var@page
    add  x2, x2, state_var@pageoff
    ldr  x2, [x2]
    cbz  x2, 1f                    // interpret → VALUE path
    // compiling: local?
    bl   _local_lookup
    cmp  x0, #-1
    b.eq 1f
    // compile LIT idx (LOCAL!)
    mov  x1, x0
    str  x1, [sp, #-16]!
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    ldr  x0, [sp], #16
    bl   _compile_cell
    adrp x0, cfa_local_store@page
    add  x0, x0, cfa_local_store@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    add  sp, sp, #16
    b    9f
1:
    // VALUE path: FIND name, >BODY CELL+ (CFA+16 for DOES> VALUE), ! or compile
    ldp  x0, x1, [sp], #16
    bl   _find_word
    cbz  x0, 9f
    // x0 = CFA; data for VALUE/CREATE DOES> @ is at CFA+16
    add  x0, x0, #16
    adrp x2, state_var@page
    add  x2, x2, state_var@pageoff
    ldr  x2, [x2]
    cbz  x2, 2f
    // compile LIT addr !
    str  x0, [sp, #-16]!
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    ldr  x0, [sp], #16
    bl   _compile_cell
    // compile !  (find CODE word "!")
    adrp x0, str_store_name@page
    add  x0, x0, str_store_name@pageoff
    mov  x1, #1
    bl   _find_word
    cbz  x0, 9f
    bl   _compile_cell
    b    9f
2:
    // interpret TO: VALUE ( x -- ) or 2VALUE ( x1 x2 -- )
    // depth including TOS: cells under + 1. Stack grows down from SP0.
    adrp x3, data_stack@page
    add  x3, x3, data_stack@pageoff
    add  x3, x3, #4096             // SP0 empty
    sub  x3, x3, x22
    lsr  x3, x3, #3                // #cells under TOS
    add  x3, x3, #1                // + TOS
    cmp  x3, #2
    b.lo 3f
    // 2VALUE: lo under, hi TOS → 2! at addr
    str  x20, [x0, #8]             // hi
    ldr  x1, [x22], #8             // lo
    str  x1, [x0]
    ldr  x20, [x22], #8
    b    9f
3:
    // VALUE: single cell
    str  x20, [x0]
    ldr  x20, [x22], #8
9:
    NEXT

// --- locals helpers ---

// _local_compile_reset
_local_compile_reset:
    adrp x0, local_name_count@page
    add  x0, x0, local_name_count@pageoff
    str  xzr, [x0]
    adrp x0, local_init_count@page
    add  x0, x0, local_init_count@pageoff
    str  xzr, [x0]
    adrp x0, local_init_reverse@page
    add  x0, x0, local_init_reverse@pageoff
    str  xzr, [x0]
    ret

// _local_add_name: x0=addr, x1=len  (uppercase into table)
_local_add_name:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    adrp x0, local_name_count@page
    add  x0, x0, local_name_count@pageoff
    ldr  x1, [x0]
    cmp  x1, #LOCAL_MAX
    b.hs 9f
    // slot = local_names + count * LOCAL_NAME_STR
    mov  x2, #LOCAL_NAME_STR
    mul  x2, x2, x1
    adrp x3, local_names@page
    add  x3, x3, local_names@pageoff
    add  x3, x3, x2
    cmp  x20, #31
    b.ls 1f
    mov  x20, #31
1:
    strb w20, [x3], #1
    mov  x2, #0
2:
    cmp  x2, x20
    b.hs 3f
    ldrb w4, [x19, x2]
    cmp  w4, #'a'
    b.lo 21f
    cmp  w4, #'z'
    b.hi 21f
    sub  w4, w4, #32
21:
    strb w4, [x3, x2]
    add  x2, x2, #1
    b    2b
3:
    adrp x0, local_name_count@page
    add  x0, x0, local_name_count@pageoff
    ldr  x1, [x0]
    add  x1, x1, #1
    str  x1, [x0]
9:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _local_lookup: x0=addr x1=len -> x0=index or -1
_local_lookup:
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    adrp x0, local_name_count@page
    add  x0, x0, local_name_count@pageoff
    ldr  x21, [x0]
    mov  x22, #0
1:
    cmp  x22, x21
    b.hs 8f
    mov  x2, #LOCAL_NAME_STR
    mul  x2, x2, x22
    adrp x3, local_names@page
    add  x3, x3, local_names@pageoff
    add  x3, x3, x2
    ldrb w2, [x3], #1
    cmp  x2, x20
    b.ne 3f
    mov  x4, #0
2:
    cmp  x4, x20
    b.hs 9f                        // match
    ldrb w5, [x3, x4]
    ldrb w6, [x19, x4]
    cmp  w6, #'a'
    b.lo 21f
    cmp  w6, #'z'
    b.hi 21f
    sub  w6, w6, #32
21:
    cmp  w5, w6
    b.ne 3f
    add  x4, x4, #1
    b    2b
3:
    add  x22, x22, #1
    b    1b
8:
    mov  x0, #-1
    b    10f
9:
    mov  x0, x22
10:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ret

// _local_finalize_compile: compile LIT n LIT nInit LIT rev (LOCAL-INIT)
_local_finalize_compile:
    stp x29, x30, [sp, #-16]!
    // LIT nLocals
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    adrp x0, local_name_count@page
    add  x0, x0, local_name_count@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    // LIT nInit
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    adrp x0, local_init_count@page
    add  x0, x0, local_init_count@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    // LIT reverse
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    adrp x0, local_init_reverse@page
    add  x0, x0, local_init_reverse@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    // (LOCAL-INIT)
    adrp x0, cfa_local_init@page
    add  x0, x0, cfa_local_init@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    ldp x29, x30, [sp], #16
    ret

// _local_frame_try_exit: pop frame if RSP matches marker
_local_frame_try_exit:
    adrp x0, local_frame_depth@page
    add  x0, x0, local_frame_depth@pageoff
    ldr  x1, [x0]
    cbz  x1, 1f
    sub  x1, x1, #1
    adrp x2, local_frame_rsp@page
    add  x2, x2, local_frame_rsp@pageoff
    ldr  x2, [x2, x1, lsl #3]
    cmp  x2, x23
    b.ne 1f
    str  x1, [x0]                  // pop depth
1:
    ret

// ============================================================================
// WORDS — TZForth-compatible listing (see TZForth.swift register("WORDS"))
// - Only first search-order wordlist (CONTEXT / search_order[0]), not CURRENT
//   e.g. ONLY FORTH ALSO BIG-INTEGER WORDS → BIG-INTEGER only
// - Optional name filter: next parse-word, substring, case-insensitive
// - Kernel words (CFA < words_user_base, set after bootstrap): A–Z sorted
//   under banner "64Forth System Words"
// - User words (keyboard / FLOAD / INCLUDE / REQUIRE…): load order at end
//   under banner "64Forth User Words" (only if any user words)
// - Header: --- <wordlist> (n) ---
// - Print 8 names per line within each section
// ============================================================================
.equ WORDS_MAX, 1024

XWORDS:
    SAVE_VM
    // Optional filter: parse next word (empty at EOL → no filter)
    bl   _next_word                // x0=scratch, x1=len
    mov  x2, #63
    cmp  x1, x2
    csel x1, x2, x1, hi            // min(len, 63)
    adrp x2, words_filter_len@page
    add  x2, x2, words_filter_len@pageoff
    str  x1, [x2]
    adrp x3, words_filter@page
    add  x3, x3, words_filter@pageoff
    mov  x4, #0
1:  // copy filter uppercased
    cmp  x4, x1
    b.hs 2f
    ldrb w5, [x0, x4]
    cmp  w5, #'a'
    b.lo 11f
    cmp  w5, #'z'
    b.hi 11f
    sub  w5, w5, #32
11:
    strb w5, [x3, x4]
    add  x4, x4, #1
    b    1b
2:
    // wid = search_order[0] (CONTEXT), else FORTH wordlist head
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x0, [x0]
    cbz  x0, 3f
    adrp x0, search_order@page
    add  x0, x0, search_order@pageoff
    ldr  x19, [x0]                 // wid (addr of head cell)
    b    4f
3:
    adrp x19, latest_var@page
    add  x19, x19, latest_var@pageoff
4:
    // Fence: CFAs < words_user_base are kernel; >= are user (0 → treat all as kernel).
    // Keep fence/nk in BSS temps — helpers clobber x25+.

    // ---- Pass 1: collect kernel CFAs into words_cfa[0..nk) ----
    ldr  x20, [x19]                // latest CFA in this wordlist
    adrp x21, words_cfa@page
    add  x21, x21, words_cfa@pageoff
    mov  x22, #0                   // count
5:
    cbz  x20, 6f
    cmp  x22, #WORDS_MAX
    b.hs 6f
    adrp x0, words_user_base@page
    add  x0, x0, words_user_base@pageoff
    ldr  x0, [x0]
    cbz  x0, 53f                   // no fence → all kernel
    cmp  x20, x0
    b.hs 52f                       // user word → skip this pass
53:
    adrp x0, words_filter_len@page
    add  x0, x0, words_filter_len@pageoff
    ldr  x0, [x0]
    cbz  x0, 51f
    mov  x0, x20
    bl   _words_name_ptr
    bl   _words_filter_match
    cbz  x0, 52f
51:
    str  x20, [x21, x22, lsl #3]
    add  x22, x22, #1
52:
    ldr  x20, [x20, #-16]          // LFA @ CFA-16
    b    5b
6:
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    str  x22, [x0]                 // nk

    // ---- Pass 2: collect user CFAs (newest first) into words_cfa[nk..) ----
    adrp x0, words_user_base@page
    add  x0, x0, words_user_base@pageoff
    ldr  x0, [x0]
    cbz  x0, 65f                   // no fence → no user section
    ldr  x20, [x19]
55:
    cbz  x20, 65f
    cmp  x22, #WORDS_MAX
    b.hs 65f
    adrp x0, words_user_base@page
    add  x0, x0, words_user_base@pageoff
    ldr  x0, [x0]
    cmp  x20, x0
    b.lo 57f                       // kernel → skip
    adrp x0, words_filter_len@page
    add  x0, x0, words_filter_len@pageoff
    ldr  x0, [x0]
    cbz  x0, 56f
    mov  x0, x20
    bl   _words_name_ptr
    bl   _words_filter_match
    cbz  x0, 57f
56:
    str  x20, [x21, x22, lsl #3]
    add  x22, x22, #1
57:
    ldr  x20, [x20, #-16]
    b    55b
65:
    // Reverse user section [nk, n) → load order (oldest first). Walk was newest-first.
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x0, [x0]                  // lo = nk
    cmp  x22, x0
    b.ls 67f                       // no user words (n <= nk)
    sub  x1, x22, #1               // hi = n-1
66:
    cmp  x0, x1
    b.ge 67f
    ldr  x2, [x21, x0, lsl #3]
    ldr  x3, [x21, x1, lsl #3]
    str  x3, [x21, x0, lsl #3]
    str  x2, [x21, x1, lsl #3]
    add  x0, x0, #1
    sub  x1, x1, #1
    b    66b
67:
    // Insertion sort only kernel range [0, nk) by name (case-insensitive)
    mov  x1, #1
61:
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x0, [x0]                  // nk
    cmp  x1, x0
    b.hs 7f
    ldr  x2, [x21, x1, lsl #3]     // key CFA
    mov  x3, x1
62:
    cbz  x3, 63f
    sub  x4, x3, #1
    ldr  x5, [x21, x4, lsl #3]     // predecessor CFA
    stp  x1, x2, [sp, #-16]!
    stp  x3, x4, [sp, #-16]!
    mov  x0, x5
    mov  x1, x2
    bl   _words_cfa_cmp            // <0 if name(a)<name(b)
    ldp  x3, x4, [sp], #16
    ldp  x1, x2, [sp], #16
    cmp  x0, #0
    b.le 63f                       // pred <= key → stop
    ldr  x5, [x21, x4, lsl #3]
    str  x5, [x21, x3, lsl #3]
    mov  x3, x4
    b    62b
63:
    str  x2, [x21, x3, lsl #3]
    add  x1, x1, #1
    b    61b
7:
    // Header: --- <wordlist> (n) ---
    mov  x0, #10
    bl   _putchar
    adrp x0, str_words_hdr1@page
    add  x0, x0, str_words_hdr1@pageoff
    bl   _print_string_svc
    mov  x0, x19                   // wid
    bl   _print_wid_name
    mov  x0, #32
    bl   _putchar
    mov  x0, #'('
    bl   _putchar
    mov  x0, x22                   // total n
    bl   _print_unsigned
    mov  x0, #')'
    bl   _putchar
    adrp x0, str_words_hdr2@page
    add  x0, x0, str_words_hdr2@pageoff
    bl   _print_string_svc
    mov  x0, #10
    bl   _putchar
    // ---- 64Forth System Words (kernel, A–Z) ----
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x0, [x0]                  // nk
    cbz  x0, 76f                   // no system words (unusual)
    adrp x0, str_words_sys@page
    add  x0, x0, str_words_sys@pageoff
    bl   _print_string_svc
    mov  x23, #0                   // i
    mov  x24, #0                   // col
71:
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x0, [x0]
    cmp  x23, x0
    b.hs 75f
    ldr  x0, [x21, x23, lsl #3]
    bl   _words_name_ptr
    cbz  x1, 72f
    stp  x23, x24, [sp, #-16]!
    bl   _write_stdout
    ldp  x23, x24, [sp], #16
72:
    mov  x0, #32
    bl   _putchar
    add  x24, x24, #1
    cmp  x24, #8
    b.lo 74f
    mov  x0, #10
    bl   _putchar
    mov  x24, #0
74:
    add  x23, x23, #1
    b    71b
75:
    cbz  x24, 76f
    mov  x0, #10
    bl   _putchar
76:
    // ---- 64Forth User Words (load order), only if any ----
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x0, [x0]                  // nk
    cmp  x22, x0
    b.ls 82f                       // n <= nk → no user section
    adrp x0, str_words_user@page
    add  x0, x0, str_words_user@pageoff
    bl   _print_string_svc
    adrp x0, words_nk_tmp@page
    add  x0, x0, words_nk_tmp@pageoff
    ldr  x23, [x0]                 // i = nk
    mov  x24, #0                   // col
77:
    cmp  x23, x22
    b.hs 80f
    ldr  x0, [x21, x23, lsl #3]
    bl   _words_name_ptr
    cbz  x1, 78f
    stp  x23, x24, [sp, #-16]!
    bl   _write_stdout
    ldp  x23, x24, [sp], #16
78:
    mov  x0, #32
    bl   _putchar
    add  x24, x24, #1
    cmp  x24, #8
    b.lo 79f
    mov  x0, #10
    bl   _putchar
    mov  x24, #0
79:
    add  x23, x23, #1
    b    77b
80:
    cbz  x24, 82f
    mov  x0, #10
    bl   _putchar
82:
    RESTORE_VM
    NEXT

// Record HERE after first completed interpret (end of bootstrap) as the
// kernel/user WORDS fence. CFA >= base → user (load order); below → kernel.
_record_words_user_base_once:
    adrp x0, words_user_base@page
    add  x0, x0, words_user_base@pageoff
    ldr  x1, [x0]
    cbnz x1, 1f
    adrp x1, here_ptr@page
    add  x1, x1, here_ptr@pageoff
    ldr  x1, [x1]
    str  x1, [x0]
1:
    ret

// _words_name_ptr: x0=CFA → x0=name chars, x1=len
_words_name_ptr:
    ldr  x1, [x0, #-8]             // FLAGS
    and  x1, x1, #0xFFFFFFFF       // NFA_OFF
    sub  x0, x0, x1                // NFA
    ldrb w1, [x0], #1              // count; x0 → chars
    ret

// _words_upchar: w0 = char → w0 = uppercase ASCII letter if a-z
_words_upchar:
    cmp  w0, #'a'
    b.lo 1f
    cmp  w0, #'z'
    b.hi 1f
    sub  w0, w0, #32
1:  ret

// _words_cfa_cmp: x0=cfaA, x1=cfaB → x0 = sign(nameA - nameB) casefold
_words_cfa_cmp:
    stp  x29, x30, [sp, #-16]!
    stp  x19, x20, [sp, #-16]!
    stp  x21, x22, [sp, #-16]!
    mov  x19, x0
    mov  x20, x1
    bl   _words_name_ptr
    mov  x21, x0
    mov  x22, x1                   // lenA
    mov  x0, x20
    bl   _words_name_ptr
    // x0=charsB, x1=lenB; x21=charsA, x22=lenA
    mov  x2, x22
    cmp  x2, x1
    csel x2, x1, x2, hi            // min(lenA,lenB)
    mov  x3, #0
1:
    cmp  x3, x2
    b.hs 2f
    ldrb w4, [x21, x3]
    ldrb w5, [x0, x3]
    // casefold
    cmp  w4, #'a'
    b.lo 11f
    cmp  w4, #'z'
    b.hi 11f
    sub  w4, w4, #32
11:
    cmp  w5, #'a'
    b.lo 12f
    cmp  w5, #'z'
    b.hi 12f
    sub  w5, w5, #32
12:
    cmp  w4, w5
    b.ne 3f
    add  x3, x3, #1
    b    1b
2:
    // equal prefix → shorter name first
    cmp  x22, x1
    b.eq 4f
    mov  x0, #1
    cneg x0, x0, lo                // lenA < lenB → -1 else +1
    b    5f
3:
    cmp  w4, w5
    mov  x0, #1
    cneg x0, x0, lo
    b    5f
4:
    mov  x0, #0
5:
    ldp  x21, x22, [sp], #16
    ldp  x19, x20, [sp], #16
    ldp  x29, x30, [sp], #16
    ret

// _words_filter_match: x0=name chars, x1=name len
// → x0=1 if filter empty or name contains filter (case-insensitive substring)
_words_filter_match:
    adrp x2, words_filter_len@page
    add  x2, x2, words_filter_len@pageoff
    ldr  x2, [x2]                  // filter len
    cbz  x2, 9f                    // empty → match
    adrp x3, words_filter@page
    add  x3, x3, words_filter@pageoff
    mov  x4, #0                    // start index in name
1:
    add  x5, x4, x2
    cmp  x5, x1
    b.hi 8f                        // past end → no match
    mov  x6, #0                    // i within filter
2:
    cmp  x6, x2
    b.hs 9f                        // all filter chars matched
    add  x7, x4, x6
    ldrb w8, [x0, x7]              // name char
    cmp  w8, #'a'
    b.lo 21f
    cmp  w8, #'z'
    b.hi 21f
    sub  w8, w8, #32
21:
    ldrb w9, [x3, x6]              // filter already upper
    cmp  w8, w9
    b.ne 3f
    add  x6, x6, #1
    b    2b
3:
    add  x4, x4, #1
    b    1b
8:
    mov  x0, #0
    ret
9:
    mov  x0, #1
    ret

// ['] ( "name" -- entry ) compile-only: find word and push entry address
XBRACKET_TICK:
    // Check if in compile mode
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    ldr x0, [x0]
    cbz x0, _bracket_tick_interpret
    
    // Compile mode: compile LIT + entry address
    stp x19, x20, [sp, #-16]!
    bl _next_word
    cbz x1, _bracket_tick_fail
    bl _find_word
    cbz x0, _bracket_tick_fail
    // x0 = entry address
    mov x19, x0
    // Compile LIT entry address
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    // Compile the entry address
    mov x0, x19
    bl _compile_cell
    ldp x19, x20, [sp], #16
    NEXT

_bracket_tick_interpret:
    // Interpret mode: parse word and push entry address
    bl _next_word
    cbz x1, _bracket_tick_fail
    bl _find_word
    cbz x0, _bracket_tick_fail
    // x0 = entry address
    DPUSH
    mov x20, x0
    NEXT

_bracket_tick_fail:
    bl   _report_undefined
    b    _do_quit

// LIT-ADDR ( -- addr ) push dict_lit entry address
XLIT_ADDR:
    DPUSH
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    mov x20, x0
    NEXT

// 0BRANCH-ADDR ( -- addr ) push dict_0branch entry address
X0BRANCH_ADDR:
    DPUSH
    adrp x0, cfa_0branch@page
    add x0, x0, cfa_0branch@pageoff
    ldr x0, [x0]
    mov x20, x0
    NEXT

// BRANCH-ADDR ( -- addr ) push dict_branch entry address
XBRANCH_ADDR:
    DPUSH
    adrp x0, cfa_branch@page
    add x0, x0, cfa_branch@pageoff
    ldr x0, [x0]
    mov x20, x0
    NEXT

// EXIT-ADDR ( -- addr ) push dict_exit entry address
XEXIT_ADDR:
    DPUSH
    adrp x0, cfa_exit@page
    add x0, x0, cfa_exit@pageoff
    ldr x0, [x0]
    mov x20, x0
    NEXT

// SLIT-ADDR ( -- xt ) xt of (S") — for SEE without embedding quotes in forth_init
XSLIT_ADDR:
    DPUSH
    adrp x0, cfa_slit@page
    add  x0, x0, cfa_slit@pageoff
    ldr  x0, [x0]
    mov  x20, x0
    NEXT

// DOCON-ADDR ( -- addr ) address of DOCON code (for CONSTANT)
XDOCON_ADDR:
    DPUSH
    adrp x0, DOCON@page
    add x0, x0, DOCON@pageoff
    mov x20, x0
    NEXT

// DOCOL-ADDR ( -- addr ) address of DOCOL code (colon entry; for DOCOL? / SEE)
XDOCOL_ADDR:
    DPUSH
    adrp x0, DOCOL@page
    add  x0, x0, DOCOL@pageoff
    mov  x20, x0
    NEXT

// ============================================================================
// DO / LOOP family  (R: limit index  with index on top)
// ============================================================================

// (DO) ( limit index -- )  R: -- limit index
XDO_RT:
    ldr x0, [x22], #8              // limit
    str x0, [x23, #-8]!            // R: limit
    str x20, [x23, #-8]!           // R: limit index
    ldr x20, [x22], #8
    NEXT

// (?DO) ( limit index -- )  R: -- limit index | skip loop if equal
// Inline after xt: forward branch offset (like BRANCH) used when index==limit.
XQDO_RT:
    ldr x0, [x22], #8              // limit
    cmp x20, x0
    b.eq _qdo_skip
    str x0, [x23, #-8]!            // R: limit
    str x20, [x23, #-8]!           // R: index
    ldr x20, [x22], #8
    add x19, x19, #8               // skip forward-offset cell
    NEXT
_qdo_skip:
    ldr x20, [x22], #8             // drop index
    ldr x0, [x19]
    add x19, x19, x0               // branch past LOOP/+LOOP
    NEXT

// (LOOP) ( -- )  increment index; branch by offset if not done
// LEAVE sets index=limit so first cmp exits.
XLOOP_RT:
    ldr x0, [x23], #8              // index
    ldr x1, [x23], #8              // limit
    cmp x0, x1
    b.ge _loop_done                // LEAVE or finished
    add x0, x0, #1
    cmp x0, x1
    b.eq _loop_done
    str x1, [x23, #-8]!
    str x0, [x23, #-8]!
    ldr x2, [x19]
    add x19, x19, x2
    NEXT
_loop_done:
    add x19, x19, #8               // skip offset
    NEXT

// (+LOOP) ( n -- )
XPLUSLOOP_RT:
    ldr x0, [x23], #8              // index
    ldr x1, [x23], #8              // limit
    mov x2, x20                    // step n
    ldr x20, [x22], #8
    cmp x0, x1
    b.eq _pl_done                  // LEAVE: index == limit
    mov x3, x0                     // old index
    add x0, x0, x2                 // new index
    cmp x2, #0
    b.lt _pl_neg
    // n >= 0: done if old < limit && new >= limit
    cmp x3, x1
    b.ge _pl_cont
    cmp x0, x1
    b.ge _pl_done
    b _pl_cont
_pl_neg:
    cmp x3, x1
    b.lt _pl_cont
    cmp x0, x1
    b.lt _pl_done
_pl_cont:
    str x1, [x23, #-8]!
    str x0, [x23, #-8]!
    ldr x2, [x19]
    add x19, x19, x2
    NEXT
_pl_done:
    add x19, x19, #8
    NEXT

// I ( -- n )  current loop index
XI:
    str x20, [x22, #-8]!
    ldr x20, [x23]
    NEXT

// J ( -- n )  outer loop index
XJ:
    str x20, [x22, #-8]!
    ldr x20, [x23, #16]            // skip inner index+limit
    NEXT

// UNLOOP ( -- )  R: limit index --
XUNLOOP:
    add x23, x23, #16
    NEXT

// LEAVE ( -- )  set index=limit so LOOP/+LOOP exit
XLEAVE:
    ldr x0, [x23, #8]              // limit
    str x0, [x23]                  // index = limit
    NEXT

// (DOES>) ( -- ) runtime of DOES>: patch CURRENT's latest, then EXIT defining word
XDOES_RT:
    adrp x0, current_var@page
    add  x0, x0, current_var@pageoff
    ldr  x0, [x0]
    cbz  x0, 1f
    ldr  x0, [x0]                  // latest CFA in CURRENT wordlist
    b    2f
1:
    adrp x0, latest_var@page
    add  x0, x0, latest_var@pageoff
    ldr  x0, [x0]
2:
    adrp x1, DODOES@page
    add x1, x1, DODOES@pageoff
    str x1, [x0]                   // CODE at CFA = DODOES
    str x19, [x0, #8]              // does_ip at CFA+8
    RPOP
    NEXT

// DOES> ( -- ) IMMEDIATE  compile (DOES>)
XDOES:
    adrp x0, cfa_does_rt@page
    add x0, x0, cfa_does_rt@pageoff
    ldr x0, [x0]
    bl _compile_cell
    NEXT

// ============================================================================
// Pictured numeric output support
// ============================================================================
// PAD ( -- c-addr )
XPAD:
    str x20, [x22, #-8]!
    adrp x0, pad_buffer@page
    add x0, x0, pad_buffer@pageoff
    mov x20, x0
    NEXT

// MS@ ( -- u )  wall-clock milliseconds since Unix epoch
// Uses libc gettimeofday (stable on Darwin); not ANS MS (which is a delay).
XMSFETCH:
    SAVE_VM
    sub sp, sp, #16                // struct timeval { tv_sec, tv_usec }
    mov x0, sp
    mov x1, xzr
    bl _gettimeofday
    ldr x0, [sp]                   // tv_sec
    ldr x1, [sp, #8]               // tv_usec
    add sp, sp, #16
    RESTORE_VM
    mov x2, #1000
    mul x0, x0, x2                 // sec * 1000
    udiv x1, x1, x2                // usec / 1000
    add x0, x0, x1
    str x20, [x22, #-8]!
    mov x20, x0
    NEXT

// TIME&DATE ( -- sec min hour day month year )
// Host hook if set: void hook(int64_t out[6]); else 0 0 0 1 1 1970.
XTIME_DATE:
    SAVE_VM
    adrp x1, time_date_hook@page
    add  x1, x1, time_date_hook@pageoff
    ldr  x9, [x1]
    sub  sp, sp, #48
    cbz  x9, 1f
    mov  x0, sp
    blr  x9
    b    2f
1:
    // stub defaults
    str  xzr, [sp]                 // sec
    str  xzr, [sp, #8]             // min
    str  xzr, [sp, #16]            // hour
    mov  x0, #1
    str  x0, [sp, #24]             // day
    str  x0, [sp, #32]             // month
    mov  x0, #1970
    str  x0, [sp, #40]             // year
2:
    ldp  x1, x2, [sp]              // sec min
    ldp  x3, x4, [sp, #16]         // hour day
    ldp  x5, x6, [sp, #32]         // month year
    add  sp, sp, #48
    RESTORE_VM
    // push 6 cells: sec … month under, year TOS
    str  x20, [x22, #-8]!
    str  x1, [x22, #-8]!
    str  x2, [x22, #-8]!
    str  x3, [x22, #-8]!
    str  x4, [x22, #-8]!
    str  x5, [x22, #-8]!
    mov  x20, x6
    NEXT

// ============================================================================
// File-Access (ANS 11) — thin CODE wrappers around host file_op_hook
// op: 1 open 2 create 3 close 4 read 5 write 6 rline 7 wline
//     8 pos 9 size 10 repos 11 resize 12 delete 13 rename 14 status 15 flush
// ============================================================================
.equ FOP_OPEN, 1
.equ FOP_CREATE, 2
.equ FOP_CLOSE, 3
.equ FOP_READ, 4
.equ FOP_WRITE, 5
.equ FOP_RLINE, 6
.equ FOP_WLINE, 7
.equ FOP_POS, 8
.equ FOP_SIZE, 9
.equ FOP_REPOS, 10
.equ FOP_RESIZE, 11
.equ FOP_DELETE, 12
.equ FOP_RENAME, 13
.equ FOP_STATUS, 14
.equ FOP_FLUSH, 15

// R/O W/O R/W BIN — fam constants
XR_O:
    DPUSH
    mov x20, #1
    NEXT
XW_O:
    DPUSH
    mov x20, #2
    NEXT
XR_W:
    DPUSH
    mov x20, #4
    NEXT
XBIN:
    orr x20, x20, #8
    NEXT

// Helper: call file_op_hook.
// In:  x0=op x1=a x2=b x3=c x4=d x5=ptr
// Out: x0=ior x6=o1 x7=o2 x8=o3
// Call with SAVE_VM around; does not touch callee-saved x19-x24 if hook is careful.
_file_op_call:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x9, file_op_hook@page
    add  x9, x9, file_op_hook@pageoff
    ldr  x9, [x9]
    cbz  x9, 1f
    // Frame (16-byte aligned):
    //   [sp+0]  = 9th arg (o3*)
    //   [sp+16] = o1 value
    //   [sp+24] = o2 value
    //   [sp+32] = o3 value
    sub  sp, sp, #64
    add  x6, sp, #16               // o1*
    add  x7, sp, #24               // o2*
    add  x8, sp, #32               // o3*
    str  xzr, [x6]
    str  xzr, [x7]
    str  xzr, [x8]
    str  x8, [sp]                  // 9th parameter
    // x0..x7 already: op,a,b,c,d,ptr,o1*,o2*
    blr  x9
    ldr  x6, [sp, #16]
    ldr  x7, [sp, #24]
    ldr  x8, [sp, #32]
    add  sp, sp, #64
    ldp  x29, x30, [sp], #16
    ret
1:
    mov  x0, #-1
    mov  x6, #0
    mov  x7, #0
    mov  x8, #0
    ldp  x29, x30, [sp], #16
    ret

// OPEN-FILE ( c-addr u fam -- fileid ior )
XOPEN_FILE:
    mov  x3, x20                   // fam -> c
    ldr  x2, [x22], #8             // u -> b
    ldr  x5, [x22], #8             // c-addr -> ptr
    mov  x1, #0                    // a unused
    mov  x4, #0
    mov  x0, #FOP_OPEN
    SAVE_VM
    // remap: op=x0 a=0 b=u c=fam d=0 ptr=caddr
    // Currently x0=op x1=a x2=u x3=fam x4=0 x5=ptr — good
    bl   _file_op_call
    RESTORE_VM
    // ior in x0, fileid in x6
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!           // fileid under
    mov  x20, x0                   // ior TOS
    NEXT

// CREATE-FILE ( c-addr u fam -- fileid ior )
XCREATE_FILE:
    mov  x3, x20
    ldr  x2, [x22], #8
    ldr  x5, [x22], #8
    mov  x1, #0
    mov  x4, #0
    mov  x0, #FOP_CREATE
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!
    mov  x20, x0
    NEXT

// CLOSE-FILE ( fileid -- ior )
XCLOSE_FILE:
    mov  x1, x20
    mov  x0, #FOP_CLOSE
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// READ-FILE ( c-addr u1 fileid -- u2 ior )
XREAD_FILE:
    mov  x1, x20                   // fileid
    ldr  x2, [x22], #8             // u1
    ldr  x5, [x22], #8             // c-addr
    mov  x0, #FOP_READ
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!           // u2
    mov  x20, x0                   // ior
    NEXT

// WRITE-FILE ( c-addr u fileid -- ior )
XWRITE_FILE:
    mov  x1, x20
    ldr  x2, [x22], #8
    ldr  x5, [x22], #8
    mov  x0, #FOP_WRITE
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// READ-LINE ( c-addr u1 fileid -- u2 flag ior )
XREAD_LINE:
    mov  x1, x20
    ldr  x2, [x22], #8
    ldr  x5, [x22], #8
    mov  x0, #FOP_RLINE
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!           // u2
    str  x7, [x22, #-8]!           // flag
    mov  x20, x0                   // ior
    NEXT

// WRITE-LINE ( c-addr u fileid -- ior )
XWRITE_LINE:
    mov  x1, x20
    ldr  x2, [x22], #8
    ldr  x5, [x22], #8
    mov  x0, #FOP_WLINE
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// FILE-POSITION ( fileid -- ud ior )
XFILE_POSITION:
    mov  x1, x20
    mov  x0, #FOP_POS
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!           // lo
    str  x7, [x22, #-8]!           // hi
    mov  x20, x0
    NEXT

// FILE-SIZE ( fileid -- ud ior )
XFILE_SIZE:
    mov  x1, x20
    mov  x0, #FOP_SIZE
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!
    str  x7, [x22, #-8]!
    mov  x20, x0
    NEXT

// REPOSITION-FILE ( ud fileid -- ior )
XREPOSITION_FILE:
    mov  x1, x20                   // fileid
    ldr  x3, [x22], #8             // hi
    ldr  x2, [x22], #8             // lo
    mov  x0, #FOP_REPOS
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// RESIZE-FILE ( ud fileid -- ior )
XRESIZE_FILE:
    mov  x1, x20
    ldr  x3, [x22], #8
    ldr  x2, [x22], #8
    mov  x0, #FOP_RESIZE
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// DELETE-FILE ( c-addr u -- ior )
XDELETE_FILE:
    mov  x2, x20                   // u
    ldr  x5, [x22], #8             // c-addr
    mov  x0, #FOP_DELETE
    mov  x1, #0
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// RENAME-FILE ( c-addr1 u1 c-addr2 u2 -- ior )
XRENAME_FILE:
    mov  x4, x20                   // u2 = d
    ldr  x3, [x22], #8             // c-addr2 as integer ptr = c
    ldr  x2, [x22], #8             // u1 = b
    ldr  x5, [x22], #8             // c-addr1 = ptr
    mov  x0, #FOP_RENAME
    mov  x1, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// FILE-STATUS ( c-addr u -- x ior )
XFILE_STATUS:
    mov  x2, x20
    ldr  x5, [x22], #8
    mov  x0, #FOP_STATUS
    mov  x1, #0
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    str  x20, [x22, #-8]!
    str  x6, [x22, #-8]!           // x
    mov  x20, x0
    NEXT

// FLUSH-FILE ( fileid -- ior )
XFLUSH_FILE:
    mov  x1, x20
    mov  x0, #FOP_FLUSH
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  x5, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    mov  x20, x0
    NEXT

// _block_erase_buf: fill block_buf with blanks (space). Clobbers x0-x2.
_block_erase_buf:
    adrp x0, block_buf@page
    add  x0, x0, block_buf@pageoff
    mov  x1, #1024
    mov  w2, #32
1:
    cbz  x1, 2f
    strb w2, [x0], #1
    sub  x1, x1, #1
    b    1b
2:
    ret

// _block_load_nr: x0 = block number. Load that block from BLOCK-FILE into
// block_buf (or blank if no file). Updates block_nr. Preserves VM via SAVE_VM
// only around file_op; caller may hold VM regs. Clobbers x0-x8,x9.
// Does not touch dirty flag (callers manage UPDATE).
_block_load_nr:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    str  x19, [sp, #16]
    mov  x19, x0                   // block#
    adrp x0, block_nr@page
    add  x0, x0, block_nr@pageoff
    str  x19, [x0]
    adrp x0, block_file_var@page
    add  x0, x0, block_file_var@pageoff
    ldr  x1, [x0]                  // fileid
    cbz  x1, _bln_blank
    // REPOSITION: offset = block# * 1024 as ud (lo=offset, hi=0)
    lsl  x2, x19, #10              // *1024
    mov  x0, #FOP_REPOS
    mov  x3, #0                    // hi
    mov  x4, #0
    mov  x5, #0
    // x1 already fileid
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    cbnz x0, _bln_blank            // seek fail → blank
    // READ 1024 into block_buf
    adrp x5, block_buf@page
    add  x5, x5, block_buf@pageoff
    adrp x0, block_file_var@page
    add  x0, x0, block_file_var@pageoff
    ldr  x1, [x0]
    mov  x2, #1024
    mov  x0, #FOP_READ
    mov  x3, #0
    mov  x4, #0
    SAVE_VM
    bl   _file_op_call
    RESTORE_VM
    // if short read, pad rest with blanks
    cmp  x6, #1024
    b.hs _bln_done
    adrp x0, block_buf@page
    add  x0, x0, block_buf@pageoff
    add  x0, x0, x6
    mov  x1, #1024
    sub  x1, x1, x6
    mov  w2, #32
3:
    cbz  x1, _bln_done
    strb w2, [x0], #1
    sub  x1, x1, #1
    b    3b
_bln_blank:
    bl   _block_erase_buf
_bln_done:
    adrp x0, block_upd@page
    add  x0, x0, block_upd@pageoff
    str  xzr, [x0]                 // clean after load
    ldr  x19, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// MS ( u -- )  Facility: wait at least u milliseconds (yields via nanosleep).
// Busy-wait on MS@ freezes the SwiftUI main thread; always sleep in the OS.
XMS:
    mov x0, x20                    // ms
    ldr x20, [x22], #8
    cbz x0, _ms_done
    SAVE_VM
    // Split large delays into ≤1s nanosleep chunks so EINTR can resume.
_ms_loop:
    // x19 holds remaining ms across nanosleep (SAVE_VM already saved VM x19)
    // Use stack-only: remaining in x19 after SAVE is free for us if we save it.
    // After SAVE_VM, x19-x24 are free for C calls; we keep remaining in [sp].
    // Build timespec: sec = min(remaining/1000, …), nsec = (remaining%1000)*1e6
    // Work with remaining ms in x19 (callee-saved is OK inside SAVE/RESTORE block
    // only if we don't call something that expects them — libc may clobber
    // caller-saved only; x19 is callee-saved so we can keep remaining there.
    mov x19, x0                    // remaining ms
_ms_chunk:
    cbz x19, _ms_restore
    // chunk = min(remaining, 1000)
    mov x1, #1000
    cmp x19, x1
    csel x2, x19, x1, lo           // x2 = ms this chunk
    // sec = chunk / 1000  (0 or 1)
    udiv x3, x2, x1                // 0 or 1
    msub x4, x3, x1, x2            // rem_ms = chunk % 1000
    // nsec = rem_ms * 1_000_000
    mov x5, #1000
    mul x4, x4, x5
    mul x4, x4, x5                 // * 1_000_000
    // struct timespec on stack
    sub sp, sp, #16
    str x3, [sp]                   // tv_sec
    str x4, [sp, #8]               // tv_nsec
    mov x0, sp                     // req
    mov x1, sp                     // rem (overwrite req on EINTR for simplicity)
    bl _nanosleep
    add sp, sp, #16
    // subtract chunk from remaining
    mov x1, #1000
    cmp x19, x1
    csel x2, x19, x1, lo
    sub x19, x19, x2
    cbnz x19, _ms_chunk
_ms_restore:
    RESTORE_VM
_ms_done:
    NEXT

// UNUSED ( -- u )  free bytes remaining in user dictionary (logical size)
// Default logical size 1 MiB; reserve USER_DICT_MAX BSS (demand-zero). GROWMEMORYMB
// raises the logical limit once per session without relocating CFAs (max 64 MiB).
.equ USER_DICT_DEFAULT, 1048576    // 1 MiB
.equ USER_DICT_MAX, 67108864       // 64 MiB reserved / hard cap
XUNUSED:
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x1, [x0]                   // HERE
    adrp x0, user_dict_area@page
    add x0, x0, user_dict_area@pageoff
    adrp x2, user_dict_size_cell@page
    add x2, x2, user_dict_size_cell@pageoff
    ldr x2, [x2]
    add x0, x0, x2                 // end of user dictionary
    subs x0, x0, x1                // free = end - HERE
    b.hs 1f
    mov x0, xzr                    // clamp if overrun
1:
    str x20, [x22, #-8]!
    mov x20, x0
    NEXT

// REDEF-WARNING ( -- addr )  VARIABLE-like; non-zero = warn on redefine
// Defaults to 0 at cold start; set TRUE (-1) when entering the user REPL.
XREDEF_WARNING:
    str x20, [x22, #-8]!
    adrp x0, redef_warn@page
    add x0, x0, redef_warn@pageoff
    mov x20, x0
    NEXT

// FILE-ECHO ( -- addr )  VARIABLE-like; non-zero = echo INCLUDE/FLOAD lines
// Defaults to 0 (OFF). Use: FILE-ECHO ON   or   FILE-ECHO OFF
XFILE_ECHO:
    str x20, [x22, #-8]!
    adrp x0, file_echo@page
    add x0, x0, file_echo@pageoff
    mov x20, x0
    NEXT

// USER-DICT ( -- addr )  start of growable user dictionary (FORGET fence)
XUSER_DICT:
    str x20, [x22, #-8]!
    adrp x0, user_dict_area@page
    add x0, x0, user_dict_area@pageoff
    mov x20, x0
    NEXT

// GROWMEMORYMB ( n -- )  TZForth extension: set logical dictionary size to n MiB.
// Once per session; cannot shrink; 1 ≤ n ≤ 64. Base address never moves (CFA-stable).
XGROWMEMORYMB:
    mov  x0, x20                   // n (MB)
    ldr  x20, [x22], #8
    // already used?
    adrp x1, grow_memory_used@page
    add  x1, x1, grow_memory_used@pageoff
    ldr  x2, [x1]
    cbnz x2, _gmm_already
    // n >= 1?
    cmp  x0, #1
    b.lt _gmm_small
    // n <= 64?
    cmp  x0, #64
    b.hi _gmm_big
    // newsize = n * 1 MiB = n << 20
    lsl  x3, x0, #20
    // cannot shrink: newsize > current
    adrp x4, user_dict_size_cell@page
    add  x4, x4, user_dict_size_cell@pageoff
    ldr  x5, [x4]
    cmp  x3, x5
    b.ls _gmm_shrink
    // accept
    str  x3, [x4]
    mov  x2, #1
    str  x2, [x1]                  // grow_memory_used = true
    NEXT
_gmm_already:
    adrp x0, str_gmm_already@page
    add  x0, x0, str_gmm_already@pageoff
    b    _gmm_fail
_gmm_small:
    adrp x0, str_gmm_small@page
    add  x0, x0, str_gmm_small@pageoff
    b    _gmm_fail
_gmm_big:
    adrp x0, str_gmm_big@page
    add  x0, x0, str_gmm_big@pageoff
    b    _gmm_fail
_gmm_shrink:
    adrp x0, str_gmm_shrink@page
    add  x0, x0, str_gmm_shrink@pageoff
_gmm_fail:
    bl   _print_string_svc
    b    _error_abandon

// ============================================================================
// Stack pointer probes (for high-level DEPTH) + SPACES C, S>D 2* 2/ 2@ 2!
// ============================================================================
// Data stack grows down. Empty DSP = data_stack + 4096 (SP0).
// TOS is kept in x20; SP@ is DSP (x22). Depth cells = (SP0 - SP@) / 8.

// SP0 ( -- addr )  DSP value when the data stack is empty
XSP0:
    str x20, [x22, #-8]!
    adrp x0, data_stack@page
    add x0, x0, data_stack@pageoff
    add x0, x0, #4096
    mov x20, x0
    NEXT

// SP@ ( -- addr )  current data-stack pointer (under-TOS cells)
// Capture DSP before pushing the result (push would lower x22 by one cell).
XSPFETCH:
    mov x0, x22
    str x20, [x22, #-8]!
    mov x20, x0
    NEXT

// SP! ( addr -- )  set data-stack pointer (DSP). TOS becomes 0 (empty cache).
// Classic empty: SP0 SP!   (same as clearing the data stack)
XSPSTORE:
    mov x22, x20
    mov x20, #0
    NEXT

// SPACES ( n -- )  emit n spaces (n<=0: no-op)
XSPACES:
    mov x1, x20
    ldr x20, [x22], #8
    cmp x1, #0
    b.le _spaces_done
_spaces_loop:
    stp x1, x20, [sp, #-16]!
    str x22, [sp, #-16]!
    mov x0, #32
    bl _putchar
    ldr x22, [sp], #16
    ldp x1, x20, [sp], #16
    subs x1, x1, #1
    b.ne _spaces_loop
_spaces_done:
    NEXT

// C, ( char -- )  store char at HERE, advance HERE by 1
XCCOMMA:
    mov w0, w20
    ldr x20, [x22], #8
    adrp x1, here_ptr@page
    add x1, x1, here_ptr@pageoff
    ldr x2, [x1]
    add x3, x2, #1
    adrp x4, user_dict_area@page
    add x4, x4, user_dict_area@pageoff
    adrp x5, user_dict_size_cell@page
    add x5, x5, user_dict_size_cell@pageoff
    ldr x5, [x5]
    add x5, x4, x5
    cmp x3, x5
    b.hi 1f
    strb w0, [x2]
    str x3, [x1]
    NEXT
1:
    adrp x0, str_dict_full@page
    add  x0, x0, str_dict_full@pageoff
    bl   _print_string_svc
    b    _error_abandon

// S>D ( n -- d )  sign-extend single to double; hi cell is TOS
XSTOD:
    str x20, [x22, #-8]!           // lo = n under
    asr x20, x20, #63              // hi = 0 or -1
    NEXT

// 2* ( x1 -- x2 )  x2 = x1 shifted left 1 (×2)
XTWOSTAR:
    lsl x20, x20, #1
    NEXT

// 2/ ( x1 -- x2 )  arithmetic shift right 1
XTWOSLASH:
    asr x20, x20, #1
    NEXT

// 2@ ( a-addr -- x1 x2 )  x1 at a-addr (lo), x2 at a-addr+cell (hi/TOS)
XTWOFETCH:
    mov x0, x20
    ldr x1, [x0]                   // lo
    ldr x20, [x0, #8]              // hi
    str x1, [x22, #-8]!
    NEXT

// 2! ( x1 x2 a-addr -- )  store x1 at a-addr, x2 at a-addr+cell
XTWOSTORE:
    mov x0, x20                    // a-addr
    ldr x2, [x22], #8              // x2 (more significant)
    ldr x1, [x22], #8              // x1 (less significant)
    ldr x20, [x22], #8
    str x1, [x0]
    str x2, [x0, #8]
    NEXT

// ============================================================================
// Double-cell arithmetic (ANS Core)
// Doubles on stack: lo under, hi in TOS (same as S>D).
// ============================================================================

// UM* ( u1 u2 -- ud )  unsigned multiply → double
XUMSTAR:
    mov x1, x20                    // u2
    ldr x0, [x22], #8              // u1
    mul x2, x0, x1                 // lo
    umulh x20, x0, x1              // hi
    str x2, [x22, #-8]!            // lo under
    NEXT

// M* ( n1 n2 -- d )  signed multiply → double
XMSTAR:
    mov x1, x20
    ldr x0, [x22], #8
    mul x2, x0, x1
    smulh x20, x0, x1
    str x2, [x22, #-8]!
    NEXT

// ============================================================================
// Double-Number word set (8.6) — stack doubles: lo under, hi in TOS
// ============================================================================

// D+ ( d1 d2 -- d3 )
XDPLUS:
    // TOS=hi2; under: lo2, hi1, lo1
    ldr x3, [x22], #8              // lo2
    ldr x2, [x22], #8              // hi1
    ldr x1, [x22], #8              // lo1
    // x20 = hi2
    adds x1, x1, x3                // lo sum
    adc  x20, x2, x20              // hi sum + carry
    str  x1, [x22, #-8]!
    NEXT

// D- ( d1 d2 -- d3 )
XDMINUS:
    ldr x3, [x22], #8              // lo2
    ldr x2, [x22], #8              // hi1
    ldr x1, [x22], #8              // lo1
    // x20 = hi2
    subs x1, x1, x3
    sbc  x20, x2, x20
    str  x1, [x22, #-8]!
    NEXT

// DNEGATE ( d1 -- d2 )
XDNEGATE:
    ldr x1, [x22]                  // lo
    mov x0, xzr
    subs x1, x0, x1
    sbc  x20, x0, x20
    str  x1, [x22]
    NEXT

// DABS ( d -- ud )
XDABS:
    tbnz x20, #63, 1f
    NEXT
1:
    // fall through to DNEGATE logic
    ldr x1, [x22]
    mov x0, xzr
    subs x1, x0, x1
    sbc  x20, x0, x20
    str  x1, [x22]
    NEXT

// D2* ( xd1 -- xd2 )
XD2STAR:
    ldr x1, [x22]
    lsl x20, x20, #1
    orr x20, x20, x1, lsr #63
    lsl x1, x1, #1
    str x1, [x22]
    NEXT

// D2/ ( xd1 -- xd2 )  arithmetic shift right
XD2SLASH:
    ldr x1, [x22]
    extr x1, x20, x1, #1           // lo = (hi:lo) >> 1
    asr  x20, x20, #1
    str  x1, [x22]
    NEXT

// D0= ( xd -- flag )
XD0EQUAL:
    ldr x1, [x22], #8
    orr x1, x1, x20
    cmp x1, #0
    csetm x20, eq
    NEXT

// D0< ( d -- flag )
XD0LESS:
    cmp x20, #0
    csetm x20, lt
    add x22, x22, #8               // drop lo
    NEXT

// D= ( xd1 xd2 -- flag )
XDEQUAL:
    ldr x3, [x22], #8              // lo2
    ldr x2, [x22], #8              // hi1
    ldr x1, [x22], #8              // lo1
    cmp x1, x3
    ccmp x2, x20, #0, eq
    csetm x20, eq
    NEXT

// D< ( d1 d2 -- flag ) signed
XDLESS:
    ldr x3, [x22], #8              // lo2
    ldr x2, [x22], #8              // hi1
    ldr x1, [x22], #8              // lo1
    cmp x2, x20
    b.lt 1f
    b.gt 2f
    cmp x1, x3
    csetm x20, lo
    NEXT
1:  mov x20, #-1
    NEXT
2:  mov x20, #0
    NEXT

// DU< ( ud1 ud2 -- flag ) unsigned
XDULESS:
    ldr x3, [x22], #8              // lo2
    ldr x2, [x22], #8              // hi1
    ldr x1, [x22], #8              // lo1
    cmp x2, x20
    b.lo 1f
    b.hi 2f
    cmp x1, x3
    csetm x20, lo
    NEXT
1:  mov x20, #-1
    NEXT
2:  mov x20, #0
    NEXT

// DMIN ( d1 d2 -- d3 ) — if d1 < d2 keep d1 else d2
XDMIN:
    // stack under TOS: lo2, hi1, lo1
    ldr x3, [x22]                  // lo2
    ldr x2, [x22, #8]              // hi1
    ldr x1, [x22, #16]             // lo1
    cmp x2, x20
    b.lt _dmin_d1
    b.gt _dmin_d2
    cmp x1, x3
    b.ls _dmin_d1
_dmin_d2:
    // keep d2: [lo2] TOS=hi2
    str x3, [x22, #16]
    add x22, x22, #16
    NEXT
_dmin_d1:
    // keep d1: [lo1] TOS=hi1
    mov x20, x2
    add x22, x22, #16
    NEXT

// DMAX ( d1 d2 -- d3 )
XDMAX:
    ldr x3, [x22]
    ldr x2, [x22, #8]
    ldr x1, [x22, #16]
    cmp x2, x20
    b.gt _dmax_d1
    b.lt _dmax_d2
    cmp x1, x3
    b.hs _dmax_d1
_dmax_d2:
    str x3, [x22, #16]
    add x22, x22, #16
    NEXT
_dmax_d1:
    mov x20, x2
    add x22, x22, #16
    NEXT

// D>S ( d -- n )  convert double to single (discard high; lo is result)
XDTOS:
    ldr x20, [x22], #8             // lo → TOS, drop hi
    NEXT

// M+ ( d1 n -- d2 )  d2 = d1 + S>D n
XMPLUS:
    // TOS=n; under: hi, lo
    ldr x2, [x22], #8              // hi
    ldr x1, [x22], #8              // lo
    // sign-extend n to hi_n
    asr x3, x20, #63
    adds x1, x1, x20
    adc  x20, x2, x3
    str  x1, [x22, #-8]!
    NEXT

// 2ROT ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 )
// rotate three cell-pairs left
XTWOROT:
    // TOS=x6; stack: x5,x4,x3,x2,x1
    ldr x5, [x22], #8
    ldr x4, [x22], #8
    ldr x3, [x22], #8
    ldr x2, [x22], #8
    ldr x1, [x22], #8
    // want: x3 x4 x5 x6 x1 x2(TOS)
    str x3, [x22, #-8]!
    str x4, [x22, #-8]!
    str x5, [x22, #-8]!
    str x20, [x22, #-8]!           // x6
    str x1, [x22, #-8]!
    mov x20, x2
    NEXT

// COMPARE ( c-addr1 u1 c-addr2 u2 -- n )  n = -1/0/1
XCOMPARE:
    // TOS=u2; under: ca2, u1, ca1
    mov x3, x20                    // u2
    ldr x2, [x22], #8              // ca2
    ldr x1, [x22], #8              // u1
    ldr x0, [x22], #8              // ca1
    cmp x1, x3
    csel x4, x1, x3, lo            // min len
    mov x5, #0
1:
    cmp x5, x4
    b.hs 2f
    ldrb w6, [x0, x5]
    ldrb w7, [x2, x5]
    cmp w6, w7
    b.ne 3f
    add x5, x5, #1
    b 1b
3:
    cmp w6, w7
    mov x20, #1
    b.hi 4f
    mov x20, #-1
4:  NEXT
2:
    cmp x1, x3
    b.eq 5f
    mov x20, #1
    b.hi 4b
    mov x20, #-1
    NEXT
5:  mov x20, #0
    NEXT

// SEARCH ( c-addr1 u1 c-addr2 u2 -- c-addr3 u3 flag )
// flag true: c-addr3/u3 is remainder of haystack at match; false: original ca1 u1
XSEARCH:
    mov x3, x20                    // u2 needle len
    ldr x2, [x22], #8              // ca2 needle
    ldr x1, [x22], #8              // u1 hay len
    ldr x0, [x22], #8              // ca1 hay
    // save originals for not-found path
    mov x9, x0
    mov x10, x1
    mov x4, #0                     // offset
    // empty needle matches at start
    cbz x3, 8f
1:
    subs x5, x1, x4                // remaining
    b.lo 9f
    cmp x5, x3
    b.lo 9f
    mov x6, #0
2:
    cmp x6, x3
    b.hs 8f
    add x7, x0, x4
    ldrb w8, [x7, x6]
    ldrb w11, [x2, x6]
    cmp w8, w11
    b.ne 3f
    add x6, x6, #1
    b 2b
3:
    add x4, x4, #1
    b 1b
8:
    add x0, x0, x4
    sub x1, x1, x4
    str x0, [x22, #-8]!
    str x1, [x22, #-8]!
    mov x20, #-1
    NEXT
9:
    str x9, [x22, #-8]!
    str x10, [x22, #-8]!
    mov x20, #0
    NEXT

// _udivmod128: unsigned (x1:x0) / x2 → quot x3, rem x4
// Pre: x2 != 0. If x1 >= x2 (quotient won't fit 64 bits), returns quot=-1, rem=x0.
// Invariant long division: remainder always restored to < divisor (at most one sub
// after 2*r+bit, with overflow handling when r's top bit was set).
_udivmod128:
    cbz x2, _udm_div0
    cmp x1, x2
    b.hs _udm_ovf
    mov x3, xzr                    // quot
    mov x4, xzr                    // rem
    mov x5, #128                   // bit index 127..0
_udm_bit:
    sub x5, x5, #1
    // bit = bit x5 of (x1:x0)
    cmp x5, #64
    b.hs 1f
    lsr x6, x0, x5
    b 2f
1:
    sub x7, x5, #64
    lsr x6, x1, x7
2:
    and x6, x6, #1
    // ov = rem top bit before shift
    lsr x7, x4, #63
    lsl x4, x4, #1
    orr x4, x4, x6
    lsl x3, x3, #1
    // if ov || rem >= div: rem -= div, quot |= 1
    cbnz x7, 3f
    cmp x4, x2
    b.lo 4f
3:
    sub x4, x4, x2
    orr x3, x3, #1
4:
    cbnz x5, _udm_bit
    ret
_udm_div0:
_udm_ovf:
    mov x3, #-1
    mov x4, x0
    ret

// UM/MOD ( ud u1 -- u2 u3 )  urem uquot ; ud = ulo under, uhi TOS before u1
XUMMOD:
    mov x2, x20                    // u1 divisor
    ldr x1, [x22], #8              // uhi
    ldr x0, [x22], #8              // ulo
    // prior TOS now at [x22]; compute
    stp x0, x1, [sp, #-16]!        // save dividend for clarity
    // x0,x1,x2 already set
    bl _udivmod128
    add sp, sp, #16
    // stack: push rem, TOS=quot. Prior stack item still at [x22].
    str x4, [x22, #-8]!            // rem under
    mov x20, x3                    // quot
    NEXT

// SM/REM ( d1 n1 -- n2 n3 )  symmetric (toward 0) rem, quot
// d1 = dlo under, dhi TOS before n1
XSMREM:
    mov x5, x20                    // n1 (signed divisor)
    ldr x4, [x22], #8              // dhi
    ldr x3, [x22], #8              // dlo
    // signs on stack (x6/x7 clobbered by _udivmod128)
    cmp x4, #0
    cset x6, lt                    // sign dividend
    cmp x5, #0
    cset x7, lt                    // sign divisor
    stp x6, x7, [sp, #-16]!
    str x5, [sp, #-16]!            // keep signed divisor (unused here)
    // abs dividend → x1:x0
    mov x0, x3
    mov x1, x4
    cbz x6, 1f
    mvn x0, x0
    mvn x1, x1
    adds x0, x0, #1
    adc x1, x1, xzr
1:
    mov x2, x5
    cbz x7, 2f
    neg x2, x2
2:
    cbz x2, 3f
    bl _udivmod128
    ldp x5, xzr, [sp], #16         // drop saved divisor slot
    ldp x6, x7, [sp], #16          // restore signs
    // rem sign = dividend; quot sign = xor
    cbz x6, 4f
    neg x4, x4
4:
    eor x8, x6, x7
    cbz x8, 5f
    neg x3, x3
5:
    str x4, [x22, #-8]!
    mov x20, x3
    NEXT
3:
    add sp, sp, #32
    mov x3, #-1
    mov x4, xzr
    str x4, [x22, #-8]!
    mov x20, x3
    NEXT

// FM/MOD ( d1 n1 -- n2 n3 )  floored rem, quot
// Like SM/REM then if rem!=0 and rem/divisor different signs: q--, r+=divisor
XFMMOD:
    mov x5, x20
    ldr x4, [x22], #8
    ldr x3, [x22], #8
    cmp x4, #0
    cset x6, lt
    cmp x5, #0
    cset x7, lt
    stp x6, x7, [sp, #-16]!
    str x5, [sp, #-16]!            // signed divisor for floor adjust
    mov x0, x3
    mov x1, x4
    cbz x6, 1f
    mvn x0, x0
    mvn x1, x1
    adds x0, x0, #1
    adc x1, x1, xzr
1:
    mov x2, x5
    cbz x7, 2f
    neg x2, x2
2:
    cbz x2, 9f
    bl _udivmod128
    ldr x5, [sp], #16              // divisor
    ldp x6, x7, [sp], #16          // signs
    cbz x6, 3f
    neg x4, x4
3:
    eor x8, x6, x7
    cbz x8, 4f
    neg x3, x3
4:
    cbz x4, 5f
    eor x8, x4, x5
    tbz x8, #63, 5f                // same sign → done
    sub x3, x3, #1
    add x4, x4, x5
5:
    str x4, [x22, #-8]!
    mov x20, x3
    NEXT
9:
    add sp, sp, #32
    mov x3, #-1
    mov x4, xzr
    str x4, [x22, #-8]!
    mov x20, x3
    NEXT

// CONTAINS ( hay-a hay-u ned-a ned-u -- flag )
// True if needle appears in haystack (ASCII case-insensitive).
// Empty needle => true.
// Stack: x20=ned-u, [DSP]=ned-a, [DSP+8]=hay-u, [DSP+16]=hay-a
XCONTAINS:
    mov x4, x20                    // ned-u
    ldr x3, [x22], #8              // ned-a
    ldr x2, [x22], #8              // hay-u
    ldr x1, [x22], #8              // hay-a
    // now [x22] = previous TOS; x20 still stale
    cbz x4, _cont_yes
    cmp x2, x4
    b.lo _cont_no
    sub x5, x2, x4
    add x5, x5, #1                 // positions to try
    mov x6, #0                     // i
_cont_i:
    cmp x6, x5
    b.hs _cont_no
    mov x7, #0                     // j
_cont_j:
    cmp x7, x4
    b.hs _cont_yes
    add x8, x1, x6
    add x8, x8, x7
    ldrb w9, [x8]
    ldrb w10, [x3, x7]
    cmp w9, #'a'
    b.lo 1f
    cmp w9, #'z'
    b.hi 1f
    sub w9, w9, #32
1:
    cmp w10, #'a'
    b.lo 2f
    cmp w10, #'z'
    b.hi 2f
    sub w10, w10, #32
2:
    cmp w9, w10
    b.ne _cont_next_i
    add x7, x7, #1
    b _cont_j
_cont_next_i:
    add x6, x6, #1
    b _cont_i
_cont_yes:
    // prior TOS already at [x22]; replace ned-u with flag
    mov x20, #-1
    NEXT
_cont_no:
    mov x20, #0
    NEXT

// EVALUATE ( c-addr u -- )  nest SOURCE and interpret the string
XEVALUATE:
    mov x1, x20                    // u
    ldr x0, [x22], #8              // c-addr
    ldr x20, [x22], #8
    stp x0, x1, [sp, #-16]!        // preserve across _push_source
    bl _push_source
    ldp x0, x1, [sp], #16
    bl _set_source
    // SOURCE-ID = -1 (string)
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    mov x1, #-1
    str x1, [x0]
    b _interpret_loop

// CATCH ( i*x xt -- j*x 0 | i*x n )
// R-stack frame (top first): saved_IP, saved_DSP, saved_TOS, prev_handler
// handler points at saved_IP.
XCATCH:
    mov x5, x20                    // xt
    ldr x20, [x22], #8             // pop xt → prior TOS
    adrp x7, throw_handler@page
    add x7, x7, throw_handler@pageoff
    ldr x2, [x7]
    str x2, [x23, #-8]!            // prev_handler
    str x20, [x23, #-8]!           // saved_TOS
    str x22, [x23, #-8]!           // saved_DSP
    str x19, [x23, #-8]!           // saved_IP (resume after CATCH)
    str x23, [x7]                  // handler = &saved_IP
    // Return trampoline: NEXT after xt → catch_ok entry
    adrp x0, cfa_catch_ok@page
    add x0, x0, cfa_catch_ok@pageoff
    ldr x0, [x0]
    adrp x1, catch_ok_cell@page
    add x1, x1, catch_ok_cell@pageoff
    str x0, [x1]
    mov x19, x1                    // IP → catch_ok_cell → XCATCH_OK after xt
    mov x21, x5                    // W = xt (CFA)
    ldr x1, [x21]                  // code field (same as EXECUTE)
    br x1

// Normal completion of CATCH'd xt
XCATCH_OK:
    adrp x7, throw_handler@page
    add x7, x7, throw_handler@pageoff
    ldr x1, [x7]
    cbz x1, _cok_push0
    mov x23, x1
    ldr x19, [x23], #8             // resume IP
    add x23, x23, #16              // skip DSP + TOS (keep xt results)
    ldr x0, [x23], #8              // prev_handler
    str x0, [x7]
_cok_push0:
    str x20, [x22, #-8]!
    mov x20, #0
    NEXT

// THROW ( k -- )  0 THROW is a no-op drop; nonzero restores CATCH frame
XTHROW:
    cbz x20, _throw_zero
    mov x5, x20                    // k
    adrp x7, throw_handler@page
    add x7, x7, throw_handler@pageoff
    ldr x1, [x7]
    cbz x1, _throw_abort
    mov x23, x1
    ldr x19, [x23], #8             // IP
    ldr x22, [x23], #8             // DSP
    ldr x20, [x23], #8             // TOS
    ldr x0, [x23], #8              // prev_handler
    str x0, [x7]
    str x20, [x22, #-8]!
    mov x20, x5                    // throw code
    NEXT
_throw_zero:
    ldr x20, [x22], #8
    NEXT
_throw_abort:
    // Uncaught THROW (e.g. typing ?COMP at the console): print code, soft-abort
    // the current line. Do NOT go through full _do_quit — under the embed host
    // that can leave the evaluate path in a bad state. Clear stacks, abandon
    // the rest of SOURCE, and return via the normal interpret-done path.
    stp  x5, xzr, [sp, #-16]!      // save throw code
    adrp x0, str_uncaught_throw@page
    add  x0, x0, str_uncaught_throw@pageoff
    bl   _print_string_svc
    ldr  x0, [sp], #16
    // print absolute value if negative (common ANS codes are negative)
    cmp  x0, #0
    cneg x0, x0, lt
    bl   _print_unsigned
    mov  x0, #10
    bl   _putchar
    // clear data stack
    adrp x22, data_stack@page
    add  x22, x22, data_stack@pageoff
    add  x22, x22, #4096
    mov  x20, #0
    // clear return stack + CATCH nesting (leave no DOCOL frames)
    adrp x23, return_stack@page
    add  x23, x23, return_stack@pageoff
    add  x23, x23, #2048
    adrp x0, throw_handler@page
    add  x0, x0, throw_handler@pageoff
    str  xzr, [x0]
    b    _error_abandon

// QUIT ( -- )  ANS outer interpreter entry (CODE — not a colon trampoline).
// Empty return stack, interpret state, existing prompt/line/interpret loop.
// Does not empty the data stack (ANS); ABORT clears the data stack first.
XQUIT:
    b _do_quit

// PARSE-NAME ( -- c-addr u )  ANS Core Ext
// Skip leading spaces/tabs; parse to next space/tab/newline/end.
// Result points into SOURCE (transient across next parse).
XPARSE_NAME:
    bl _cursor_load
    mov x2, x0
    bl _source_end
    mov x9, x0
_pn_skip:
    cmp x2, x9
    b.hs _pn_empty
    ldrb w4, [x2]
    cbz w4, _pn_empty
    cmp w4, #32
    b.eq _pn_sk
    cmp w4, #9
    b.eq _pn_sk
    cmp w4, #10
    b.eq _pn_sk
    cmp w4, #13
    b.eq _pn_sk
    b _pn_start
_pn_sk:
    add x2, x2, #1
    b _pn_skip
_pn_start:
    mov x3, x2
_pn_scan:
    cmp x2, x9
    b.hs _pn_end
    ldrb w4, [x2]
    cbz w4, _pn_end
    cmp w4, #32
    b.eq _pn_end
    cmp w4, #9
    b.eq _pn_end
    cmp w4, #10
    b.eq _pn_end
    cmp w4, #13
    b.eq _pn_end
    add x2, x2, #1
    b _pn_scan
_pn_end:
    sub x5, x2, x3                 // u
    // consume trailing delimiter if space-class
    cmp x2, x9
    b.hs _pn_store
    ldrb w4, [x2]
    cbz w4, _pn_store
    cmp w4, #32
    b.eq _pn_cons
    cmp w4, #9
    b.eq _pn_cons
    cmp w4, #10
    b.eq _pn_cons
    cmp w4, #13
    b.ne _pn_store
_pn_cons:
    add x2, x2, #1
_pn_store:
    mov x0, x2
    // save c-addr/u across _cursor_store
    str x3, [x23, #-8]!
    str x5, [x23, #-8]!
    bl _cursor_store
    ldr x5, [x23], #8
    ldr x3, [x23], #8
    str x20, [x22, #-8]!
    mov x20, x3
    str x20, [x22, #-8]!
    mov x20, x5
    NEXT
_pn_empty:
    mov x0, x2
    mov x3, x2                     // c-addr = end
    bl _cursor_store
    str x20, [x22, #-8]!
    mov x20, x3
    str x20, [x22, #-8]!
    mov x20, #0
    NEXT

// PARSE ( char "ccc<char>" -- c-addr u )
// From >IN to delimiter or end of SOURCE; consumes delimiter if found.
// Does not skip leading delimiters (ANS PARSE).
XPARSE:
    mov w7, w20                     // delimiter
    bl _cursor_load
    mov x9, x0                      // c-addr = start (x9 not clobbered by helpers)
    mov x3, x9
    bl _source_end
    mov x6, x0                      // end
_parse_scan:
    cmp x3, x6
    b.hs _parse_eos
    ldrb w4, [x3]
    cbz w4, _parse_eos
    cmp w4, w7
    b.eq _parse_found
    add x3, x3, #1
    b _parse_scan
_parse_found:
    sub x5, x3, x9                  // u
    add x3, x3, #1                  // skip delimiter
    mov x0, x3
    bl _cursor_store
    b _parse_push
_parse_eos:
    sub x5, x3, x9
    mov x0, x3
    bl _cursor_store
_parse_push:
    mov x20, x9
    str x20, [x22, #-8]!
    mov x20, x5
    NEXT

// WORD ( char "<chars>ccc<char>" -- c-addr )
// Skip leading delimiters, parse until delimiter, store counted string
// in word_scratch (transient). Space delimiter also skips TAB/CR/LF.
XWORD:
    mov w7, w20                     // delimiter
    bl _cursor_load
    mov x2, x0
    bl _source_end
    mov x9, x0                      // end of SOURCE
_word_skip:
    cmp x2, x9
    b.hs _word_empty
    ldrb w4, [x2]
    cbz w4, _word_empty
    cmp w7, #32
    b.ne _word_skip_exact
    cmp w4, #32
    b.eq _word_skip_adv
    cmp w4, #9
    b.eq _word_skip_adv
    cmp w4, #10
    b.eq _word_skip_adv
    cmp w4, #13
    b.eq _word_skip_adv
    b _word_start
_word_skip_exact:
    cmp w4, w7
    b.ne _word_start
_word_skip_adv:
    add x2, x2, #1
    b _word_skip
_word_start:
    mov x3, x2                      // start of token
_word_scan:
    cmp x2, x9
    b.hs _word_end
    ldrb w4, [x2]
    cbz w4, _word_end
    cmp w7, #32
    b.ne _word_scan_exact
    cmp w4, #32
    b.eq _word_end
    cmp w4, #9
    b.eq _word_end
    cmp w4, #10
    b.eq _word_end
    cmp w4, #13
    b.eq _word_end
    add x2, x2, #1
    b _word_scan
_word_scan_exact:
    cmp w4, w7
    b.eq _word_end
    add x2, x2, #1
    b _word_scan
_word_end:
    sub x5, x2, x3                  // length
    cmp x2, x9
    b.hs _word_store
    ldrb w4, [x2]
    cbz w4, _word_store
    add x2, x2, #1                  // consume delimiter
_word_store:
    // Save token start/len across _cursor_store (clobbers x0-x3)
    mov x6, x3                      // token start
    mov x7, x5                      // len
    mov x0, x2
    bl _cursor_store
    mov x3, x6
    mov x5, x7
    cmp x5, #63
    b.ls _word_len_ok
    mov x5, #63
_word_len_ok:
    adrp x6, word_scratch@page
    add x6, x6, word_scratch@pageoff
    strb w5, [x6]
    mov x1, #0
_word_copy:
    cmp x1, x5
    b.ge _word_done
    ldrb w4, [x3, x1]
    add x8, x6, #1
    strb w4, [x8, x1]
    add x1, x1, #1
    b _word_copy
_word_done:
    mov x20, x6
    NEXT
_word_empty:
    mov x0, x2
    bl _cursor_store
    adrp x6, word_scratch@page
    add x6, x6, word_scratch@pageoff
    strb wzr, [x6]
    mov x20, x6
    NEXT

// \ ( -- ) IMMEDIATE  discard rest of parse area (to end of line)
// When BLK is nonzero (block source): skip to next 64-char line boundary
// (classic screen width), not a newline (blocks are space-filled, no \n).
// Note: _source_end clobbers x0/x1 — keep cursor in x10.
XBACKSLASH:
    adrp x0, blk_var@page
    add  x0, x0, blk_var@pageoff
    ldr  x0, [x0]
    cbnz x0, _bs_block
    bl _cursor_load
    mov x10, x0                     // cursor
    bl _source_end
    mov x9, x0                      // end
_bs_loop:
    cmp x10, x9
    b.hs _bs_done
    ldrb w2, [x10]
    cbz w2, _bs_done
    cmp w2, #10
    b.eq _bs_done
    add x10, x10, #1
    b _bs_loop
_bs_done:
    mov x0, x10
    bl _cursor_store
    NEXT
_bs_block:
    // >IN := min( source_len, ((>IN / 64) + 1) * 64 )
    adrp x0, to_in_var@page
    add  x0, x0, to_in_var@pageoff
    ldr  x1, [x0]                   // >IN
    adrp x2, source_len@page
    add  x2, x2, source_len@pageoff
    ldr  x2, [x2]                   // len
    // line end offset
    mov  x3, #64
    udiv x4, x1, x3
    add  x4, x4, #1
    mul  x4, x4, x3                 // next line start
    cmp  x4, x2
    csel x4, x2, x4, hi
    str  x4, [x0]
    adrp x0, source_addr@page
    add  x0, x0, source_addr@pageoff
    ldr  x0, [x0]
    add  x0, x0, x4
    adrp x1, word_cursor@page
    add  x1, x1, word_cursor@pageoff
    str  x0, [x1]
    NEXT

// \S ( -- ) IMMEDIATE  TZForth / F-PC model:
//   Stop further interpretation of the *current* SOURCE (whole INCLUDE/FLOAD
//   buffer, EVALUATE string, or single console kernel_eval line). Does NOT
//   clear STATE. Nested INCLUDE: only the innermost file stops; outer SOURCE
//   resumes (so `FLOAD f 123 .` still runs tokens after FLOAD).
//   When SOURCE-ID == 0 (console), also set repl_batch_stop so the host can
//   drop remaining lines of a multi-line paste (see ConsoleView).
//   Case-insensitive FIND: `\s` (Hayes) matches this name.
XBACKSLASH_S:
    // Pin >IN and word_cursor at end of current SOURCE (ignore rest of line/file)
    adrp x0, source_len@page
    add  x0, x0, source_len@pageoff
    ldr  x1, [x0]                   // u
    adrp x0, to_in_var@page
    add  x0, x0, to_in_var@pageoff
    str  x1, [x0]
    adrp x0, source_addr@page
    add  x0, x0, source_addr@pageoff
    ldr  x0, [x0]
    add  x0, x0, x1
    adrp x2, word_cursor@page
    add  x2, x2, word_cursor@pageoff
    str  x0, [x2]
    // Console (SOURCE-ID 0): request host to stop multi-line paste batch
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    ldr  x0, [x0]
    cbnz x0, 1f                     // file or EVALUATE: only end this SOURCE
    adrp x0, repl_batch_stop@page
    add  x0, x0, repl_batch_stop@pageoff
    mov  x1, #1
    str  x1, [x0]
1:
    NEXT

// ( ( -- ) IMMEDIATE  paren comment; discard until ')'
XPAREN:
    bl _cursor_load
    mov x10, x0                     // cursor
    bl _source_end
    mov x9, x0                      // end
_par_loop:
    cmp x10, x9
    b.hs _par_done
    ldrb w2, [x10]
    cbz w2, _par_done
    cmp w2, #41
    b.eq _par_found
    add x10, x10, #1
    b _par_loop
_par_found:
    add x10, x10, #1
_par_done:
    mov x0, x10
    bl _cursor_store
    NEXT

// SOURCE ( -- c-addr u )  ANS
XSOURCE:
    str x20, [x22, #-8]!
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x20, [x0]
    NEXT

// SOURCE-ID ( -- 0 | -1 | fileid )  ANS
// 0 = user input device, -1 = EVALUATE string, >0 = file-ish INCLUDE buffer
XSOURCE_ID:
    str x20, [x22, #-8]!
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    ldr x20, [x0]
    NEXT

// REFILL ( -- flag )  ANS
// Terminal (SOURCE-ID 0): read a line into input_buffer, true (false on EOF).
// Block source (BLK nonzero): advance to next block, true (Hayes blocktest).
// EVALUATE string / INCLUDE file without BLK: false.
XREFILL:
    adrp x0, blk_var@page
    add  x0, x0, blk_var@pageoff
    ldr  x0, [x0]
    cbnz x0, _refill_block
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    ldr x0, [x0]
    cmp x0, #0
    b.ne _refill_false
    adrp x0, input_buffer@page
    add x0, x0, input_buffer@pageoff
    mov x1, #1023
    SAVE_VM
    bl _read_line
    RESTORE_VM
    cbz x0, _refill_eof
    adrp x0, input_buffer@page
    add x0, x0, input_buffer@pageoff
    mov x1, #0
1:
    ldrb w2, [x0, x1]
    cbz w2, 2f
    add x1, x1, #1
    b 1b
2:
    bl _set_source
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    str xzr, [x0]
    str x20, [x22, #-8]!
    mov x20, #-1
    NEXT
_refill_block:
    // BLK++ ; (BLOCK-LOAD) that block into block_buf; SOURCE = block_buf 1024; >IN=0
    adrp x0, blk_var@page
    add  x0, x0, blk_var@pageoff
    ldr  x1, [x0]
    add  x1, x1, #1
    str  x1, [x0]
    mov  x0, x1
    bl   _block_load_nr            // x0=block# → load into block_buf (ignore errors)
    adrp x0, block_buf@page
    add  x0, x0, block_buf@pageoff
    mov  x1, #1024
    bl   _set_source
    // keep SOURCE-ID as-is (usually -1 from EVALUATE during LOAD)
    str  x20, [x22, #-8]!
    mov  x20, #-1                  // true
    NEXT
_refill_eof:
_refill_false:
    str x20, [x22, #-8]!
    mov x20, #0
    NEXT

// ACCEPT ( c-addr +n1 -- +n2 )  ANS
// Receive a string of at most +n1 characters into c-addr; return count.
// Uses the line editor when stdin is a TTY.
XACCEPT:
    // ( c-addr +n1 )  TOS=+n1
    mov x1, x20                    // +n1
    ldr x0, [x22], #8              // c-addr; x22 -> prior TOS cell
    cmp x1, #0
    b.gt 1f
    mov x20, #0                    // +n2 = 0
    NEXT
1:
    // Save VM + args; _read_line uses x19-x26
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x0, x1, [sp, #-16]!        // c-addr, +n1
    mov x19, x0
    add x1, x1, #1                 // room for NUL
    mov x0, x19
    bl _read_line
    mov x2, x0                     // buf or 0
    ldp x0, x1, [sp], #16          // c-addr, +n1
    mov x3, #0                     // len
    cbz x2, 3f
2:
    cmp x3, x1
    b.hs 3f
    ldrb w4, [x2, x3]
    cbz w4, 3f
    add x3, x3, #1
    b 2b
3:
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    // x22 restored to post-c-addr-pop (prior under); TOS = n2
    mov x20, x3
    NEXT

// >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )  ANS
// Convert digits from string in BASE into double ud1; leave rest of string.
// ud is lo under, hi TOS (same as S>D). Character set: 0-9A-Z (case-insensitive).
XTONUMBER:
    // stack: ( udlo udhi c-addr u )  TOS=u
    mov x4, x20                    // u
    ldr x3, [x22], #8              // c-addr
    ldr x2, [x22], #8              // udhi
    ldr x1, [x22], #8              // udlo
    // BASE
    adrp x5, base_var@page
    add x5, x5, base_var@pageoff
    ldr x5, [x5]
    cmp x5, #2
    b.lo 8f
    cmp x5, #36
    b.ls 9f
8:
    mov x5, #10
9:
_tn_loop:
    cbz x4, _tn_done
    ldrb w6, [x3]
    // digit value
    sub w7, w6, #48
    cmp w7, #9
    b.ls _tn_dig
    mov w7, w6
    cmp w7, #'a'
    b.lo _tn_up
    cmp w7, #'z'
    b.hi _tn_stop
    sub w7, w7, #32
_tn_up:
    sub w7, w7, #'A'
    cmp w7, #25
    b.hi _tn_stop
    add w7, w7, #10
_tn_dig:
    cmp x7, x5
    b.hs _tn_stop
    // ud = ud * base + digit  (128-bit)
    // (x2:x1) * x5 + x7
    mul x8, x1, x5                 // lo*base low
    umulh x9, x1, x5               // lo*base high
    mul x10, x2, x5                // hi*base low (ignore hi*base high overflow)
    add x9, x9, x10
    adds x1, x8, x7
    adc x2, x9, xzr
    add x3, x3, #1
    sub x4, x4, #1
    b _tn_loop
_tn_stop:
_tn_done:
    // push udlo udhi c-addr u
    str x1, [x22, #-8]!
    str x2, [x22, #-8]!
    str x3, [x22, #-8]!
    mov x20, x4
    NEXT

// ENVIRONMENT? ( c-addr u -- false | i*x true )  ANS
// Recognized queries (minimal Core set + a few useful ones):
//   /COUNTED-STRING  ADDRESS-UNIT-BITS  CORE  CORE-EXT  FLOORED
//   MAX-CHAR  MAX-N  MAX-U  RETURN-STACK-CELLS  STACK-CELLS
XENVIRONMENT_Q:
    mov x1, x20                    // u
    ldr x0, [x22], #8              // c-addr
    // x0/x1 = query string; scan env_name_ptrs table
    mov x4, #0                     // index
_env_next:
    // load name pointer and length from table: each entry is .quad ptr, .quad len, then next
    // Simpler: fixed table of asciz names, parallel values
    cmp x4, #10                    // ENV_COUNT
    b.hs _env_no
    // name at env_name_ptrs[x4]
    adrp x5, env_name_ptrs@page
    add x5, x5, env_name_ptrs@pageoff
    ldr x5, [x5, x4, lsl #3]
    // strlen name
    mov x6, #0
1:
    ldrb w7, [x5, x6]
    cbz w7, 2f
    add x6, x6, #1
    b 1b
2:
    cmp x6, x1
    b.ne _env_cont
    // compare bytes case-sensitive (ANS names are uppercase)
    mov x7, #0
3:
    cmp x7, x6
    b.eq _env_yes
    ldrb w8, [x5, x7]
    ldrb w9, [x0, x7]
    cmp w8, w9
    b.ne _env_cont
    add x7, x7, #1
    b 3b
_env_cont:
    add x4, x4, #1
    b _env_next
_env_yes:
    // value kind in env_kinds[x4]: 0 = flag true only, 1 = single cell then true
    adrp x5, env_kinds@page
    add x5, x5, env_kinds@pageoff
    ldrb w5, [x5, x4]
    adrp x6, env_values@page
    add x6, x6, env_values@pageoff
    ldr x6, [x6, x4, lsl #3]
    cbz w5, _env_flag_only
    // push value, then true
    str x6, [x22, #-8]!
    mov x20, #-1
    NEXT
_env_flag_only:
    // boolean query: value is the flag (-1 present / 0 absent)
    mov x20, x6
    NEXT
_env_no:
    mov x20, #0
    NEXT

// >IN ( -- a-addr )  ANS variable
XTOIN:
    str x20, [x22, #-8]!
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    mov x20, x0
    NEXT

// (S") ( -- c-addr u )  runtime for compiled S" / ."
// In-line layout at IP:  cell len, then len bytes, then pad to 8.
XSLIT:
    ldr x0, [x19], #8               // length
    str x20, [x22, #-8]!
    mov x20, x19                    // c-addr of string bytes
    str x20, [x22, #-8]!
    mov x20, x0                     // u
    add x19, x19, x0
    add x19, x19, #7
    bic x19, x19, #7
    NEXT

// S" ( -- c-addr u | compile-time ) IMMEDIATE
// Parse is fully inlined so we never clobber VM regs via nested helpers.
XSQUOTE:
    // --- skip blanks; parse to " ---
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x9, [x0]                    // SOURCE base
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    mov x10, x0                     // & >IN
    ldr x11, [x10]                  // >IN
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x12, [x0]                   // SOURCE len
    add x1, x9, x11                 // cursor
    add x6, x9, x12                 // end
_sq_skip:
    cmp x1, x6
    b.hs _sq_body0
    ldrb w2, [x1]
    cmp w2, #32
    b.eq _sq_sk1
    cmp w2, #9
    b.ne _sq_body0
_sq_sk1:
    add x1, x1, #1
    b _sq_skip
_sq_body0:
    mov x2, x1                      // c-addr
_sq_scan:
    cmp x1, x6
    b.hs _sq_eos
    ldrb w3, [x1]
    cbz w3, _sq_eos
    cmp w3, #34
    b.eq _sq_found
    add x1, x1, #1
    b _sq_scan
_sq_found:
    sub x5, x1, x2                  // u
    add x1, x1, #1
    b _sq_commit
_sq_eos:
    sub x5, x1, x2
_sq_commit:
    sub x11, x1, x9
    str x11, [x10]                  // >IN
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    str x1, [x0]
    // x2=c-addr, x5=u  (x9-x12 free again except we keep x2,x5)
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    ldr x0, [x0]
    cbnz x0, _sq_comp
    // interpret: ( c-addr u )
    str x20, [x22, #-8]!
    mov x20, x2
    str x20, [x22, #-8]!
    mov x20, x5
    NEXT
_sq_comp:
    // Compile (S") , len , bytes , align.  x2=c-addr x5=u; save IP on R stack.
    str x19, [x23, #-8]!            // RPUSH IP
    str x2, [x23, #-8]!             // save c-addr
    str x5, [x23, #-8]!             // save u
    adrp x0, cfa_slit@page
    add x0, x0, cfa_slit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [x23]                   // peek u
    bl _compile_cell
    // copy u bytes from c-addr to HERE
    ldr x5, [x23], #8               // pop u
    ldr x2, [x23], #8               // pop c-addr
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x1, [x0]                    // dest
    mov x3, #0
_sq_cpy:
    cmp x3, x5
    b.ge _sq_al
    ldrb w4, [x2, x3]
    strb w4, [x1, x3]
    add x3, x3, #1
    b _sq_cpy
_sq_al:
    add x1, x1, x5
    add x1, x1, #7
    bic x1, x1, #7
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    str x1, [x0]
    ldr x19, [x23], #8              // RPOP IP
    NEXT

// (C") ( -- c-addr )  runtime: counted string inline at IP
// Layout: len byte, chars, pad to 8-byte boundary.
XCSTR:
    str x20, [x22, #-8]!
    mov x20, x19                   // c-addr of counted string
    ldrb w0, [x19]
    add x19, x19, x0
    add x19, x19, #1
    add x19, x19, #7
    bic x19, x19, #7
    NEXT

// C" ( -- c-addr ) IMMEDIATE  ANS counted string
// Interpret: counted copy in PAD. Compile: (C") + counted bytes + align.
XCQUOTE:
    // Parse to " (same style as S")
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x9, [x0]
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    mov x10, x0
    ldr x11, [x10]
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x12, [x0]
    add x1, x9, x11
    add x6, x9, x12
_cq_skip:
    cmp x1, x6
    b.hs _cq_body
    ldrb w2, [x1]
    cmp w2, #32
    b.eq _cq_sk1
    cmp w2, #9
    b.ne _cq_body
_cq_sk1:
    add x1, x1, #1
    b _cq_skip
_cq_body:
    mov x2, x1
_cq_scan:
    cmp x1, x6
    b.hs _cq_eos
    ldrb w3, [x1]
    cbz w3, _cq_eos
    cmp w3, #34
    b.eq _cq_found
    add x1, x1, #1
    b _cq_scan
_cq_found:
    sub x5, x1, x2
    add x1, x1, #1
    b _cq_commit
_cq_eos:
    sub x5, x1, x2
_cq_commit:
    sub x11, x1, x9
    str x11, [x10]
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    str x1, [x0]
    cmp x5, #255
    b.ls _cq_lenok
    mov x5, #255
_cq_lenok:
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    ldr x0, [x0]
    cbnz x0, _cq_comp
    // interpret → PAD counted string
    adrp x0, pad_buffer@page
    add x0, x0, pad_buffer@pageoff
    strb w5, [x0]
    mov x3, #0
1:
    cmp x3, x5
    b.ge 2f
    ldrb w4, [x2, x3]
    add x6, x0, #1
    strb w4, [x6, x3]
    add x3, x3, #1
    b 1b
2:
    str x20, [x22, #-8]!
    mov x20, x0
    NEXT
_cq_comp:
    str x19, [x23, #-8]!
    str x2, [x23, #-8]!
    str x5, [x23, #-8]!
    adrp x0, cfa_cstr@page
    add x0, x0, cfa_cstr@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x5, [x23], #8
    ldr x2, [x23], #8
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x1, [x0]
    strb w5, [x1], #1
    mov x3, #0
3:
    cmp x3, x5
    b.ge 4f
    ldrb w4, [x2, x3]
    strb w4, [x1, x3]
    add x3, x3, #1
    b 3b
4:
    add x1, x1, x5
    add x1, x1, #7
    bic x1, x1, #7
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    str x1, [x0]
    ldr x19, [x23], #8
    NEXT

// S\" ( -- c-addr u ) IMMEDIATE  ANS escaped string
// Escapes: \a \b \e \f \l \m \n \q \r \t \v \z \" \\ \xHH
// Interpret: expand into slit_esc_buf. Compile: (S") + expanded bytes.
XSESCAPE:
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x9, [x0]
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    mov x10, x0
    ldr x11, [x10]
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x12, [x0]
    add x1, x9, x11                // cursor
    add x6, x9, x12                // end
_se_skip:
    cmp x1, x6
    b.hs _se_body
    ldrb w2, [x1]
    cmp w2, #32
    b.eq _se_sk1
    cmp w2, #9
    b.ne _se_body
_se_sk1:
    add x1, x1, #1
    b _se_skip
_se_body:
    // Expand into slit_esc_buf (max 255)
    adrp x7, slit_esc_buf@page
    add x7, x7, slit_esc_buf@pageoff
    mov x5, #0                     // out len
_se_loop:
    cmp x1, x6
    b.hs _se_done
    ldrb w2, [x1]
    cbz w2, _se_done
    cmp w2, #34                    // "
    b.eq _se_endq
    cmp w2, #92                    // backslash
    b.eq _se_esc
    // ordinary char
    cmp x5, #255
    b.hs _se_adv
    strb w2, [x7, x5]
    add x5, x5, #1
_se_adv:
    add x1, x1, #1
    b _se_loop
_se_endq:
    add x1, x1, #1
    b _se_done
_se_esc:
    add x1, x1, #1
    cmp x1, x6
    b.hs _se_done
    ldrb w2, [x1]
    add x1, x1, #1
    // decode escape in w2 → w3 (char), or multi for \m \x
    cmp w2, #'a'
    b.eq _se_a
    cmp w2, #'b'
    b.eq _se_b
    cmp w2, #'e'
    b.eq _se_e
    cmp w2, #'f'
    b.eq _se_f
    cmp w2, #'l'
    b.eq _se_l
    cmp w2, #'m'
    b.eq _se_m
    cmp w2, #'n'
    b.eq _se_n
    cmp w2, #'q'
    b.eq _se_q
    cmp w2, #'r'
    b.eq _se_r
    cmp w2, #'t'
    b.eq _se_t
    cmp w2, #'v'
    b.eq _se_v
    cmp w2, #'z'
    b.eq _se_z
    cmp w2, #'"'
    b.eq _se_qq
    cmp w2, #'\\'
    b.eq _se_bs
    cmp w2, #'x'
    b.eq _se_hex
    // unknown: emit the char after backslash
    mov w3, w2
    b _se_put1
_se_a:  mov w3, #7
    b _se_put1
_se_b:  mov w3, #8
    b _se_put1
_se_e:  mov w3, #27
    b _se_put1
_se_f:  mov w3, #12
    b _se_put1
_se_l:  mov w3, #10
    b _se_put1
_se_n:  mov w3, #10
    b _se_put1
_se_q:  mov w3, #34
    b _se_put1
_se_r:  mov w3, #13
    b _se_put1
_se_t:  mov w3, #9
    b _se_put1
_se_v:  mov w3, #11
    b _se_put1
_se_z:  mov w3, #0
    b _se_put1
_se_qq: mov w3, #34
    b _se_put1
_se_bs: mov w3, #92
    b _se_put1
_se_m:
    // CR LF
    cmp x5, #254
    b.hs _se_loop
    mov w3, #13
    strb w3, [x7, x5]
    add x5, x5, #1
    mov w3, #10
    strb w3, [x7, x5]
    add x5, x5, #1
    b _se_loop
_se_hex:
    // \xHH — two hex digits
    mov w3, #0
    mov x4, #2
_se_hx:
    cbz x4, _se_put1
    cmp x1, x6
    b.hs _se_put1
    ldrb w2, [x1]
    // hex value
    sub w8, w2, #48
    cmp w8, #9
    b.ls _se_hd
    sub w8, w2, #'A'
    cmp w8, #5
    b.ls _se_hu
    sub w8, w2, #'a'
    cmp w8, #5
    b.hi _se_put1
    add w8, w8, #10
    b _se_hok
_se_hu:
    add w8, w8, #10
    b _se_hok
_se_hd:
_se_hok:
    add x1, x1, #1
    lsl w3, w3, #4
    orr w3, w3, w8
    sub x4, x4, #1
    b _se_hx
_se_put1:
    cmp x5, #255
    b.hs _se_loop
    strb w3, [x7, x5]
    add x5, x5, #1
    b _se_loop
_se_done:
    sub x11, x1, x9
    str x11, [x10]
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    str x1, [x0]
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    ldr x0, [x0]
    cbnz x0, _se_comp
    // interpret: ( c-addr u ) pointing at slit_esc_buf
    str x20, [x22, #-8]!
    mov x20, x7
    str x20, [x22, #-8]!
    mov x20, x5
    NEXT
_se_comp:
    str x19, [x23, #-8]!
    str x7, [x23, #-8]!            // buf
    str x5, [x23, #-8]!            // u
    adrp x0, cfa_slit@page
    add x0, x0, cfa_slit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [x23]                  // peek u
    bl _compile_cell
    ldr x5, [x23], #8
    ldr x2, [x23], #8
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x1, [x0]
    mov x3, #0
1:
    cmp x3, x5
    b.ge 2f
    ldrb w4, [x2, x3]
    strb w4, [x1, x3]
    add x3, x3, #1
    b 1b
2:
    add x1, x1, x5
    add x1, x1, #7
    bic x1, x1, #7
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    str x1, [x0]
    ldr x19, [x23], #8
    NEXT

// SAVE-INPUT ( -- xn ... x1 n )
// Saves SOURCE addr, len, >IN, SOURCE-ID, BLK; n=5.
// BLK is required so RESTORE can re-fetch a block after REFILL overwrote the buffer.
XSAVE_INPUT:
    str x20, [x22, #-8]!
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    adrp x0, blk_var@page
    add x0, x0, blk_var@pageoff
    ldr x20, [x0]
    str x20, [x22, #-8]!
    mov x20, #5
    NEXT

// RESTORE-INPUT ( xn ... x1 n -- flag )
// flag true (-1) = cannot restore; false (0) = ok.
// Accepts n=5 (addr len >in id blk) or legacy n=4 (addr len >in id).
XRESTORE_INPUT:
    cmp x20, #5
    b.eq _ri_n5
    cmp x20, #4
    b.ne _ri_fail
    // n=4: addr len >in id
    mov x5, #0                     // blk = 0
    b _ri_common
_ri_n5:
    ldr x5, [x22], #8              // BLK
_ri_common:
    ldr x0, [x22], #8              // source_id
    ldr x1, [x22], #8              // >IN
    ldr x2, [x22], #8              // len
    ldr x3, [x22], #8              // addr
    ldr x20, [x22], #8             // prior under
    // stash on data stack temporarily (VM regs free enough)
    str x20, [x22, #-8]!           // prior
    str x0, [x22, #-8]!            // id
    str x1, [x22, #-8]!            // >IN
    str x2, [x22, #-8]!            // len
    str x3, [x22, #-8]!            // addr
    str x5, [x22, #-8]!            // blk
    // Restore BLK
    adrp x4, blk_var@page
    add  x4, x4, blk_var@pageoff
    str  x5, [x4]
    cbz  x5, _ri_apply
    mov  x0, x5
    bl   _block_load_nr
    // force SOURCE to block_buf / 1024 when restoring a block
    adrp x3, block_buf@page
    add  x3, x3, block_buf@pageoff
    str  x3, [x22, #8]             // overwrite saved addr on stack (addr is at +8 from top? )
    // stack top-first: blk, addr, len, >in, id, prior
    // After pushes: [sp-ish via x22] layout: top=blk, then addr,len,>in,id,prior
    // Overwrite addr (second cell): x22 points at blk; addr at [x22,#8]
    mov  x2, #1024
    str  x2, [x22, #16]            // overwrite len
_ri_apply:
    ldr x5, [x22], #8              // blk (discard)
    ldr x3, [x22], #8              // addr
    ldr x2, [x22], #8              // len
    ldr x1, [x22], #8              // >IN
    ldr x0, [x22], #8              // id
    ldr x20, [x22], #8             // prior
    adrp x4, source_addr@page
    add x4, x4, source_addr@pageoff
    str x3, [x4]
    adrp x4, source_len@page
    add x4, x4, source_len@pageoff
    str x2, [x4]
    adrp x4, to_in_var@page
    add x4, x4, to_in_var@pageoff
    str x1, [x4]
    adrp x4, source_id_var@page
    add x4, x4, source_id_var@pageoff
    str x0, [x4]
    add x3, x3, x1
    adrp x4, word_cursor@page
    add x4, x4, word_cursor@pageoff
    str x3, [x4]
    str x20, [x22, #-8]!
    mov x20, #0
    NEXT
_ri_fail:
    mov x1, x20
    ldr x20, [x22], #8
1:
    cbz x1, 2f
    ldr x20, [x22], #8
    sub x1, x1, #1
    b 1b
2:
    str x20, [x22, #-8]!
    mov x20, #-1
    NEXT

// ." ( -- ) IMMEDIATE
XDOTQ:
    // Reuse S" logic by calling the same parse, then TYPE or compile TYPE
    // Implement by branching into shared structure via stack trick:
    // For simplicity, duplicate parse (same as S") then diverge.
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x9, [x0]
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    mov x10, x0
    ldr x11, [x10]
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x12, [x0]
    add x1, x9, x11
    add x6, x9, x12
_dq_skip:
    cmp x1, x6
    b.hs _dq_body0
    ldrb w2, [x1]
    cmp w2, #32
    b.eq _dq_sk1
    cmp w2, #9
    b.ne _dq_body0
_dq_sk1:
    add x1, x1, #1
    b _dq_skip
_dq_body0:
    mov x2, x1
_dq_scan:
    cmp x1, x6
    b.hs _dq_eos
    ldrb w3, [x1]
    cbz w3, _dq_eos
    cmp w3, #34
    b.eq _dq_found
    add x1, x1, #1
    b _dq_scan
_dq_found:
    sub x5, x1, x2
    add x1, x1, #1
    b _dq_commit
_dq_eos:
    sub x5, x1, x2
_dq_commit:
    sub x11, x1, x9
    str x11, [x10]
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    str x1, [x0]
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    ldr x0, [x0]
    cbnz x0, _dq_comp
    // interpret: write string to stdout
    mov x1, x2
    mov x2, x5
    cbz x2, _dq_out
    mov x0, #1
    mov x16, #4
    svc #0x80
_dq_out:
    NEXT
_dq_comp:
    str x19, [x23, #-8]!
    str x2, [x23, #-8]!
    str x5, [x23, #-8]!
    adrp x0, cfa_slit@page
    add x0, x0, cfa_slit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [x23]
    bl _compile_cell
    ldr x5, [x23], #8
    ldr x2, [x23], #8
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    ldr x1, [x0]
    mov x3, #0
_dq_cpy:
    cmp x3, x5
    b.ge _dq_al
    ldrb w4, [x2, x3]
    strb w4, [x1, x3]
    add x3, x3, #1
    b _dq_cpy
_dq_al:
    add x1, x1, x5
    add x1, x1, #7
    bic x1, x1, #7
    adrp x0, here_ptr@page
    add x0, x0, here_ptr@pageoff
    str x1, [x0]
    adrp x0, cfa_type@page
    add x0, x0, cfa_type@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x19, [x23], #8
    NEXT

// _skip_blanks: advance >IN over spaces/tabs (not newlines)
_skip_blanks:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _cursor_load
    mov x1, x0
    bl _source_end
    mov x9, x0
_sb_loop:
    cmp x1, x9
    b.hs _sb_done
    ldrb w2, [x1]
    cmp w2, #32
    b.eq _sb_adv
    cmp w2, #9
    b.eq _sb_adv
    b _sb_done
_sb_adv:
    add x1, x1, #1
    b _sb_loop
_sb_done:
    mov x0, x1
    bl _cursor_store
    ldp x29, x30, [sp], #16
    ret

// _parse_quote: w7=delim -> x2=c-addr, x5=u, advances >IN
_parse_quote:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    bl _cursor_load
    mov x21, x0                     // start (callee-saved)
    mov x3, x0
    bl _source_end
    mov x6, x0
_pq_scan:
    cmp x3, x6
    b.hs _pq_eos
    ldrb w4, [x3]
    cbz w4, _pq_eos
    cmp w4, w7
    b.eq _pq_found
    add x3, x3, #1
    b _pq_scan
_pq_found:
    sub x22, x3, x21                // u
    add x3, x3, #1
    mov x0, x3
    bl _cursor_store
    b _pq_out
_pq_eos:
    sub x22, x3, x21
    mov x0, x3
    bl _cursor_store
_pq_out:
    mov x2, x21                     // c-addr
    mov x5, x22                     // u
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _compile_slit: x2=c-addr, x5=u — compile (S") + len + bytes + align
_compile_slit:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x2                     // src
    mov x20, x5                     // len
    adrp x0, cfa_slit@page
    add x0, x0, cfa_slit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    mov x0, x20
    bl _compile_cell
    // copy bytes to HERE
    adrp x1, here_ptr@page
    add x1, x1, here_ptr@pageoff
    ldr x21, [x1]                   // dest
    mov x2, #0
_cs_copy:
    cmp x2, x20
    b.ge _cs_pad
    ldrb w3, [x19, x2]
    strb w3, [x21, x2]
    add x2, x2, #1
    b _cs_copy
_cs_pad:
    add x21, x21, x20
    // align HERE to 8
    add x21, x21, #7
    bic x21, x21, #7
    adrp x1, here_ptr@page
    add x1, x1, here_ptr@pageoff
    str x21, [x1]
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// ============================================================================
// QUIT - Outer Interpreter
// ============================================================================
.align 4
_do_quit:
    // Empty return stack; clear CATCH nesting
    adrp x23, return_stack@page
    add  x23, x23, return_stack@pageoff
    add  x23, x23, #2048
    adrp x0, throw_handler@page
    add  x0, x0, throw_handler@pageoff
    str  xzr, [x0]
    // Interpret state
    adrp x0, state_var@page
    add  x0, x0, state_var@pageoff
    str  xzr, [x0]
    // Pop any nested SOURCE (EVALUATE / INCLUDE) back to base
    adrp x0, source_sp@page
    add  x0, x0, source_sp@pageoff
    str  xzr, [x0]
    // Terminal is the input source
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    str  xzr, [x0]
    // Drop all locals frames
    adrp x0, local_frame_depth@page
    add  x0, x0, local_frame_depth@pageoff
    str  xzr, [x0]

    // Embed host: return to C (no TTY prompt / infinite loop)
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    ldr  x0, [x0]
    cbnz x0, _embed_quit_return

_quit_loop:
    // Once after bootstrap: REDEF-WARNING ON, and clear data stack (init
    // may leave residual cells). Do not clear on later prompts — stack persists.
    adrp x0, redef_boot_done@page
    add x0, x0, redef_boot_done@pageoff
    ldr x1, [x0]
    cbnz x1, 1f
    mov x1, #1
    str x1, [x0]
    adrp x0, redef_warn@page
    add x0, x0, redef_warn@pageoff
    mov x1, #-1
    str x1, [x0]
    adrp x22, data_stack@page
    add x22, x22, data_stack@pageoff
    add x22, x22, #4096
    mov x20, #0
1:
    // Refresh fault recovery point (siglongjmp lands here after SIGSEGV/SIGBUS)
    adrp x0, quit_jmpbuf@page
    add x0, x0, quit_jmpbuf@pageoff
    mov x1, #1                     // save signal mask
    bl _sigsetjmp
    cbz x0, 2f
    // Returned from fault handler: rebuild a clean outer-interpreter state
    adrp x22, data_stack@page
    add x22, x22, data_stack@pageoff
    add x22, x22, #4096
    mov x20, #0
    adrp x23, return_stack@page
    add x23, x23, return_stack@pageoff
    add x23, x23, #2048
    adrp x0, throw_handler@page
    add x0, x0, throw_handler@pageoff
    str xzr, [x0]
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    str xzr, [x0]
    adrp x0, source_sp@page
    add x0, x0, source_sp@pageoff
    str xzr, [x0]
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    str xzr, [x0]
    adrp x0, local_frame_depth@page
    add x0, x0, local_frame_depth@pageoff
    str xzr, [x0]
    adrp x24, latest_var@page
    add x24, x24, latest_var@pageoff
    bl  _emit_memfault_msg
2:
    // Print prompt via raw SVC
    mov x0, #1
    adrp x1, str_prompt@page
    add x1, x1, str_prompt@pageoff
    mov x2, #5
    mov x16, #4
    svc #0x80

    // Read line (line editor; maxlen leaves room for NUL)
    adrp x0, input_buffer@page
    add  x0, x0, input_buffer@pageoff
    mov  x1, #1023
    bl   _read_line
    cbz  x0, _quit_exit

    // SOURCE = input_buffer, length = strlen, >IN = 0
    adrp x0, input_buffer@page
    add  x0, x0, input_buffer@pageoff
    mov x1, #0
1:
    ldrb w2, [x0, x1]
    cbz w2, 2f
    add x1, x1, #1
    b 1b
2:
    bl _set_source
    // User input device
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    str xzr, [x0]

_interpret_loop:
    // Embed: keep LATEST base register valid (x24 = &latest_var)
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff
    // Between words: catch underflow/overflow from the previous word
    bl _check_stack

    // When FILE-ECHO is on and SOURCE is an INCLUDE buffer, echo source
    // lines up through the current parse position before the next word.
    bl _file_echo_upto_cursor

    bl _next_word
    cbz x1, _interpret_empty

    // Save word addr and len on return stack (caller-saved x2/x3 will be clobbered)
    str x0, [x23, #-8]!    // push word addr
    str x1, [x23, #-8]!    // push word len

    // Try number (x0=1 single in x1; x0=2 double lo=x1 hi=x2; x0=0 fail)
    bl _parse_number
    cbz x0, _try_find

    // Pop saved word addr/len from return stack
    add x23, x23, #16

    cmp x0, #2
    b.eq _number_double

    // --- single-cell number in x1 ---
    adrp x2, state_var@page
    add x2, x2, state_var@pageoff
    ldr x2, [x2]
    cbnz x2, _compile_lit

    DPUSH
    mov x20, x1
    b _interpret_loop

_compile_lit:
    str x1, [x23, #-8]!
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [x23], #8
    bl _compile_cell
    b _interpret_loop

// Double literal: lo in x1, hi in x2
_number_double:
    adrp x3, state_var@page
    add x3, x3, state_var@pageoff
    ldr x3, [x3]
    cbnz x3, _compile_dlit
    // interpret: push lo under, hi in TOS
    str x20, [x22, #-8]!           // flush prior TOS
    str x1, [x22, #-8]!            // lo
    mov x20, x2                    // hi
    b _interpret_loop

_compile_dlit:
    // compile LIT lo  LIT hi
    stp x1, x2, [sp, #-16]!
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [sp]
    bl _compile_cell
    adrp x0, cfa_lit@page
    add x0, x0, cfa_lit@pageoff
    ldr x0, [x0]
    bl _compile_cell
    ldr x0, [sp, #8]
    bl _compile_cell
    add sp, sp, #16
    b _interpret_loop

_try_find:
    // Restore word addr and len from return stack
    ldr x1, [x23], #8      // pop len
    ldr x0, [x23], #8      // pop addr
    // Compile-time locals: name → LIT idx (LOCAL@)
    adrp x2, state_var@page
    add  x2, x2, state_var@pageoff
    ldr  x2, [x2]
    cbz  x2, 1f
    // Save name for find if not local
    stp  x0, x1, [sp, #-16]!
    bl   _local_lookup             // x0=index or -1
    cmp  x0, #-1
    b.eq 2f
    // Compile LIT index (LOCAL@)
    mov  x1, x0
    str  x1, [sp, #-16]!
    adrp x0, cfa_lit@page
    add  x0, x0, cfa_lit@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    ldr  x0, [sp], #16
    bl   _compile_cell
    adrp x0, cfa_local_at@page
    add  x0, x0, cfa_local_at@pageoff
    ldr  x0, [x0]
    bl   _compile_cell
    add  sp, sp, #16               // drop saved name
    b    _interpret_loop
2:
    ldp  x0, x1, [sp], #16
1:
    bl _find_word
    cbz x0, _word_not_found

    mov x2, x0                     // CFA
    mov x3, x1                     // FLAGS
    ldr x5, [x2]                   // code ptr at CFA

    // Immediate? FLAG_IMM bit 63
    mov x4, #1
    lsl x4, x4, #63
    tst x3, x4
    b.ne _exec_found

    // Compile mode?
    adrp x6, state_var@page
    add x6, x6, state_var@pageoff
    ldr x6, [x6]
    cbnz x6, _compile_entry

_exec_found:
    // Trampoline: IP -> restart_cell -> restart_cfa (code = XRESTART)
    adrp x19, restart_cell@page
    add  x19, x19, restart_cell@pageoff
    mov x21, x2
    adrp x1, next_diag@page
    add  x1, x1, next_diag@pageoff
    str  x5, [x1]
    str  x19, [x1, #8]
    str  x22, [x1, #16]
    str  x20, [x1, #24]
    br x5

_compile_entry:
    mov x0, x2
    bl _compile_cell
    b _interpret_loop

_word_not_found:
    bl   _report_undefined
    b    _error_abandon

// _report_undefined: print "undefined: <word_scratch>\n" via host emit_hook
// (raw svc write never appears in the SwiftUI console). word_scratch must be
// the failed name, NUL-terminated (_next_word always does this).
_report_undefined:
    stp  x29, x30, [sp, #-16]!
    adrp x0, str_undefined@page
    add  x0, x0, str_undefined@pageoff
    mov  x1, #11                   // "undefined: "
    bl   _write_stdout
    adrp x0, word_scratch@page
    add  x0, x0, word_scratch@pageoff
    bl   _print_string_svc
    mov  x0, #10
    bl   _putchar
    ldp  x29, x30, [sp], #16
    ret

// Data-stack check between outer-interpreter words (not inside primitives).
// Stack grows down; empty DSP = data_stack+4096. Underflow if DSP > SP0.
// Also reject DSP below data_stack (overflow into other BSS).
_check_stack:
    adrp x0, data_stack@page
    add x0, x0, data_stack@pageoff
    add x1, x0, #4096              // SP0
    cmp x22, x1
    b.hi _stack_underflow          // DSP above empty → underflowed
    cmp x22, x0
    b.lo _stack_overflow           // DSP below buffer → overflow
    ret

_stack_underflow:
    adrp x0, str_underflow@page
    add  x0, x0, str_underflow@pageoff
    mov  x1, #16                   // "stack underflow\n"
    bl   _write_stdout
    b _stack_reset_abandon

_stack_overflow:
    adrp x0, str_overflow@page
    add  x0, x0, str_overflow@pageoff
    mov  x1, #15                   // "stack overflow\n"
    bl   _write_stdout
_stack_reset_abandon:
    adrp x22, data_stack@page
    add x22, x22, data_stack@pageoff
    add x22, x22, #4096
    mov x20, #0
    b _error_abandon

// Shared: leave interpret, abandon rest of SOURCE, finish line
_error_abandon:
    adrp x0, state_var@page
    add x0, x0, state_var@pageoff
    str xzr, [x0]
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    ldr x0, [x0]
    adrp x1, to_in_var@page
    add x1, x1, to_in_var@pageoff
    str x0, [x1]
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x0, [x0]
    adrp x1, source_len@page
    add x1, x1, source_len@pageoff
    ldr x1, [x1]
    add x0, x0, x1
    adrp x1, word_cursor@page
    add x1, x1, word_cursor@pageoff
    str x0, [x1]
    b _interpret_empty

// End of current SOURCE: pop nested source (INCLUDE/EVALUATE) or finish line
_interpret_empty:
    // If ending a file INCLUDE/FLOAD (SOURCE-ID > 0), restore host load cwd
    // so nested relative FLOAD paths resolve against the outer file's folder.
    adrp x0, source_id_var@page
    add  x0, x0, source_id_var@pageoff
    ldr  x0, [x0]
    cmp  x0, #0
    b.le 1f
    adrp x0, end_include_hook@page
    add  x0, x0, end_include_hook@pageoff
    ldr  x9, [x0]
    cbz  x9, 1f
    blr  x9
1:
    bl _pop_source
    cbnz x0, _interpret_loop       // restored outer SOURCE — keep going
_interpret_done:
    // First completion is bootstrap (forth_init_str); fence user WORDS after that.
    bl   _record_words_user_base_once
    // Print " ok\n" (host emit hook when set)
    adrp x0, str_ok@page
    add  x0, x0, str_ok@pageoff
    mov  x1, #4
    bl   _write_stdout
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    ldr  x0, [x0]
    cbnz x0, _embed_finish
    b _quit_loop

_quit_exit:
    // Print "Bye!\n"
    adrp x0, str_bye@page
    add  x0, x0, str_bye@pageoff
    mov  x1, #5
    bl   _write_stdout
    adrp x0, embed_mode@page
    add  x0, x0, embed_mode@pageoff
    ldr  x0, [x0]
    cbnz x0, _embed_bye_return
    mov x0, #0
    mov x16, #1
    svc #0x80

// ============================================================================
// C Helper Functions (assembly)
// ============================================================================

// _set_source: x0=c-addr, x1=u  — establish SOURCE / >IN=0
_set_source:
    adrp x2, source_addr@page
    add x2, x2, source_addr@pageoff
    str x0, [x2]
    adrp x2, source_len@page
    add x2, x2, source_len@pageoff
    str x1, [x2]
    adrp x2, to_in_var@page
    add x2, x2, to_in_var@pageoff
    str xzr, [x2]
    adrp x2, word_cursor@page
    add x2, x2, word_cursor@pageoff
    str x0, [x2]
    // Reset FILE-ECHO scan so the new SOURCE echoes from its start
    adrp x2, file_echo_pos@page
    add x2, x2, file_echo_pos@pageoff
    str x0, [x2]
    ret

// _file_echo_upto_cursor: if FILE-ECHO nonzero and SOURCE-ID > 0 (INCLUDE),
// write any not-yet-echoed source text through the end of the line that
// contains the next non-whitespace character (lookahead from word_cursor).
// That way blank lines skipped by the parser are still echoed.
// Tracks progress in file_echo_pos (absolute address).
// Safe to call with any VM regs live; uses only x0-x4/x16 (+ frame).
_file_echo_upto_cursor:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // FILE-ECHO off?
    adrp x0, file_echo@page
    add x0, x0, file_echo@pageoff
    ldr x0, [x0]
    cbz x0, _fe_done
    // Only for INCLUDE / file-ish buffers (SOURCE-ID > 0)
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    ldr x0, [x0]
    cmp x0, #0
    b.le _fe_done
    // source base / end
    adrp x1, source_addr@page
    add x1, x1, source_addr@pageoff
    ldr x1, [x1]                   // x1 = source base
    adrp x2, source_len@page
    add x2, x2, source_len@pageoff
    ldr x2, [x2]
    add x2, x1, x2                 // x2 = source end
    // cursor = word_cursor, clamped
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    ldr x0, [x0]
    cmp x0, x1
    csel x0, x1, x0, lo
    cmp x0, x2
    csel x0, x2, x0, hi
    // Lookahead: skip whitespace to next token (or end)
1:
    cmp x0, x2
    b.hs 2f
    ldrb w3, [x0]
    cbz w3, 2f
    cmp w3, #32
    b.eq 3f
    cmp w3, #10
    b.eq 3f
    cmp w3, #9
    b.eq 3f
    b 2f                           // non-ws: target found
3:
    add x0, x0, #1
    b 1b
2:
    // x0 = target (next token or end). Find end of that line.
    mov x3, x0                     // x3 = line_end scan
4:
    cmp x3, x2
    b.hs 5f
    ldrb w4, [x3]
    cbz w4, 5f
    cmp w4, #10
    b.eq 5f
    add x3, x3, #1
    b 4b
5:
    // x1 = pos (file_echo_pos), clamp into SOURCE
    adrp x4, file_echo_pos@page
    add x4, x4, file_echo_pos@pageoff
    ldr x0, [x4]                   // x0 = pos (reuse x0; target no longer needed)
    adrp x1, source_addr@page
    add x1, x1, source_addr@pageoff
    ldr x1, [x1]
    cmp x0, x1
    csel x0, x1, x0, lo
    cmp x0, x2
    csel x0, x2, x0, hi
    // if pos >= line_end, already echoed through this line
    cmp x0, x3
    b.hs _fe_done
    // write [pos, line_end) via emit_hook (not raw write(1) — embed UI never
    // sees SVC stdout, which produced a screen full of blank newlines only).
    // x0=pos, x3=line_end; _write_stdout clobbers caller-saved regs.
    mov x1, x3
    subs x1, x1, x0                // len = line_end - pos; x0 = buf
    b.eq 6f
    str x3, [sp, #-16]!            // keep line_end
    bl  _write_stdout              // x0=buf, x1=len → host emit_hook
    ldr x3, [sp], #16
6:
    // Advance file_echo_pos *before* bl _putchar: the Swift emit_hook clobbers
    // all caller-saved regs (x0–x18), so storing x3 after bl left garbage and
    // the next word re-echoed the whole file from SOURCE start (massive dup).
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x0, [x0]
    adrp x1, source_len@page
    add x1, x1, source_len@pageoff
    ldr x1, [x1]
    add x0, x0, x1                 // source end
    cmp x3, x0
    b.hs 7f
    ldrb w1, [x3]
    cmp w1, #10
    b.ne 7f
    add x1, x3, #1                 // next pos = past \n
    adrp x4, file_echo_pos@page
    add x4, x4, file_echo_pos@pageoff
    str x1, [x4]
    mov x0, #10
    bl _putchar
    b _fe_done
7:
    // No trailing newline in source (last line): print one for the console
    adrp x4, file_echo_pos@page
    add x4, x4, file_echo_pos@pageoff
    str x3, [x4]                   // next pos = line_end (EOF)
    mov x0, #10
    bl _putchar
_fe_done:
    ldp x29, x30, [sp], #16
    ret

// _push_source: save current SOURCE/>IN/SOURCE-ID/file_echo_pos on source_stack.
// Frame = 5 quads (addr, len, >IN, source-id, file_echo_pos). Clobbers x0-x3.
// Returns x0=1 ok, x0=0 overflow.
_push_source:
    adrp x0, source_sp@page
    add x0, x0, source_sp@pageoff
    ldr x1, [x0]
    cmp x1, #8
    b.hs 1f
    mov x2, #40                    // 5*8 per frame
    mul x3, x1, x2
    adrp x2, source_stack@page
    add x2, x2, source_stack@pageoff
    add x2, x2, x3
    // store addr, len, to_in, source_id, file_echo_pos
    adrp x3, source_addr@page
    add x3, x3, source_addr@pageoff
    ldr x3, [x3]
    str x3, [x2], #8
    adrp x3, source_len@page
    add x3, x3, source_len@pageoff
    ldr x3, [x3]
    str x3, [x2], #8
    adrp x3, to_in_var@page
    add x3, x3, to_in_var@pageoff
    ldr x3, [x3]
    str x3, [x2], #8
    adrp x3, source_id_var@page
    add x3, x3, source_id_var@pageoff
    ldr x3, [x3]
    str x3, [x2], #8
    adrp x3, file_echo_pos@page
    add x3, x3, file_echo_pos@pageoff
    ldr x3, [x3]
    str x3, [x2]
    add x1, x1, #1
    str x1, [x0]
    mov x0, #1
    ret
1:
    mov x0, #0
    ret

// _pop_source: restore SOURCE/>IN/SOURCE-ID/file_echo_pos. x0=1 ok, x0=0 underflow.
_pop_source:
    adrp x0, source_sp@page
    add x0, x0, source_sp@pageoff
    ldr x1, [x0]
    cbz x1, 1f
    sub x1, x1, #1
    str x1, [x0]
    mov x2, #40
    mul x3, x1, x2
    adrp x2, source_stack@page
    add x2, x2, source_stack@pageoff
    add x2, x2, x3
    ldr x3, [x2], #8
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    str x3, [x0]
    mov x4, x3                     // base for cursor
    ldr x3, [x2], #8
    adrp x0, source_len@page
    add x0, x0, source_len@pageoff
    str x3, [x0]
    ldr x3, [x2], #8
    adrp x0, to_in_var@page
    add x0, x0, to_in_var@pageoff
    str x3, [x0]
    add x4, x4, x3
    adrp x0, word_cursor@page
    add x0, x0, word_cursor@pageoff
    str x4, [x0]
    ldr x3, [x2], #8
    adrp x0, source_id_var@page
    add x0, x0, source_id_var@pageoff
    str x3, [x0]
    ldr x3, [x2]
    adrp x0, file_echo_pos@page
    add x0, x0, file_echo_pos@pageoff
    str x3, [x0]
    mov x0, #1
    ret
1:
    mov x0, #0
    ret

// _cursor_load: -> x0 = absolute parse pointer (SOURCE + >IN)
_cursor_load:
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x0, [x0]
    adrp x1, to_in_var@page
    add x1, x1, to_in_var@pageoff
    ldr x1, [x1]
    add x0, x0, x1
    ret

// _cursor_store: x0 = absolute parse pointer; updates >IN and word_cursor
_cursor_store:
    adrp x1, source_addr@page
    add x1, x1, source_addr@pageoff
    ldr x1, [x1]
    sub x2, x0, x1                 // offset
    cmp x2, #0
    b.ge 1f
    mov x2, #0
1:
    adrp x3, source_len@page
    add x3, x3, source_len@pageoff
    ldr x3, [x3]
    cmp x2, x3
    b.ls 2f
    mov x2, x3
2:
    adrp x1, to_in_var@page
    add x1, x1, to_in_var@pageoff
    str x2, [x1]
    adrp x1, source_addr@page
    add x1, x1, source_addr@pageoff
    ldr x1, [x1]
    add x1, x1, x2
    adrp x3, word_cursor@page
    add x3, x3, word_cursor@pageoff
    str x1, [x3]
    ret

// _source_end: -> x0 = SOURCE+u (one past last char)
_source_end:
    adrp x0, source_addr@page
    add x0, x0, source_addr@pageoff
    ldr x0, [x0]
    adrp x1, source_len@page
    add x1, x1, source_len@pageoff
    ldr x1, [x1]
    add x0, x0, x1
    ret

// _putchar: x0 = char
// Host emit_hook when set; else write(1). Does not touch x19-x28 (VM-safe).
.globl _putchar
_putchar:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    // emit_hook?
    adrp x1, emit_hook@page
    add  x1, x1, emit_hook@pageoff
    ldr  x1, [x1]
    cbz  x1, _putchar_svc
    // w0 already has char; AAPCS: int in w0
    blr  x1
    ldp x29, x30, [sp], #16
    ret
_putchar_svc:
    sub sp, sp, #16
    strb w0, [sp]
    mov x0, #1              // fd = stdout
    mov x1, sp              // buf
    mov x2, #1              // len
    mov x16, #4             // write
    svc #0x80               // Darwin: preserves x19-x28; result in x0
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

// _emit_memfault_msg: print "memory access error\n" via emit_hook (safe after longjmp)
_emit_memfault_msg:
    stp x29, x30, [sp, #-16]!
    adrp x0, str_memfault@page
    add  x0, x0, str_memfault@pageoff
    mov  x1, #20
    bl   _write_stdout
    // clear sticky so host does not double-print if it also checks the flag
    adrp x0, fault_pending@page
    add  x0, x0, fault_pending@pageoff
    str  xzr, [x0]
    ldp x29, x30, [sp], #16
    ret

// _write_stdout: x0 = buf, x1 = len  (routes through emit_hook when set)
_write_stdout:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov x19, x0                    // buf
    mov x20, x1                    // len
    adrp x0, emit_hook@page
    add  x0, x0, emit_hook@pageoff
    ldr  x0, [x0]
    cbnz x0, _ws_hook
    cbz  x20, _ws_done
    mov  x0, #1
    mov  x1, x19
    mov  x2, x20
    mov  x16, #4
    svc  #0x80
    b    _ws_done
_ws_hook:
    cbz  x20, _ws_done
1:
    ldrb w0, [x19], #1
    bl   _putchar
    sub  x20, x20, #1
    cbnz x20, 1b
_ws_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// _rl_echo: like _putchar but only when line-editor owns the TTY (raw mode).
// Avoids double-echo when still in cooked mode or when stdin is a pipe.
_rl_echo:
    stp x29, x30, [sp, #-16]!
    adrp x1, tty_raw_active@page
    add x1, x1, tty_raw_active@pageoff
    ldr x1, [x1]
    cbz x1, 1f
    bl _putchar
1:
    ldp x29, x30, [sp], #16
    ret

// _getchar: returns char or -1 on EOF
// Host key_hook when set; else read(0). Does not touch x19-x28 (VM-safe).
.globl _getchar
_getchar:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x1, key_hook@page
    add  x1, x1, key_hook@pageoff
    ldr  x1, [x1]
    cbz  x1, _getchar_svc
    blr  x1                        // int (*)(void) → w0
    // sign-extend byte-ish; keep full int (hook may return -1)
    ldp x29, x30, [sp], #16
    ret
_getchar_svc:
    sub sp, sp, #16
    mov x0, #0              // fd = stdin
    mov x1, sp
    mov x2, #1
    mov x16, #3             // read
    svc #0x80
    cbz x0, _gc_eof
    ldrb w0, [sp]
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret
_gc_eof:
    mov w0, #-1
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

// _print_string_svc: x0 = null-terminated string (via _write_stdout / emit)
_print_string_svc:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x1, x0
    mov x2, #0
_pss_len:
    ldrb w3, [x1, x2]
    cbz w3, _pss_print
    add x2, x2, #1
    b _pss_len
_pss_print:
    mov x0, x1
    mov x1, x2
    bl  _write_stdout
    ldp x29, x30, [sp], #16
    ret

// ============================================================================
// Line editor (_read_line)
// Raw-ish TTY (no ICANON/ECHO) + local echo, so left/right/backspace work
// when pasting or editing a long definition before Enter.
// Up/Down arrows walk a ring of recent lines (history).
// x0=buf, x1=maxlen (incl. room for NUL) -> x0=buf or 0 on EOF
// Preserves VM regs x19-x24 (and more).
// ============================================================================

// History: 32 lines x 512 bytes (NUL-terminated). Ring buffer.
.equ HIST_MAX, 32
.equ HIST_LINE, 512

// _tty_raw_enter / _tty_raw_leave: libc tcgetattr/tcsetattr
// termios layout (Darwin arm64): c_lflag @24, c_cc @32, VMIN=16, VTIME=17
// ICANON=0x100, ECHO=0x8, ECHOE=0x2
_tty_raw_enter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x1, tty_termios_save@page
    add x1, x1, tty_termios_save@pageoff
    mov x0, #0                      // stdin
    bl _tcgetattr
    cbnz x0, _tty_re_fail
    // copy save -> raw (72 bytes)
    adrp x0, tty_termios_save@page
    add x0, x0, tty_termios_save@pageoff
    adrp x1, tty_termios_raw@page
    add x1, x1, tty_termios_raw@pageoff
    mov x2, #72
1:
    cbz x2, 2f
    ldrb w3, [x0], #1
    strb w3, [x1], #1
    sub x2, x2, #1
    b 1b
2:
    adrp x1, tty_termios_raw@page
    add x1, x1, tty_termios_raw@pageoff
    ldr x0, [x1, #24]               // c_lflag
    mov x2, #0x108                  // ICANON|ECHO
    bic x0, x0, x2
    mov x2, #0x2                    // ECHOE
    bic x0, x0, x2
    str x0, [x1, #24]
    mov w0, #1
    strb w0, [x1, #32+16]           // c_cc[VMIN]=1
    strb wzr, [x1, #32+17]          // c_cc[VTIME]=0
    mov x0, #0
    mov x2, x1
    mov x1, #0                      // TCSANOW
    bl _tcsetattr
    cbnz x0, _tty_re_fail
    adrp x0, tty_raw_active@page
    add x0, x0, tty_raw_active@pageoff
    mov x1, #1
    str x1, [x0]
    ldp x29, x30, [sp], #16
    ret
_tty_re_fail:
    adrp x0, tty_raw_active@page
    add x0, x0, tty_raw_active@pageoff
    str xzr, [x0]
    ldp x29, x30, [sp], #16
    ret

_tty_raw_leave:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, tty_raw_active@page
    add x0, x0, tty_raw_active@pageoff
    ldr x1, [x0]
    cbz x1, 1f
    str xzr, [x0]
    mov x0, #0
    mov x1, #0                      // TCSANOW
    adrp x2, tty_termios_save@page
    add x2, x2, tty_termios_save@pageoff
    bl _tcsetattr
1:
    ldp x29, x30, [sp], #16
    ret

// _rl_emit_bs: emit n backspaces (x0=n)
_rl_emit_bs:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x19, x0
1:
    cbz x19, 2f
    mov x0, #8
    bl _rl_echo
    sub x19, x19, #1
    b 1b
2:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _rl_redraw_tail: from cursor pos to end, then pad space, then back up.
// x19=buf x21=len x22=pos  (does not clobber those permanently beyond needs)
// After delete/insert-at-middle: show buf[pos..len), space, BS*(len-pos+1)
_rl_redraw_tail:
    stp x29, x30, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x23, x22                    // i = pos
1:
    cmp x23, x21
    b.ge 2f
    ldrb w0, [x19, x23]
    bl _rl_echo
    add x23, x23, #1
    b 1b
2:
    mov x0, #32                     // trailing space clears leftover char
    bl _rl_echo
    // backspaces: (len - pos + 1)
    sub x0, x21, x22
    add x0, x0, #1
    bl _rl_emit_bs
    ldp x23, x24, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _rl_clear_display: erase current line on screen (cursor -> col0, wipe)
// uses x19/x21/x22
_rl_clear_display:
    stp x29, x30, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x0, x22
    bl _rl_emit_bs                  // cursor to start
    mov x23, x21
1:
    cbz x23, 2f
    mov x0, #32
    bl _rl_echo
    sub x23, x23, #1
    b 1b
2:
    mov x0, x21
    bl _rl_emit_bs
    ldp x23, x24, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _rl_load_str: replace edit buffer with C-string at x0 (NUL-term), redraw
// respects maxlen in x20; updates x21/x22
_rl_load_str:
    stp x29, x30, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x25, x0                     // src
    bl _rl_clear_display
    mov x21, #0
    mov x23, #0
1:
    ldrb w0, [x25, x23]
    cbz w0, 2f
    cmp x23, x20
    b.ge 2f
    strb w0, [x19, x23]
    add x23, x23, #1
    b 1b
2:
    mov x21, x23
    mov x22, x23
    strb wzr, [x19, x21]
    // echo new line
    mov x23, #0
3:
    cmp x23, x21
    b.ge 4f
    ldrb w0, [x19, x23]
    bl _rl_echo
    add x23, x23, #1
    b 3b
4:
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _hist_push: save current line (x19, x21=len) into history ring
_hist_push:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    cbz x21, _hp_done               // skip empty
    // cap copy length
    mov x22, x21
    cmp x22, #HIST_LINE-1
    b.ls 1f
    mov x22, #HIST_LINE-1
1:
    // skip if identical to most recent entry
    adrp x0, hist_count@page
    add x0, x0, hist_count@pageoff
    ldr x1, [x0]
    cbz x1, _hp_store
    adrp x0, hist_head@page
    add x0, x0, hist_head@pageoff
    ldr x2, [x0]                    // head = next write
    // newest slot = (head - 1) mod HIST_MAX
    subs x2, x2, #1
    b.ge 2f
    mov x2, #HIST_MAX-1
2:
    // compare
    mov x3, #HIST_LINE
    mul x3, x2, x3
    adrp x4, hist_data@page
    add x4, x4, hist_data@pageoff
    add x4, x4, x3                  // &hist[newest]
    mov x5, #0
3:
    cmp x5, x22
    b.ge 4f
    ldrb w6, [x19, x5]
    ldrb w7, [x4, x5]
    cmp w6, w7
    b.ne _hp_store
    add x5, x5, #1
    b 3b
4:
    ldrb w7, [x4, x5]               // must be NUL at end for equal
    cbnz w7, _hp_store
    // equal — skip push
    b _hp_done
_hp_store:
    adrp x0, hist_head@page
    add x0, x0, hist_head@pageoff
    ldr x2, [x0]
    mov x3, #HIST_LINE
    mul x3, x2, x3
    adrp x4, hist_data@page
    add x4, x4, hist_data@pageoff
    add x4, x4, x3
    mov x5, #0
5:
    cmp x5, x22
    b.ge 6f
    ldrb w6, [x19, x5]
    strb w6, [x4, x5]
    add x5, x5, #1
    b 5b
6:
    strb wzr, [x4, x5]
    // head = (head+1) % HIST_MAX
    add x2, x2, #1
    cmp x2, #HIST_MAX
    b.lo 7f
    mov x2, #0
7:
    str x2, [x0]
    adrp x0, hist_count@page
    add x0, x0, hist_count@pageoff
    ldr x1, [x0]
    cmp x1, #HIST_MAX
    b.hs _hp_done
    add x1, x1, #1
    str x1, [x0]
_hp_done:
    adrp x0, hist_nav@page
    add x0, x0, hist_nav@pageoff
    mov x1, #-1
    str x1, [x0]
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _rl_hist_up: older line (ESC [ A)
_rl_hist_up:
    stp x29, x30, [sp, #-16]!
    adrp x0, hist_count@page
    add x0, x0, hist_count@pageoff
    ldr x1, [x0]
    cbz x1, _hu_done
    adrp x0, hist_nav@page
    add x0, x0, hist_nav@pageoff
    ldr x2, [x0]                    // current nav (-1 = draft)
    // first up: save draft
    cmp x2, #-1
    b.ne 1f
    // copy buf -> hist_draft
    adrp x3, hist_draft@page
    add x3, x3, hist_draft@pageoff
    mov x4, #0
2:
    cmp x4, x21
    b.ge 3f
    cmp x4, #HIST_LINE-1
    b.ge 3f
    ldrb w5, [x19, x4]
    strb w5, [x3, x4]
    add x4, x4, #1
    b 2b
3:
    strb wzr, [x3, x4]
    adrp x3, hist_draft_len@page
    add x3, x3, hist_draft_len@pageoff
    str x21, [x3]
    mov x2, #0                      // nav = newest
    b 4f
1:
    // older
    add x3, x2, #1
    cmp x3, x1
    b.hs _hu_done                   // already oldest
    mov x2, x3
4:
    str x2, [x0]
    // slot = (hist_head - 1 - nav) mod HIST_MAX
    adrp x3, hist_head@page
    add x3, x3, hist_head@pageoff
    ldr x3, [x3]
    sub x3, x3, #1
    sub x3, x3, x2
5:
    cmp x3, #0
    b.ge 6f
    add x3, x3, #HIST_MAX
    b 5b
6:
    mov x4, #HIST_LINE
    mul x4, x3, x4
    adrp x0, hist_data@page
    add x0, x0, hist_data@pageoff
    add x0, x0, x4
    bl _rl_load_str
_hu_done:
    ldp x29, x30, [sp], #16
    ret

// _rl_hist_down: newer line / draft (ESC [ B)
_rl_hist_down:
    stp x29, x30, [sp, #-16]!
    adrp x0, hist_nav@page
    add x0, x0, hist_nav@pageoff
    ldr x2, [x0]
    cmp x2, #-1
    b.eq _hd_done                   // already on draft
    cbz x2, 1f                      // nav 0 -> restore draft
    // newer
    sub x2, x2, #1
    str x2, [x0]
    adrp x3, hist_head@page
    add x3, x3, hist_head@pageoff
    ldr x3, [x3]
    sub x3, x3, #1
    sub x3, x3, x2
2:
    cmp x3, #0
    b.ge 3f
    add x3, x3, #HIST_MAX
    b 2b
3:
    mov x4, #HIST_LINE
    mul x4, x3, x4
    adrp x1, hist_data@page
    add x1, x1, hist_data@pageoff
    add x0, x1, x4
    bl _rl_load_str
    b _hd_done
1:
    mov x1, #-1
    str x1, [x0]
    adrp x0, hist_draft@page
    add x0, x0, hist_draft@pageoff
    bl _rl_load_str
_hd_done:
    ldp x29, x30, [sp], #16
    ret

// _read_line: x0=buf, x1=maxlen -> x0=buf ptr on success, 0 on EOF
_read_line:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, x0                     // buf
    // leave 1 byte for NUL
    subs x20, x1, #1
    b.gt 1f
    mov x20, #0
1:
    mov x21, #0                     // len
    mov x22, #0                     // pos
    // reset history navigation for this prompt
    adrp x0, hist_nav@page
    add x0, x0, hist_nav@pageoff
    mov x1, #-1
    str x1, [x0]
    bl _tty_raw_enter
_rl_loop:
    bl _getchar
    cmp w0, #-1
    b.le _rl_eof
    and w0, w0, #0xff
    // Enter
    cmp w0, #10
    b.eq _rl_nl
    cmp w0, #13
    b.eq _rl_nl
    // Backspace / DEL
    cmp w0, #8
    b.eq _rl_backspace
    cmp w0, #127
    b.eq _rl_backspace
    // Ctrl-A home
    cmp w0, #1
    b.eq _rl_home
    // Ctrl-E end
    cmp w0, #5
    b.eq _rl_end
    // Ctrl-U kill whole line
    cmp w0, #21
    b.eq _rl_kill_all
    // Ctrl-K kill to end
    cmp w0, #11
    b.eq _rl_kill_eol
    // Ctrl-D: EOF if empty, else delete forward
    cmp w0, #4
    b.eq _rl_ctrl_d
    // ESC sequences (arrows, etc.)
    cmp w0, #27
    b.eq _rl_esc
    // Printable ASCII
    cmp w0, #32
    b.lo _rl_loop
    cmp w0, #126
    b.hi _rl_loop
    // insert w0 at pos
    cmp x21, x20
    b.ge _rl_loop                   // full
    mov w25, w0                     // save char
    // shift right: from len-1 down to pos
    mov x23, x21
_rl_ins_shift:
    cmp x23, x22
    b.le _rl_ins_store
    sub x24, x23, #1
    ldrb w0, [x19, x24]
    strb w0, [x19, x23]
    sub x23, x23, #1
    b _rl_ins_shift
_rl_ins_store:
    strb w25, [x19, x22]
    add x21, x21, #1
    // echo inserted char + tail
    mov w0, w25
    bl _rl_echo
    add x22, x22, #1
    // print rest of line after new cursor, then BS back
    mov x23, x22
_rl_ins_echo:
    cmp x23, x21
    b.ge _rl_ins_back
    ldrb w0, [x19, x23]
    bl _rl_echo
    add x23, x23, #1
    b _rl_ins_echo
_rl_ins_back:
    sub x0, x21, x22
    bl _rl_emit_bs
    b _rl_loop

_rl_backspace:
    cbz x22, _rl_loop
    sub x22, x22, #1
    // shift left from pos
    mov x23, x22
_rl_bs_shift:
    add x24, x23, #1
    cmp x24, x21
    b.ge _rl_bs_done_shift
    ldrb w0, [x19, x24]
    strb w0, [x19, x23]
    add x23, x23, #1
    b _rl_bs_shift
_rl_bs_done_shift:
    sub x21, x21, #1
    mov x0, #8
    bl _rl_echo
    bl _rl_redraw_tail
    b _rl_loop

_rl_home:
    mov x0, x22
    bl _rl_emit_bs
    mov x22, #0
    b _rl_loop

_rl_end:
1:
    cmp x22, x21
    b.ge _rl_loop
    ldrb w0, [x19, x22]
    bl _rl_echo
    add x22, x22, #1
    b 1b

_rl_kill_all:
    mov x0, x22
    bl _rl_emit_bs
    // erase visible: spaces for old len, then BS
    mov x23, x21
1:
    cbz x23, 2f
    mov x0, #32
    bl _rl_echo
    sub x23, x23, #1
    b 1b
2:
    mov x0, x21
    bl _rl_emit_bs
    mov x21, #0
    mov x22, #0
    b _rl_loop

_rl_kill_eol:
    // clear on screen from pos
    sub x23, x21, x22
1:
    cbz x23, 2f
    mov x0, #32
    bl _rl_echo
    sub x23, x23, #1
    b 1b
2:
    sub x0, x21, x22
    bl _rl_emit_bs
    mov x21, x22
    b _rl_loop

_rl_ctrl_d:
    cbz x21, _rl_eof                // empty -> EOF
    // delete forward if not at end
    cmp x22, x21
    b.ge _rl_loop
    mov x23, x22
_rl_del_shift:
    add x24, x23, #1
    cmp x24, x21
    b.ge _rl_del_done
    ldrb w0, [x19, x24]
    strb w0, [x19, x23]
    add x23, x23, #1
    b _rl_del_shift
_rl_del_done:
    sub x21, x21, #1
    bl _rl_redraw_tail
    b _rl_loop

// ESC [ ... final   (CSI).  w26 holds last parameter digit (for ~ keys).
_rl_esc:
    bl _getchar
    cmp w0, #-1
    b.le _rl_eof
    cmp w0, #'['
    b.ne _rl_loop                   // drop lone ESC / Alt- keys
    mov w26, #0                     // last CSI digit
    // collect CSI until final byte 0x40-0x7E
_rl_csi:
    bl _getchar
    cmp w0, #-1
    b.le _rl_eof
    cmp w0, #'0'
    b.lo 1f
    cmp w0, #'9'
    b.hi 1f
    mov w26, w0                     // remember digit
    b _rl_csi
1:
    cmp w0, #0x40
    b.lo _rl_csi                    // other parameter/intermediate
    // final
    cmp w0, #'A'                    // up — history older
    b.eq _rl_up
    cmp w0, #'B'                    // down — history newer
    b.eq _rl_down
    cmp w0, #'C'                    // right
    b.eq _rl_right
    cmp w0, #'D'                    // left
    b.eq _rl_left
    cmp w0, #'H'                    // home
    b.eq _rl_home
    cmp w0, #'F'                    // end
    b.eq _rl_end
    cmp w0, #'~'
    b.ne _rl_loop
    // ESC [ n ~  : 1/7=home 3=delete 4/8=end
    cmp w26, #'3'
    b.eq _rl_ctrl_d
    cmp w26, #'1'
    b.eq _rl_home
    cmp w26, #'7'
    b.eq _rl_home
    cmp w26, #'4'
    b.eq _rl_end
    cmp w26, #'8'
    b.eq _rl_end
    b _rl_loop

_rl_up:
    bl _rl_hist_up
    b _rl_loop

_rl_down:
    bl _rl_hist_down
    b _rl_loop

_rl_left:
    cbz x22, _rl_loop
    sub x22, x22, #1
    mov x0, #8
    bl _rl_echo
    b _rl_loop

_rl_right:
    cmp x22, x21
    b.ge _rl_loop
    ldrb w0, [x19, x22]
    bl _rl_echo
    add x22, x22, #1
    b _rl_loop

_rl_nl:
    // move visually to end then newline
1:
    cmp x22, x21
    b.ge 2f
    ldrb w0, [x19, x22]
    bl _rl_echo
    add x22, x22, #1
    b 1b
2:
    mov x0, #10
    bl _rl_echo
    strb wzr, [x19, x21]
    bl _hist_push                   // remember non-empty lines
    // _tty_raw_leave clobbers x0 (tcsetattr status); keep buffer ptr in x25
    mov x25, x19
    bl _tty_raw_leave
    mov x0, x25                     // success: return buf (non-zero)
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_rl_eof:
    // Preserve len across leave; x0 must be buf or 0 after restore
    mov x25, x21
    bl _tty_raw_leave
    cbz x25, _rl_null
    strb wzr, [x19, x25]
    mov x0, x19
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
_rl_null:
    mov x0, #0
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _next_word: parse next word -> x0=addr of word_scratch, x1=length (0=done)
// Stops at SOURCE end (not only NUL) so EVALUATE substrings work.
_next_word:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    bl _cursor_load
    mov x19, x0
    bl _source_end
    mov x21, x0                    // end of SOURCE

_nw_skip:
    cmp x19, x21
    b.hs _nw_eof
    ldrb w0, [x19]
    cbz w0, _nw_eof
    cmp w0, #32
    b.eq _nw_adv
    cmp w0, #10
    b.eq _nw_adv
    cmp w0, #9
    b.eq _nw_adv
    b _nw_start
_nw_adv:
    add x19, x19, #1
    b _nw_skip

_nw_start:
    mov x20, x19
_nw_scan:
    cmp x19, x21
    b.hs _nw_got
    ldrb w0, [x19]
    cbz w0, _nw_got
    cmp w0, #32
    b.eq _nw_got
    cmp w0, #10
    b.eq _nw_got
    cmp w0, #9
    b.eq _nw_got
    add x19, x19, #1
    b _nw_scan

_nw_got:
    sub x1, x19, x20
    cbz x1, _nw_eof

    // Consume trailing delimiter (space/tab/CR/LF), matching WORD and
    // PARSE-NAME. Hayes prelimtest relies on this: after `+!` in
    // `1 >IN +! xSOURCE`, >IN must point at `x` so `1 >IN +!` skips it.
    // Leaving >IN *on* the blank made `1 >IN +!` land on `x` → xSOURCE.
    cmp x19, x21
    b.hs _nw_copy_prep
    ldrb w0, [x19]
    cbz w0, _nw_copy_prep
    cmp w0, #32
    b.eq _nw_cons
    cmp w0, #9
    b.eq _nw_cons
    cmp w0, #10
    b.eq _nw_cons
    cmp w0, #13
    b.ne _nw_copy_prep
_nw_cons:
    add x19, x19, #1
_nw_copy_prep:

    // Copy to word_scratch (cap WORD_SCRATCH_MAX-1; leave room for NUL)
    adrp x2, word_scratch@page
    add x2, x2, word_scratch@pageoff
    mov x5, #511                   // max chars
    cmp x1, x5
    csel x1, x5, x1, hi
    mov x3, #0
_nw_copy:
    cmp x3, x1
    b.ge _nw_copied
    ldrb w4, [x20, x3]
    strb w4, [x2, x3]
    add x3, x3, #1
    b _nw_copy
_nw_copied:
    strb wzr, [x2, x3]

    // update >IN (preserve len x1 and scratch x2)
    stp x1, x2, [sp, #-16]!
    mov x0, x19
    bl _cursor_store
    ldp x1, x2, [sp], #16

    mov x0, x2
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_nw_eof:
    mov x0, #0
    mov x1, #0
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _parse_number: x0=addr, x1=len
//   -> x0=1 single (value in x1)
//   -> x0=2 double (lo in x1, hi in x2)  when token ends with '.'
//   -> x0=0 fail
// Honors BASE (2..36). Optional leading # $ % base prefixes (decimal/hex/binary).
// Digits: 0-9, A-Z / a-z. Optional leading '-'. Trailing '.' → double (hi=sign).
_parse_number:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    mov x19, x0                 // addr
    mov x20, x1                 // len
    mov x23, #0                 // double flag
    mov x24, #0                 // lo accumulator (we only fill 64-bit for now)
    mov x2, #0                  // accumulator (grows; for large values only low 64)
    mov x3, #0                  // digit count
    mov x4, #0                  // negative flag
    // base from BASE
    adrp x21, base_var@page
    add x21, x21, base_var@pageoff
    ldr x21, [x21]
    cmp x21, #2
    b.lo _pn_base10
    cmp x21, #36
    b.ls _pn_base_ok
_pn_base10:
    mov x21, #10
_pn_base_ok:
    cbz x20, _pn_fail
    // trailing '.' → double number
    add x0, x19, x20
    ldrb w5, [x0, #-1]
    cmp w5, #46                 // '.'
    b.ne _pn_prefix
    mov x23, #1
    sub x20, x20, #1
    cbz x20, _pn_fail
_pn_prefix:
    ldrb w5, [x19]
    cmp w5, #45                 // '-'
    b.ne _pn_base_prefix
    mov x4, #1
    add x19, x19, #1
    sub x20, x20, #1
    cbz x20, _pn_fail
    ldrb w5, [x19]
_pn_base_prefix:
    // # decimal  $ hex  % binary
    cmp w5, #35                 // '#'
    b.ne 1f
    mov x21, #10
    add x19, x19, #1
    sub x20, x20, #1
    b _pn_loop
1:  cmp w5, #36                 // '$'
    b.ne 2f
    mov x21, #16
    add x19, x19, #1
    sub x20, x20, #1
    b _pn_loop
2:  cmp w5, #37                 // '%'
    b.ne _pn_loop
    mov x21, #2
    add x19, x19, #1
    sub x20, x20, #1
_pn_loop:
    cbz x20, _pn_done
    ldrb w5, [x19], #1
    sub w22, w5, #48
    cmp w22, #9
    b.ls _pn_have_digit
    mov w22, w5
    cmp w22, #97
    b.lo _pn_upper
    cmp w22, #122
    b.hi _pn_fail
    sub w22, w22, #32
_pn_upper:
    sub w22, w22, #65
    cmp w22, #25
    b.hi _pn_fail
    add w22, w22, #10
_pn_have_digit:
    cmp x22, x21
    b.hs _pn_fail
    // 128-bit-ish: x24:x2 = x24:x2 * base + digit (x2=lo, x24=hi)
    // lo * base
    mul x0, x2, x21
    umulh x1, x2, x21
    // hi * base + lo_hi
    mul x5, x24, x21
    add x1, x1, x5
    mov x2, x0
    mov x24, x1
    add x2, x2, x22
    // carry into hi if lo overflowed (add digit rarely overflows after mul)
    cmp x2, x22
    b.hs 3f
    add x24, x24, #1
3:
    add x3, x3, #1
    sub x20, x20, #1
    b _pn_loop
_pn_done:
    cbz x3, _pn_fail
    cbz x4, _pn_pos
    // negate 128-bit x24:x2
    mov x0, xzr
    subs x2, x0, x2
    sbc  x24, x0, x24
_pn_pos:
    cbnz x23, _pn_dbl
    mov x0, #1
    mov x1, x2
    b _pn_ret
_pn_dbl:
    mov x0, #2
    mov x1, x2                     // lo
    mov x2, x24                    // hi
_pn_ret:
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
_pn_fail:
    mov x0, #0
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _find_word: x0=addr, x1=len -> x0=CFA or 0, x1=FLAGS (bit32=IMM)
// Walks search_order wordlists (ANS Search-Order).
_find_word:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    cbz x0, _fw_fail
    cmp x1, #256
    b.hi _fw_fail
    mov x19, x0                    // search name
    mov x20, x1                    // len
    // Keep x24 = &latest_var for rest of VM
    adrp x24, latest_var@page
    add  x24, x24, latest_var@pageoff
    // Order index
    mov  x23, #0
_fw_wl:
    adrp x0, search_order_n@page
    add  x0, x0, search_order_n@pageoff
    ldr  x0, [x0]
    cmp  x23, x0
    b.hs _fw_fail
    adrp x0, search_order@page
    add  x0, x0, search_order@pageoff
    ldr  x0, [x0, x23, lsl #3]     // wid
    cbz  x0, _fw_next_wl
    ldr  x21, [x0]                 // latest CFA in this wordlist
_fw_loop:
    cbz x21, _fw_next_wl
    ldr x2, [x21, #-8]             // FLAGS
    and x3, x2, #0xFFFFFFFF        // NFA_OFF
    sub x4, x21, x3                // NFA
    ldrb w3, [x4], #1              // name len; x4 -> chars
    cmp x3, x20
    b.ne _fw_next
    mov x5, #0
_fw_cmp:
    cmp x5, x20
    b.ge _fw_match
    ldrb w6, [x4, x5]
    ldrb w7, [x19, x5]
    cmp w7, #'a'
    b.lo _fw_eq
    cmp w7, #'z'
    b.hi _fw_eq
    sub w7, w7, #32
_fw_eq:
    cmp w6, w7
    b.ne _fw_next
    add x5, x5, #1
    b _fw_cmp
_fw_match:
    mov x0, x21                    // CFA
    ldr x1, [x21, #-8]             // FLAGS
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
_fw_next:
    ldr x21, [x21, #-16]           // LINK at CFA-16
    b _fw_loop
_fw_next_wl:
    add x23, x23, #1
    b _fw_wl
_fw_fail:
    mov x0, #0
    mov x1, #0
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _warn_redef: x0=name addr, x1=len
// If name is already in the dictionary, print:  <name> is redefined\n
// Gated by REDEF-WARNING (redef_warn cell): 0 = quiet, nonzero = warn.
// Cell is 0 during bootstrap; set to TRUE (-1) when entering QUIT.
_warn_redef:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    adrp x2, redef_warn@page
    add x2, x2, redef_warn@pageoff
    ldr x2, [x2]
    cbz x2, _wr_done
    mov x19, x0                     // name
    mov x20, x1                     // len
    bl _find_word
    cbz x0, _wr_done
    // write name
    cbz x20, 1f
    mov x0, #1                      // stdout
    mov x1, x19
    mov x2, x20
    mov x16, #4                     // write
    svc #0x80
1:
    mov x0, #1
    adrp x1, str_redef@page
    add x1, x1, str_redef@pageoff
    mov x2, #15                     // " is redefined\n"
    mov x16, #4
    svc #0x80
_wr_done:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _compile_cell: x0 = value, compile at HERE (bounds-checked)
// On overflow: message + abandon (same as ALLOT over dict end).
_compile_cell:
    adrp x1, here_ptr@page
    add  x1, x1, here_ptr@pageoff
    ldr  x2, [x1]                  // HERE
    add  x3, x2, #8                // candidate HERE
    adrp x4, user_dict_area@page
    add  x4, x4, user_dict_area@pageoff
    adrp x5, user_dict_size_cell@page
    add  x5, x5, user_dict_size_cell@pageoff
    ldr  x5, [x5]
    add  x5, x4, x5                // end
    cmp  x3, x5
    b.hi 1f
    str  x0, [x2]
    str  x3, [x1]
    ret
1:
    // clobber-safe: we will not return
    adrp x0, str_dict_full@page
    add  x0, x0, str_dict_full@pageoff
    bl   _print_string_svc
    b    _error_abandon

// _print_signed: x0=value  (uses BASE; leading '-' if negative)
_print_signed:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #80             // 16-byte aligned; room for digits + sign + NUL
    mov x1, sp
    bl _i64_to_str
    mov x0, sp
    bl _print_string_svc
    add sp, sp, #80
    ldp x29, x30, [sp], #16
    ret

// _print_unsigned: x0=value  (uses BASE; always unsigned)
_print_unsigned:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #80
    mov x1, sp
    bl _u64_to_str
    mov x0, sp
    bl _print_string_svc
    add sp, sp, #80
    ldp x29, x30, [sp], #16
    ret

// _load_base: -> x6 = BASE clamped to 2..36
_load_base:
    adrp x6, base_var@page
    add x6, x6, base_var@pageoff
    ldr x6, [x6]
    cmp x6, #2
    b.lo _lb_def
    cmp x6, #36
    b.ls _lb_ok
_lb_def:
    mov x6, #10
_lb_ok:
    ret

// _digit_char: w8 = digit value 0..35 -> ASCII in w8
_digit_char:
    cmp w8, #9
    b.hi _dc_alpha
    add w8, w8, #48             // '0'
    ret
_dc_alpha:
    add w8, w8, #55             // 'A' - 10
    ret

// _i64_to_str: x0=val, x1=buf — signed, current BASE
_i64_to_str:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x2, x1                  // write ptr
    add x3, x1, #64             // temp digit area near end of 72-byte buf
    mov x4, x0                  // value
    mov x5, #0                  // digit count
    bl _load_base               // x6 = base
    mov x19, x6
    cmp x4, #0
    b.ge _i2s_pos
    mov w6, #45
    strb w6, [x2], #1           // '-'
    neg x4, x4
_i2s_pos:
    cbnz x4, _i2s_div
    mov w6, #48
    strb w6, [x2], #1
    strb wzr, [x2]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
_i2s_div:
    udiv x7, x4, x19
    msub x8, x7, x19, x4        // remainder
    bl _digit_char
    strb w8, [x3, #-1]!
    add x5, x5, #1
    mov x4, x7
    cbnz x4, _i2s_div
_i2s_cpy:
    cbz x5, _i2s_done
    ldrb w8, [x3], #1
    strb w8, [x2], #1
    sub x5, x5, #1
    b _i2s_cpy
_i2s_done:
    strb wzr, [x2]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _u64_to_str: x0=val, x1=buf — unsigned, current BASE
_u64_to_str:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x2, x1
    add x3, x1, #64
    mov x4, x0
    mov x5, #0
    bl _load_base
    mov x19, x6
    cbnz x4, _u2s_div
    mov w6, #48
    strb w6, [x2], #1
    strb wzr, [x2]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
_u2s_div:
    udiv x7, x4, x19
    msub x8, x7, x19, x4
    bl _digit_char
    strb w8, [x3, #-1]!
    add x5, x5, #1
    mov x4, x7
    cbnz x4, _u2s_div
_u2s_cpy:
    cbz x5, _u2s_done
    ldrb w8, [x3], #1
    strb w8, [x2], #1
    sub x5, x5, #1
    b _u2s_cpy
_u2s_done:
    strb wzr, [x2]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// _print_dots: print stack without destroying DSP/TOS.
// Empty: DSP==base, TOS=0. Each DPUSH stores previous TOS; after n pushes
// from empty, mem is [v_{n-1},...,v1,0_sentinel] and x20=v_n. Skip sentinel.
// Callee-saved x19-x22 only — do not rely on x0-x18 across bl.
_print_dots:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    adrp x19, data_stack@page
    add x19, x19, data_stack@pageoff
    add x19, x19, #4096            // stack base

    cmp x22, x19
    b.ge _pd_empty

    sub x21, x19, x22
    lsr x21, x21, #3               // mem_cells >= 1; depth == mem_cells

    mov x0, x21
    bl _print_unsigned
    mov x0, #58                    // ':'
    bl _putchar
    mov x0, #32
    bl _putchar

    // under-TOS items at indices mem_cells-2 .. 0 (skip sentinel at mem_cells-1)
    // x19 = loop index (callee-saved)
    cmp x21, #1
    b.eq _pd_print_tos
    sub x19, x21, #1               // x19 = mem_cells - 1
_pd_mem_loop:
    sub x19, x19, #1
    lsl x0, x19, #3
    ldr x0, [x22, x0]
    bl _print_signed
    mov x0, #32
    bl _putchar
    cbnz x19, _pd_mem_loop

_pd_print_tos:
    mov x0, x20
    bl _print_signed
    mov x0, #32
    bl _putchar
    b _pd_done

_pd_empty:
    mov x0, #48                    // '0'
    bl _putchar
    mov x0, #58                    // ':'
    bl _putchar

_pd_done:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

// XRESTART: trampoline code that returns to the interpreter loop.
// Must be in __text (executable) section, NOT in .data.
.align 8
XRESTART:
    b _interpret_loop

// ============================================================================
// Data Section
// ============================================================================
.data
.align 8

data_stack:     .skip 4096
return_stack:   .skip 2048
input_buffer:   .skip 1024
file_buffer:    .skip 65536
word_scratch:   .skip 512          // paths for INCLUDE / FLOAD (was 64)
tty_termios_save: .skip 80
tty_termios_raw:  .skip 80
tty_raw_active:   .quad 0
redef_warn:       .quad 0           // REDEF-WARNING body; 0=off, nonzero=on (TRUE after boot)
redef_boot_done:  .quad 0           // set after first QUIT so default TRUE applied once
file_echo:        .quad 0           // FILE-ECHO body; 0=off, nonzero=on
file_echo_pos:    .quad 0           // absolute addr: next source byte not yet echoed
noname_xt:        .quad 0           // :NONAME entry; ; pushes then clears
slit_esc_buf:     .skip 256         // S\" interpret expansion buffer
// Line history (see HIST_MAX / HIST_LINE)
hist_data:        .skip HIST_MAX * HIST_LINE
hist_draft:       .skip HIST_LINE
hist_count:       .quad 0
hist_head:        .quad 0
hist_nav:         .quad -1
hist_draft_len:   .quad 0

state_var:      .quad 0
base_var:       .quad 10
blk_var:        .quad 0            // BLK body (0 = not interpreting a block)
scr_var:        .quad 0            // SCR body
block_file_var: .quad 0            // current volume fileid (0 = none)
block_nr:       .quad -1           // block number currently in block_buf (-1 empty)
block_upd:      .quad 0            // nonzero = block_buf dirty
.align 8
block_buf:      .skip 1024         // single 1K block buffer
here_ptr:       .quad 0
latest_var:     .quad 0
current_var:    .quad 0            // wid (addr of wordlist head cell)
search_order:   .skip 64           // 8 wids
search_order_n: .quad 0
host_tmp0:      .skip 32           // scratch for host ABI
host_tmp1:      .quad 0
word_cursor:    .quad 0
source_addr:    .quad 0
source_len:     .quad 0
to_in_var:      .quad 0
repl_batch_stop: .quad 0           // set by \S on SOURCE-ID 0; host takes via kernel_take_repl_batch_stop
pad_buffer:     .skip 256
hold_ptr:       .quad 0
// Nested SOURCE stack: 8 frames * 5 quads (addr, len, >IN, source-id, file_echo_pos)
source_stack:   .skip 320
source_sp:      .quad 0
source_id_var:  .quad 0
throw_handler:  .quad 0

// ENVIRONMENT? tables (name ptrs, value cells, kinds: 0=flag only, 1=value+true)
.equ ENV_COUNT, 10
.align 8
env_name_ptrs:
    .quad env_n_counted
    .quad env_n_aub
    .quad env_n_core
    .quad env_n_core_ext
    .quad env_n_floored
    .quad env_n_maxchar
    .quad env_n_maxn
    .quad env_n_maxu
    .quad env_n_rstack
    .quad env_n_stack
env_values:
    .quad 255                      // /COUNTED-STRING
    .quad 8                        // ADDRESS-UNIT-BITS
    .quad -1                       // CORE (flag)
    .quad -1                       // CORE-EXT (true — names present)
    .quad 0                        // FLOORED (false — we use symmetric /)
    .quad 255                      // MAX-CHAR
    .quad 0x7FFFFFFFFFFFFFFF       // MAX-N
    .quad 0xFFFFFFFFFFFFFFFF       // MAX-U
    .quad 256                      // RETURN-STACK-CELLS (2048/8)
    .quad 512                      // STACK-CELLS (4096/8)
env_kinds:
    .byte 1, 1, 0, 0, 0, 1, 1, 1, 1, 1
    .space 6
env_n_counted:  .asciz "/COUNTED-STRING"
env_n_aub:      .asciz "ADDRESS-UNIT-BITS"
env_n_core:     .asciz "CORE"
env_n_core_ext: .asciz "CORE-EXT"
env_n_floored:  .asciz "FLOORED"
env_n_maxchar:  .asciz "MAX-CHAR"
env_n_maxn:     .asciz "MAX-N"
env_n_maxu:     .asciz "MAX-U"
env_n_rstack:   .asciz "RETURN-STACK-CELLS"
env_n_stack:    .asciz "STACK-CELLS"

str_hello:  .asciz "PickleForth v0.4.0\n"
str_prompt: .asciz "\nok> "
str_ok:     .asciz " ok\n"
str_bye:    .asciz "Bye!\n"
str_quest:  .asciz "? "
str_uncaught_throw: .asciz "uncaught THROW "
str_cant_open:  .ascii "can't open: "
                .byte 0
str_undefined:  .ascii "undefined: "
                .byte 0
str_protected:  .asciz "protected (system word)\n"
                .byte 0
str_underflow:  .asciz "stack underflow\n"
str_overflow:   .asciz "stack overflow\n"
str_memfault:   .asciz "memory access error\n"
str_allot_over: .asciz "ALLOT: dictionary full (need more USER-DICT space)\n"
str_allot_under:.asciz "ALLOT: below dictionary start\n"
str_dict_full:  .asciz "dictionary full (code/data space exhausted)\n"
str_gmm_already:.asciz "? GROWMEMORYMB already used (once per session)\n"
str_gmm_small:  .asciz "? GROWMEMORYMB needs at least 1 MB\n"
str_gmm_big:    .asciz "? GROWMEMORYMB exceeds maximum (64 MB)\n"
str_gmm_shrink: .asciz "? GROWMEMORYMB cannot shrink memory\n"
str_redef:  .asciz " is redefined\n"
.align 8
quit_jmpbuf:        .skip 256      // sigjmp_buf for fault recovery
fault_handlers_on:  .quad 0
fault_pending:      .quad 0        // set in signal handler; cleared after message
str_x:      .asciz "X"

// Embed API state (Phase 1–3)
.align 8
embed_mode:     .quad 0            // 0 = terminal cold start, 1 = host embed
emit_hook:      .quad 0            // void (*)(int c)
key_hook:       .quad 0            // int (*)(void) — KEY (blocking)
key_q_hook:     .quad 0            // int (*)(void) — KEY? (non-zero if ready)
time_date_hook: .quad 0            // void (*)(int64_t out[6]) — TIME&DATE
file_op_hook:   .quad 0            // file_op multiplex
fromlib_hook:   .quad 0            // void (*)(void) — FROMLIB arm
fromlib_clear_hook: .quad 0        // void (*)(void) — FROMLIB disarm (REQUIRE skip)
end_include_hook: .quad 0          // void (*)(void) — file INCLUDE SOURCE ended (restore load cwd)
load_file_hook: .quad 0            // int (*)(path, path_len, out_ptr*, out_len*); path_len 0 = bare
resolve_key_hook: .quad 0          // resolve path → absolute key
last_load_key_hook: .quad 0        // absolute key of last successful load
chdir_hook:     .quad 0            // void (*)(path, path_len); path_len 0 = bare picker
pwd_hook:       .quad 0            // void (*)(void)
dir_hook:       .quad 0            // void (*)(path, path_len); path_len 0 = list cwd
edit_hook:      .quad 0            // void (*)(path, path_len); path_len 0 = bare EDIT dialog
alloc_hook:     .quad 0            // int (*)(size_t n, void **out)
free_hook:      .quad 0            // int (*)(void *p)
bi_mul_hook:    .quad 0            // void (*)(int64 a, int64 b, int64 r)
bi_divmod_hook: .quad 0            // void (*)(int64 num, den, quot, rem)
bi_isqrt_hook:   .quad 0            // void (*)(int64 a, int64 r)
kernel_inited:  .quad 0

str_search_order: .asciz "Search order: "
str_comp_wl:      .asciz "Compilation wordlist: "
str_forth_name:   .asciz "FORTH"
str_wid:          .asciz "wid"
str_words_hdr1:   .asciz "--- "
str_words_hdr2:   .asciz " ---"
str_words_sys:    .asciz "64Forth System Words\n"
str_words_user:   .asciz "64Forth User Words\n"
str_included_hdr: .asciz "Included:\n"
str_included_none: .asciz "  (none)\n"
.align 8
words_filter_len: .quad 0
words_filter:     .skip 64          // uppercased filter substring
words_cfa:        .skip WORDS_MAX * 8  // CFA list for WORDS (kernel then user)
words_user_base:  .quad 0           // HERE after bootstrap; CFA >= this → user word
words_nk_tmp:     .quad 0           // kernel count during WORDS
forget_cut:       .quad 0           // FORGET cut CFA (must not live in x19/IP)
// REQUIRE / INCLUDED-NAMES style registry (parse-name keys)
.align 8
included_count:       .quad 0
include_name_len:     .quad 0
include_name_pending: .skip INCL_NAME
included_names:       .skip INCL_MAX * INCL_NAME
embed_c_sp:     .quad 0            // C stack frame for return from interpret
vm_tos:         .quad 0
vm_dsp:         .quad 0
vm_rsp:         .quad 0
eval_arg_ptr:   .quad 0
eval_arg_len:   .quad 0

// ============================================================================
// High-level Forth bootstrap (interpreted once at startup)
// Prefer new user-facing words here; assembly only for needed primitives.
//
// Dictionary field helpers (xt = CFA from ' or FIND):
//   >LINK  ( xt -- a-addr )  LINK at CFA-16
//   >FLAGS ( xt -- a-addr )  FLAGS at CFA-8  (low32=NFA_OFF, bit32=IMM)
//   >CODE  ( xt -- a-addr )  CFA itself (code field)
//   >BODY  ( xt -- a-addr )  CFA+8
//   NAME>STRING via NFA = CFA - NFA_OFF
// ============================================================================
forth_init_str:
    // Order matters: define dependencies before users.

    // DOC" needs SETDOC (CODE). Define DOC" first, then document HERE via redefine.
    .ascii ": DOC\" 34 PARSE SETDOC ; "
    .ascii "DOC\" HERE ( -- addr ) current dictionary pointer (DP @)\" "
    .ascii ": HERE DP @ ; "

    // --- 1. Simple ANS helpers ---
    .ascii "DOC\" CHAR+ ( addr -- addr' ) add size of one char\" "
    .ascii ": CHAR+ 1+ ; "
    .ascii "DOC\" CHARS ( n -- n ) chars to address units\" "
    .ascii ": CHARS ; "
    .ascii "DOC\" CELL+ ( addr -- addr' ) add size of one cell\" "
    .ascii ": CELL+ 8 + ; "
    .ascii "DOC\" CELLS ( n -- n ) cells to address units\" "
    .ascii ": CELLS 8 * ; "
    .ascii "DOC\" ALIGNED ( addr -- addr' ) next aligned address\" "
    .ascii ": ALIGNED 7 + 7 INVERT AND ; "
    .ascii "DOC\" ALIGN ( -- ) align DP to cell boundary\" "
    .ascii ": ALIGN HERE ALIGNED HERE - ALLOT ; "
    .ascii "DOC\" 2DUP ( n1 n2 -- n1 n2 n1 n2 ) duplicate pair\" "
    .ascii ": 2DUP OVER OVER ; "
    .ascii "DOC\" 2DROP ( n1 n2 -- ) drop two items\" "
    .ascii ": 2DROP DROP DROP ; "
    .ascii "DOC\" 2SWAP ( n1 n2 n3 n4 -- n3 n4 n1 n2 ) swap pairs\" "
    .ascii ": 2SWAP ROT >R ROT R> ; "
    .ascii "DOC\" 2OVER ( n1 n2 n3 n4 -- n1 n2 n3 n4 n1 n2 ) copy second pair\" "
    .ascii ": 2OVER >R >R 2DUP R> R> 2SWAP ; "
    .ascii "DOC\" COUNT ( c-addr -- addr u ) from counted string addr return char-addr and length\" "
    .ascii ": COUNT DUP C@ SWAP CHAR+ SWAP ; "
    .ascii "DOC\" /STRING ( c-addr u n -- c-addr' u' ) adjust string by n characters\" "
    .ascii ": /STRING DUP >R - SWAP R> + SWAP ; "
    .ascii "DOC\" DECIMAL ( -- ) set BASE to 10\" "
    .ascii ": DECIMAL 10 BASE ! ; "
    .ascii "DOC\" HEX ( -- ) set BASE to 16\" "
    .ascii ": HEX 16 BASE ! ; "
    // 0<> 0> WITHIN U> are CODE primitives (boot table)
    .ascii "DOC\" >= ( n1 n2 -- flag ) greater or equal\" "
    .ascii ": >= < 0= ; "
    .ascii "DOC\" <= ( n1 n2 -- flag ) less or equal\" "
    .ascii ": <= > 0= ; "

    // --- 2. Dictionary field accessors (xt = CFA) ---
    .ascii "DOC\" >LINK ( xt -- a-addr ) link field address\" "
    .ascii ": >LINK 16 - ; "
    .ascii "DOC\" >FLAGS ( xt -- a-addr ) flags field address\" "
    .ascii ": >FLAGS 8 - ; "
    .ascii "DOC\" >CODE ( xt -- a-addr ) code field (xt itself)\" "
    .ascii ": >CODE ; "
    .ascii "DOC\" >BODY ( xt -- addr ) data field of a CREATEd word\" "
    .ascii ": >BODY 8 + ; "
    // Layout: HFA help | NFA name | LFA | FLAGS | CFA | BODY
    // FLAGS: low32 NFA_OFF, bits32-62 HFA_OFF, bit63 IMM
    .ascii "DOC\" NFA ( xt -- nfa ) name field address\" "
    .ascii ": NFA DUP >FLAGS @ 4294967295 AND - ; "
    .ascii "DOC\" HFA ( xt -- hfa ) help field address\" "
    .ascii ": HFA DUP >FLAGS @ 32 RSHIFT 2147483647 AND - ; "
    .ascii "DOC\" NAME>STRING ( nt -- c-addr u ) copy name token name to buffer (valid until next NAME>STRING)\" "
    .ascii ": NAME>STRING NFA COUNT ; "
    .ascii "DOC\" NAME>HELP ( xt -- c-addr u ) help string\" "
    .ascii ": NAME>HELP HFA COUNT ; "
    // Early DOCOL? so tools work even if later forth_init aborts
    .ascii "DOC\" DOCOL? ( xt -- flag ) true if colon definition\" "
    .ascii ": DOCOL? @ DOCOL-ADDR = ; "
    // DOC" text" — pending help for next defining word (help should start with name)
    // Documented high-level words (DOC" then : … ;)
    .ascii "DOC\" BL ( -- c ) ASCII blank (space)\" "
    .ascii ": BL 32 ; "
    .ascii "DOC\" SPACE ( -- ) emit one space\" "
    .ascii ": SPACE BL EMIT ; "

    // --- 3. Control flow (immediate) ---
    // Bootstrap order is strict:
    //   1) BEGIN/UNTIL/AGAIN, IF/THEN/ELSE/WHILE/REPEAT  (no ?COMP needed)
    //   2) ?COMP  (body uses IF/THEN — must not be defined before them)
    //   3) AHEAD / DO / LOOP…  (compile a call to ?COMP)
    // Putting ?COMP before IF left a half-built colon word (no EXIT); typing
    // ?COMP then crashed in NEXT after 0=. Putting AHEAD before ?COMP aborted
    // the rest of forth_init (undefined: ?COMP).
    .ascii "DOC\" BEGIN ( -- ) start indefinite loop (immediate)\" "
    .ascii ": BEGIN HERE ; IMMEDIATE "
    .ascii "DOC\" UNTIL ( flag -- ) loop until true (immediate)\" "
    .ascii ": UNTIL 0BRANCH-ADDR , HERE - , ; IMMEDIATE "
    .ascii "DOC\" AGAIN ( -- ) unconditional branch back (immediate)\" "
    .ascii ": AGAIN BRANCH-ADDR , HERE - , ; IMMEDIATE "
    .ascii "DOC\" IF ( flag -- ) conditional (immediate)\" "
    .ascii ": IF 0BRANCH-ADDR , HERE 0 , ; IMMEDIATE "
    .ascii "DOC\" THEN ( -- ) end of IF/ELSE (immediate)\" "
    .ascii ": THEN HERE OVER - SWAP ! ; IMMEDIATE "
    .ascii "DOC\" ELSE ( -- ) else part of IF (immediate)\" "
    .ascii ": ELSE BRANCH-ADDR , HERE 0 , SWAP HERE OVER - SWAP ! ; IMMEDIATE "
    .ascii "DOC\" WHILE ( flag -- ) conditional exit from BEGIN (immediate)\" "
    .ascii ": WHILE 0BRANCH-ADDR , HERE 0 , ; IMMEDIATE "
    .ascii "DOC\" REPEAT ( -- ) branch back from WHILE (immediate)\" "
    .ascii ": REPEAT BRANCH-ADDR , SWAP HERE - , HERE OVER - SWAP ! ; IMMEDIATE "
    .ascii "DOC\" ?COMP ( -- ) error if not compiling\" "
    .ascii ": ?COMP STATE @ 0= IF S\" compile only\" TYPE CR -14 THROW THEN ; "
    .ascii "DOC\" AHEAD ( -- orig ) compile forward branch (immediate; resolve with THEN)\" "
    .ascii ": AHEAD ?COMP BRANCH-ADDR , HERE 0 , ; IMMEDIATE "

    // DO/LOOP: ( limit start -- ) ... LOOP    classic Forth order: limit first
    // DO leaves ( 0 dest ); ?DO leaves ( orig dest ) so LOOP/+LOOP can resolve
    // the empty-range forward branch after (?DO).
    .ascii "DOC\" DO ( limit start -- ) start counted loop\" "
    .ascii ": DO ?COMP ['] (DO) , 0 HERE ; IMMEDIATE "
    .ascii "DOC\" ?DO ( limit start -- ) start counted loop that skips if start==limit\" "
    .ascii ": ?DO ?COMP ['] (?DO) , HERE 0 , HERE ; IMMEDIATE "
    .ascii "DOC\" LOOP ( -- ) end DO loop (add 1 to index, branch back if < limit)\" "
    .ascii ": LOOP ?COMP ['] (LOOP) , HERE - , ?DUP IF HERE OVER - SWAP ! THEN ; IMMEDIATE "
    .ascii "DOC\" +LOOP ( n -- ) end DO loop with custom increment (delta from stack)\" "
    .ascii ": +LOOP ?COMP ['] (+LOOP) , HERE - , ?DUP IF HERE OVER - SWAP ! THEN ; IMMEDIATE "

    // --- 4. Defining words / parse helpers using the above ---
    .ascii "DOC\" CHAR ( 'name' -- char ) first character of next word\" "
    .ascii ": CHAR BL WORD COUNT DROP C@ ; "
    .ascii "DOC\" [CHAR] ( 'name' -- ) compile first char of name as literal (immediate)\" "
    .ascii ": [CHAR] ?COMP CHAR LIT-ADDR , , ; IMMEDIATE "
    .ascii "DOC\" VARIABLE ( 'name' -- ) create a variable\" "
    .ascii ": VARIABLE CREATE 0 , ; "
    // CONSTANT via DOES> (body+0=does_ip, body+8=value; DOES> action @ )
    .ascii "DOC\" CONSTANT ( x 'name' -- ) create a constant\" "
    .ascii ": CONSTANT CREATE , DOES> @ ; "
    .ascii "DOC\" RECURSE ( -- ) recurse into current definition (immediate)\" "
    .ascii ": RECURSE ?COMP CURRENT @ @ , ; IMMEDIATE "

    // --- Search-Order / VOCABULARY (ANS-style; BIG-INTEGER for host BI) ---
    .ascii "DOC\" VOCABULARY ( 'name' -- ) named word list; execute to push onto search order\" "
    .ascii ": VOCABULARY CREATE WORDLIST DROP DOES> PUSH-ORDER ; "
    .ascii "VOCABULARY BIG-INTEGER "
    .ascii "VOCABULARY EDITOR "
    .ascii "VOCABULARY ASSEMBLER "
    .ascii "ONLY FORTH DEFINITIONS "

    // --- 4b. Pictured numeric output (single-cell); . and U. stay native (BASE-aware) ---
    .ascii "DOC\" HLD ( -- addr ) pictured output pointer variable\" "
    .ascii "VARIABLE HLD "
    .ascii "DOC\" <# ( -- ) begin pictured numeric output\" "
    .ascii ": <# PAD 256 + HLD ! ; "
    .ascii "DOC\" HOLD ( char -- ) insert char into pictured output\" "
    .ascii ": HOLD -1 HLD +! HLD @ C! ; "
    // ANS pictured output is double-cell (ud = lo under, hi TOS).
    // Single-cell form was wrong for `n 0 <# #S #>` (used by BI. / BI-U.9) and
    // printed only the high cell — π and other BI output collapsed to 0.000…
    .ascii "DOC\" #> ( xd -- c-addr u ) end pictured numeric, return string\" "
    .ascii ": #> 2DROP HLD @ PAD 256 + OVER - ; "
    .ascii "DOC\" # ( ud1 -- ud2 ) convert one digit of pictured numeric output\" "
    .ascii ": # 0 BASE @ UM/MOD >R BASE @ UM/MOD R> ROT DUP 9 > IF 7 + THEN 48 + HOLD ; "
    .ascii "DOC\" #S ( ud1 -- ud2 ) convert remaining digits of pictured numeric output\" "
    .ascii ": #S BEGIN # 2DUP OR 0= UNTIL ; "
    .ascii "DOC\" SIGN ( n -- ) insert minus sign if n<0 into pictured\" "
    .ascii ": SIGN 0< IF 45 HOLD THEN ; "
    // Formatted print using pictured output (native . / U. remain)
    .ascii "DOC\" UD. ( ud -- ) print unsigned double\" "
    .ascii ": UD. <# #S #> TYPE SPACE ; "
    .ascii "DOC\" D. ( n -- ) print signed single in current BASE via pictured output\" "
    .ascii ": D. DUP 0< IF NEGATE 0 <# #S 45 HOLD #> ELSE 0 <# #S #> THEN TYPE SPACE ; "
    // FILL ( c-addr u char -- ); stack top is u, so bump addr via SWAP 1+ SWAP
    .ascii "DOC\" FILL ( addr u b -- ) fill u bytes at addr with b\" "
    .ascii ": FILL >R BEGIN DUP WHILE OVER R@ SWAP C! SWAP 1+ SWAP 1- REPEAT R> DROP 2DROP ; "
    .ascii "DOC\" ERASE ( addr u -- ) fill u bytes at addr with zero\" "
    .ascii ": ERASE 0 FILL ; "
    // MOVE / CMOVE (ANS character/cell move; MOVE handles overlap)
    .ascii "DOC\" CMOVE ( c-addr1 c-addr2 u -- ) copy u chars from c-addr1 to c-addr2 (low→high)\" "
    .ascii ": CMOVE BEGIN DUP WHILE >R OVER C@ OVER C! CHAR+ SWAP CHAR+ SWAP R> 1- REPEAT DROP 2DROP ; "
    .ascii "DOC\" CMOVE> ( c-addr1 c-addr2 u -- ) copy u chars from c-addr1 to c-addr2 (high→low)\" "
    .ascii ": CMOVE> DUP >R + 1- SWAP R@ + 1- SWAP R> BEGIN DUP WHILE >R OVER C@ OVER C! 1- SWAP 1- SWAP R> 1- REPEAT DROP 2DROP ; "
    .ascii "DOC\" MOVE ( addr1 addr2 u -- ) copy u bytes\" "
    .ascii ": MOVE DUP 0= IF DROP 2DROP EXIT THEN >R 2DUP U< IF R> CMOVE> ELSE R> CMOVE THEN ; "

    // POSTPONE (ANS, compilation only):
    //   immediate:     compile xt (runs when outer word runs)
    //   non-immediate: compile LIT xt (COMP,)  so runtime compiles xt via ,
    .ascii "DOC\" (COMP,) ( xt -- ) compile xt (for POSTPONE)\" "
    .ascii ": (COMP,) , ; "
    .ascii "DOC\" POSTPONE ( 'name' -- ) compile compilation semantics of name (immediate)\" "
    .ascii ": POSTPONE ?COMP BL WORD FIND DUP 0= IF 2DROP EXIT THEN 1 = IF , ELSE LIT-ADDR , , ['] (COMP,) , THEN ; IMMEDIATE "

    // CASE OF ENDOF ENDCASE (ANS-style; compilation only)
    .ascii "DOC\" CASE ( -- ) start CASE structure (immediate)\" "
    .ascii ": CASE ?COMP 0 ; IMMEDIATE "
    .ascii "DOC\" OF ( x x -- | x ) CASE of branch (immediate)\" "
    .ascii ": OF ?COMP 1+ >R POSTPONE OVER POSTPONE = POSTPONE IF POSTPONE DROP R> ; IMMEDIATE "
    .ascii "DOC\" ENDOF ( -- ) end of OF, branch to ENDCASE (immediate)\" "
    .ascii ": ENDOF ?COMP >R POSTPONE ELSE R> ; IMMEDIATE "

    // Programming-Tools: interpret-time conditionals (Hayes / bi-test / HayesTest.fth)
    .ascii "DOC\" [DEFINED] ( 'name' -- flag ) true if name is found (immediate)\" "
    .ascii ": [DEFINED] BL WORD FIND NIP 0<> ; IMMEDIATE "
    .ascii "DOC\" [UNDEFINED] ( 'name' -- flag ) true if name is not found (immediate)\" "
    .ascii ": [UNDEFINED] BL WORD FIND NIP 0= ; IMMEDIATE "
    .ascii "DOC\" [THEN] ( -- ) end of [IF] (immediate no-op)\" "
    .ascii ": [THEN] ; IMMEDIATE "
    .ascii "DOC\" [ELSE] ( -- ) skip to matching [THEN] (immediate)\" "
    .ascii ": [ELSE] 1 BEGIN BEGIN BL WORD COUNT DUP WHILE 2DUP S\" [IF]\" COMPARE 0= IF 2DROP 1+ ELSE 2DUP S\" [ELSE]\" COMPARE 0= IF 2DROP 1- DUP IF 1+ THEN ELSE 2DUP S\" [THEN]\" COMPARE 0= IF 2DROP 1- ELSE 2DROP THEN THEN THEN DUP 0= IF DROP EXIT THEN REPEAT 2DROP REFILL 0= UNTIL DROP ; IMMEDIATE "
    .ascii "DOC\" [IF] ( flag -- ) interpret if true else skip to [ELSE]/[THEN] (immediate)\" "
    .ascii ": [IF] 0= IF POSTPONE [ELSE] THEN ; IMMEDIATE "
    .ascii "DOC\" ENDCASE ( -- ) end CASE, resolve branches (immediate)\" "
    .ascii ": ENDCASE ?COMP POSTPONE DROP BEGIN DUP WHILE 1- >R POSTPONE THEN R> REPEAT DROP ; IMMEDIATE "

    // --- 5. Tools / extensions ---
    // WORDS is CODE (XWORDS). DOCOL? defined early after NAME>HELP (may redefine here).
    .ascii "DOC\" DOCOL? ( xt -- flag ) true if colon definition\" "
    .ascii ": DOCOL? @ DOCOL-ADDR = ; "
    // SEE: walk colon body; skip inline data after LIT, (S"), BRANCH, 0BRANCH,
    // (LOOP), and (+LOOP). Ordinary xts (including (DO), (DOES>), EXIT) are 1 cell.
    // ALIAS copies CODE field only — correct for CODE words (e.g. FLOAD/INCLUDE)
    .ascii "DOC\" ALIAS ( xt 'name' -- ) define name with same CODE field as xt\" "
    .ascii ": ALIAS CREATE LATEST @ SWAP @ SWAP ! ; "
    .ascii "DOC\" SYNONYM ( 'newname' 'oldname' -- ) newname behaves as oldname\" "
    .ascii ": SYNONYM >IN @ >R PARSE-NAME 2DROP ' R> >IN ! ALIAS ; "
    // SEE / HELP — one-line header, then body walk.
    // SEE helpers — keep forth_init free of embedded \" names like (S")
    .ascii "DOC\" (SEE-BR?) ( xt -- flag ) SEE helper: branch/loop xt?\" "
    .ascii ": (SEE-BR?) >R R@ BRANCH-ADDR = R@ 0BRANCH-ADDR = OR R@ ['] (LOOP) = OR R@ ['] (+LOOP) = OR R> DROP ; "
    .ascii "DOC\" (SEE-HDR) ( xt -- xt ) print C/colon tag, help or name, CR\" "
    .ascii ": (SEE-HDR) DUP DOCOL? IF 58 EMIT SPACE ELSE 67 EMIT 79 EMIT 68 EMIT 69 EMIT SPACE THEN DUP NAME>HELP DUP IF TYPE ELSE 2DROP DUP NAME>STRING TYPE THEN CR ; "
    .ascii "DOC\" (SEE-PRIM) ( xt -- ) print (primitive) for non-colon\" "
    .ascii ": (SEE-PRIM) DROP 40 EMIT 112 EMIT 114 EMIT 105 EMIT 109 EMIT 105 EMIT 116 EMIT 105 EMIT 118 EMIT 101 EMIT 41 EMIT CR ; "
    .ascii "DOC\" (SEE-STEP) ( addr -- addr' ) decompile one body cell; advances addr\" "
    .ascii ": (SEE-STEP) DUP @ >R R@ EXIT-ADDR = IF R> DROP DROP 59 EMIT CR 0 EXIT THEN R@ LIT-ADDR = IF R> DROP 8 + DUP @ . SPACE 8 + EXIT THEN R@ SLIT-ADDR = IF R> DROP 8 + DUP @ >R 8 + 83 EMIT 34 EMIT SPACE DUP R@ TYPE 34 EMIT SPACE R> + ALIGNED EXIT THEN R@ (SEE-BR?) IF R@ NAME>STRING TYPE SPACE R> DROP 8 + DUP @ . SPACE 8 + EXIT THEN R@ NAME>STRING TYPE SPACE R> DROP 8 + ; "
    .ascii "DOC\" SEE ( 'name' -- ) show help and decompile word\" "
    .ascii ": SEE ' DUP (SEE-HDR) DUP DOCOL? 0= IF (SEE-PRIM) EXIT THEN >BODY BEGIN (SEE-STEP) DUP 0= UNTIL DROP ; "
    .ascii "DOC\" HELP ( 'name' -- ) show help and decompile word (same as SEE)\" "
    .ascii ": HELP SEE ; "
    .ascii "' INCLUDE ALIAS FLOAD "
    // ANS: REQUIRE = PARSE-NAME REQUIRED  (REQUIRED is CODE; load-once registry)
    .ascii "DOC\" REQUIRE ( 'name' -- ) load file once (PARSE-NAME REQUIRED)\" "
    .ascii ": REQUIRE PARSE-NAME REQUIRED ; "

    // .FREE ( -- )  print free user-dictionary bytes (UNUSED is the cell value)
    .ascii "DOC\" .FREE ( -- ) print free dictionary bytes remaining (unsigned, like UNUSED U.)\" "
    .ascii ": .FREE UNUSED U. SPACE S\" bytes free\" TYPE CR ; "
    // Digit helpers for .ELAPSED (zero-padded; BASE forced to DECIMAL)
    .ascii "DOC\" .2DIG ( n -- ) print n as 2 decimal digits\" "
    .ascii ": .2DIG 10 /MOD 48 + EMIT 48 + EMIT ; "
    .ascii "DOC\" .3DIG ( n -- ) print n as 3 decimal digits\" "
    .ascii ": .3DIG 100 /MOD 48 + EMIT .2DIG ; "
    // .ELAPSED ( ms -- )  print milliseconds as HH:MM:SS.mmm (HH at least 2 digits)
    // Hours use ANS double pictured (`n 0 <# #S #>`): #/#S/#> are double-cell.
    .ascii "DOC\" .ELAPSED ( ms -- ) print ms as HH:MM:SS.mmm\" "
    .ascii ": .ELAPSED BASE @ >R DECIMAL 1000 /MOD SWAP >R 60 /MOD SWAP >R 60 /MOD SWAP >R DUP 10 < IF 48 EMIT THEN 0 <# #S #> TYPE 58 EMIT R> .2DIG 58 EMIT R> .2DIG 46 EMIT R> .3DIG R> BASE ! ; "
    // ELAPSED <name>  run name once; print wall time as HH:MM:SS.mmm
    // Start time on R so EXECUTE stack results do not interfere with MS@ / delta.
    .ascii "DOC\" ELAPSED ( 'name' -- ) run name once and print elapsed time\" "
    .ascii ": ELAPSED ' MS@ >R EXECUTE MS@ R> - .ELAPSED CR ; "
    // DUMP ( addr u -- )  classic hex+ASCII dump, 16 bytes/line
    // .H2 byte as 2 hex digits; .HA address as 16 hex digits (BASE=HEX)
    // Single-cell values need hi=0 for double-cell # (same as BI. / D.).
    .ascii "DOC\" .H2 ( b -- ) print byte as 2 hex digits\" "
    .ascii ": .H2 255 AND 0 <# # # #> TYPE ; "
    .ascii "DOC\" .HA ( addr -- ) print address as 16 hex digits\" "
    .ascii ": .HA 0 <# # # # # # # # # # # # # # # # # #> TYPE ; "
    .ascii "DOC\" DUMP-END ( -- addr ) variable end of DUMP range\" "
    .ascii "VARIABLE DUMP-END "
    .ascii "DOC\" DUMP-LINE ( addr -- addr' ) dump one line\" "
    .ascii ": DUMP-LINE DUP .HA SPACE SPACE DUP 16 0 DO DUP I + DUMP-END @ U< IF DUP I + C@ .H2 SPACE ELSE SPACE SPACE SPACE THEN LOOP SPACE SPACE 16 0 DO DUP I + DUMP-END @ U< IF DUP I + C@ DUP BL 127 WITHIN 0= IF DROP BL THEN EMIT ELSE BL EMIT THEN LOOP DROP 16 + ; "
    .ascii "DOC\" DUMP ( addr u -- ) hex dump u bytes from addr (16 per line, ASCII gutter)\" "
    .ascii ": DUMP BASE @ >R HEX OVER + DUMP-END ! BEGIN DUP DUMP-END @ U< WHILE CR DUMP-LINE REPEAT DROP CR R> BASE ! ; "
    // DEPTH — high-level so SEE shows TOS-cached layout (stack grows down)
    .ascii "DOC\" DEPTH ( -- n ) data stack depth in cells\" "
    .ascii ": DEPTH SP@ SP0 SWAP - CELL / ; "
    // */MOD */  — double intermediate via M* then symmetric divide (matches ARM /)
    .ascii "DOC\" */MOD ( n1 n2 n3 -- rem quot ) multiply then divmod\" "
    .ascii ": */MOD >R M* R> SM/REM ; "
    .ascii "DOC\" */ ( n1 n2 n3 -- n4 ) multiply to double-cell, divide (quotient)\" "
    .ascii ": */ */MOD SWAP DROP ; "
    // ABORT / ABORT" — high-level; QUIT is pure CODE (XQUIT -> _do_quit).
    // ABORT: SP0 SP! clears data stack (TOS-cache model), then QUIT.
    .ascii "DOC\" ABORT ( -- ) THROW -1 (catchable; prints Aborted! if uncaught)\" "
    .ascii ": ABORT SP0 SP! QUIT ; "
    // ANS ABORT" ( x -- ): if x nonzero, type ccc and abort; else discard x.
    // Old body compiled S" TYPE ABORT with no IF — always aborted (bubble-sort
    // verify-list failed even when the list was correctly sorted).
    // Note: do not put ABORT" inside DOC" — the embedded quote truncates DOC".
    .ascii "DOC\" ABORT quote ( x -- ) if x nonzero type message and ABORT (immediate)\" "
    .ascii ": ABORT\" STATE @ IF POSTPONE IF POSTPONE S\" POSTPONE TYPE POSTPONE CR POSTPONE ABORT POSTPONE THEN ELSE 34 PARSE ROT IF TYPE CR ABORT THEN 2DROP THEN ; IMMEDIATE "
    // FORGET is CODE (XFORGET): multi-wordlist prune + USER-DICT fence.
    // ANEW — classic reload marker (formerly AutoLoad/ANEW.fth; single definition).
    // If name exists: FORGET it (and all newer words), then CREATE the marker again.
    .ascii "DOC\" ANEW ( 'name' -- ) FORGET name if present, then CREATE reload marker\" "
    .ascii ": ANEW >IN @ >R BL WORD FIND IF DROP R@ >IN ! S\" Reloading module: \" TYPE BL WORD COUNT TYPE CR R@ >IN ! FORGET ELSE DROP R@ >IN ! S\" Loading module: \" TYPE BL WORD COUNT TYPE CR THEN R> >IN ! CREATE ; "
    // ON / OFF — store 1 or 0 at addr (classic: FILE-ECHO ON  /  FILE-ECHO OFF)
    .ascii "DOC\" ON ( addr -- ) store 1 at addr (e.g. file-echo ON)\" "
    .ascii ": ON 1 SWAP ! ; "
    .ascii "DOC\" OFF ( addr -- ) store 0 at addr (e.g. file-echo OFF)\" "
    .ascii ": OFF 0 SWAP ! ; "

    // --- 6. Core Ext (high-level; U> 0<> 0> WITHIN / 2>R family are CODE) ---
    // U.R ( u n -- ) right-justify u in a field of n characters (no trailing space)
    .ascii "DOC\" U.R ( u n -- ) print u right-justified in n field\" "
    .ascii ": U.R >R 0 <# #S #> R> OVER - 0 MAX SPACES TYPE ; "
    .ascii "DOC\" .R ( n n -- ) print n right-justified in field (no trailing space)\" "
    .ascii ": .R >R DUP ABS 0 <# #S ROT SIGN #> R> OVER - 0 MAX SPACES TYPE ; "
    .ascii "DOC\" HOLDS ( c-addr u -- ) add string to pictured numeric output (prepend via HOLD)\" "
    .ascii ": HOLDS BEGIN DUP WHILE 1- 2DUP + C@ HOLD REPEAT 2DROP ; "
    .ascii "DOC\" COMPILE, ( xt -- ) compile the execution token xt\" "
    .ascii ": COMPILE, , ; "
    .ascii "DOC\" [COMPILE] ( 'name' -- ) force-compile name even if immediate (immediate)\" "
    .ascii ": [COMPILE] ?COMP BL WORD FIND 0= IF DROP EXIT THEN DROP , ; IMMEDIATE "
    // .( is CODE immediate (XDOTPAREN) — do not redefine here
    .ascii "DOC\" BUFFER: ( u 'name' -- ) create a buffer of u bytes\" "
    .ascii ": BUFFER: CREATE ALLOT ; "
    .ascii "DOC\" VALUE ( x 'name' -- ) create a value; change with TO\" "
    .ascii ": VALUE CREATE , DOES> @ ; "
    .ascii "DOC\" DEFER ( 'name' -- ) create a deferred word (set with IS)\" "
    .ascii ": DEFER CREATE ['] ABORT , DOES> @ EXECUTE ; "
    .ascii "DOC\" DEFER@ ( xt1 -- xt2 ) get the xt that defer xt1 currently executes\" "
    .ascii ": DEFER@ >BODY CELL+ @ ; "
    .ascii "DOC\" DEFER! ( xt1 xt2 -- ) set defer xt2 to execute xt1\" "
    .ascii ": DEFER! >BODY CELL+ ! ; "
    .ascii "DOC\" IS ( xt 'name' -- ) set DEFER named (immediate)\" "
    .ascii ": IS STATE @ IF POSTPONE ['] POSTPONE DEFER! ELSE ' DEFER! THEN ; IMMEDIATE "
    .ascii "DOC\" ACTION-OF ( 'name' -- xt ) xt currently in deferred name (immediate)\" "
    .ascii ": ACTION-OF STATE @ IF POSTPONE ['] POSTPONE DEFER@ ELSE ' DEFER@ THEN ; IMMEDIATE "
    // MARKER — body: HERE-at-define, LATEST-before-define
    .ascii "DOC\" MARKER ( 'name' -- ) create a dictionary restore point\" "
    .ascii ": MARKER LATEST @ HERE CREATE , , DOES> DUP @ DP ! CELL+ @ LATEST ! ; "

    // --- 7. Double-Number high-level ---
    .ascii "DOC\" 2CONSTANT ( x1 x2 'name' -- ) create double constant\" "
    .ascii ": 2CONSTANT CREATE SWAP , , DOES> 2@ ; "
    .ascii "DOC\" 2VARIABLE ( 'name' -- ) create double variable\" "
    .ascii ": 2VARIABLE CREATE 0 , 0 , ; "
    .ascii "DOC\" 2VALUE ( x1 x2 'name' -- ) double value; change with TO\" "
    .ascii ": 2VALUE CREATE SWAP , , DOES> 2@ ; "
    .ascii "DOC\" 2LITERAL ( x1 x2 -- ) compile double literal (immediate)\" "
    .ascii ": 2LITERAL ?COMP SWAP POSTPONE LITERAL POSTPONE LITERAL ; IMMEDIATE "
    .ascii "DOC\" D. ( d -- ) print signed double with space\" "
    .ascii ": D. 2DUP D0< IF DNEGATE -1 ELSE 0 THEN >R <# #S R> SIGN #> TYPE SPACE ; "
    .ascii "DOC\" D.R ( d n -- ) print signed double right-justified\" "
    .ascii ": D.R >R 2DUP D0< IF DNEGATE -1 ELSE 0 THEN >R <# #S R> SIGN #> R> OVER - 0 MAX SPACES TYPE ; "
    // M*/ — full multiprecision later; D>S path covers Hayes cases where d1 fits single
    .ascii "DOC\" M*/ ( d1 n1 +n2 -- d2 ) multiply double by n1 then divide by n2\" "
    .ascii ": M*/ >R >R D>S R> R> */ S>D ; "

    // --- 8. String word set ---
    .ascii "DOC\" BLANK ( c-addr u -- ) fill with spaces\" "
    .ascii ": BLANK BL FILL ; "
    .ascii "DOC\" -TRAILING ( c-addr u1 -- c-addr u2 ) remove trailing spaces\" "
    .ascii ": -TRAILING BEGIN DUP WHILE 1- 2DUP + C@ BL <> IF 1+ EXIT THEN REPEAT ; "
    // COMPARE / SEARCH are CODE primitives
    .ascii "DOC\" SLITERAL ( c-addr u -- ) compile string literal (immediate)\" "
    .ascii ": SLITERAL ?COMP SLIT-ADDR , DUP C, BEGIN DUP WHILE OVER C@ C, 1 /STRING REPEAT 2DROP ALIGN ; IMMEDIATE "

    // --- 9. Facility (MS/KEY? are CODE; EKEY family thin wrappers) ---
    .ascii "DOC\" EKEY? ( -- flag ) same as KEY? when no extended keys\" "
    .ascii ": EKEY? KEY? ; "
    .ascii "DOC\" EKEY ( -- u ) wait for key; same as KEY for ASCII\" "
    .ascii ": EKEY KEY ; "
    .ascii "DOC\" EKEY>CHAR ( u -- u false | char true )\" "
    .ascii ": EKEY>CHAR DUP 0 256 WITHIN IF TRUE ELSE FALSE THEN ; "
    .ascii "DOC\" EMIT? ( -- flag ) always true (console always ready)\" "
    .ascii ": EMIT? TRUE ; "
    .ascii "DOC\" PAGE ( -- ) clear screen (emit form-feed / ANSI home+clear)\" "
    .ascii ": PAGE 12 EMIT 27 EMIT 91 EMIT 72 EMIT 27 EMIT 91 EMIT 50 EMIT 74 EMIT ; "
    .ascii "DOC\" AT-XY ( u1 u2 -- ) set cursor column u1 row u2 (ANSI 1-based)\" "
    .ascii ": AT-XY 1+ SWAP 1+ SWAP 27 EMIT 91 EMIT 0 U.R 59 EMIT 0 U.R 72 EMIT ; "
    // TIME&DATE needs host; stub returns 0s until host hook
    .ascii "DOC\" WARNING ( -- addr ) variable; used by some test suites\" "
    .ascii "VARIABLE WARNING "

    // --- 10. Block word set (file-backed via BLOCK-FILE + File-Access) ---
    // BLK SCR BLOCK-FILE (BLOCK-BUF) (BLOCK-NR) (BLOCK-UPD) are CODE (BSS).
    .ascii "DOC\" (BLOCK-SEEK) ( u -- ior ) seek BLOCK-FILE to start of block u\" "
    .ascii ": (BLOCK-SEEK) 1024 UM* BLOCK-FILE @ REPOSITION-FILE ; "
    .ascii "DOC\" (BLOCK-WRITE) ( u -- ior ) write block buffer to mass storage block u\" "
    .ascii ": (BLOCK-WRITE) BLOCK-FILE @ 0= IF DROP 0 EXIT THEN DUP (BLOCK-SEEK) ?DUP IF NIP EXIT THEN DROP (BLOCK-BUF) 1024 BLOCK-FILE @ WRITE-FILE ; "
    .ascii "DOC\" (BLOCK-READ) ( u -- ior ) read mass storage block u into block buffer\" "
    .ascii ": (BLOCK-READ) BLOCK-FILE @ 0= IF DROP (BLOCK-BUF) 1024 BL FILL 0 EXIT THEN DUP (BLOCK-SEEK) ?DUP IF NIP EXIT THEN DROP (BLOCK-BUF) 1024 BLOCK-FILE @ READ-FILE NIP ; "
    .ascii "DOC\" UPDATE ( -- ) mark current block buffer dirty\" "
    .ascii ": UPDATE -1 (BLOCK-UPD) ! ; "
    .ascii "DOC\" SAVE-BUFFERS ( -- ) write dirty buffers; keep assignment\" "
    .ascii ": SAVE-BUFFERS (BLOCK-UPD) @ IF (BLOCK-NR) @ DUP 0< 0= IF (BLOCK-WRITE) DROP THEN 0 (BLOCK-UPD) ! THEN BLOCK-FILE @ IF BLOCK-FILE @ FLUSH-FILE DROP THEN ; "
    .ascii "DOC\" EMPTY-BUFFERS ( -- ) unassign buffers; discard dirty without writing\" "
    .ascii ": EMPTY-BUFFERS 0 (BLOCK-UPD) ! -1 (BLOCK-NR) ! ; "
    .ascii "DOC\" FLUSH ( -- ) SAVE-BUFFERS then EMPTY-BUFFERS\" "
    .ascii ": FLUSH SAVE-BUFFERS EMPTY-BUFFERS ; "
    .ascii "DOC\" BLOCK ( u -- a-addr ) a-addr is the address of the block buffer for block u\" "
    .ascii ": BLOCK DUP (BLOCK-NR) @ = IF DROP (BLOCK-BUF) EXIT THEN (BLOCK-UPD) @ IF (BLOCK-NR) @ DUP 0< 0= IF (BLOCK-WRITE) DROP THEN 0 (BLOCK-UPD) ! THEN DUP (BLOCK-NR) ! DUP (BLOCK-READ) DROP DROP (BLOCK-BUF) ; "
    .ascii "DOC\" BUFFER ( u -- a-addr ) like BLOCK; contents may be unspecified\" "
    .ascii ": BUFFER BLOCK ; "
    .ascii "DOC\" OPEN-BLOCK-FILE ( c-addr u -- fileid ior ) open existing .blk volume R/W\" "
    .ascii ": OPEN-BLOCK-FILE R/W BIN OPEN-FILE ; "
    .ascii "DOC\" CREATE-BLOCK-FILE ( c-addr u n -- fileid ior ) create .blk with n blank blocks\" "
    .ascii ": CREATE-BLOCK-FILE >R R/W BIN CREATE-FILE DUP IF R> DROP EXIT THEN DROP R> 0 ?DO >R (BLOCK-BUF) 1024 BL FILL (BLOCK-BUF) 1024 R@ WRITE-FILE DROP R> LOOP >R 0 0 R@ REPOSITION-FILE DROP R> 0 ; "
    .ascii "DOC\" USE-BLOCK-FILE ( fileid -- ) select volume as current; flush previous\" "
    .ascii ": USE-BLOCK-FILE FLUSH BLOCK-FILE ! ; "
    .ascii "DOC\" CLOSE-BLOCK-FILE ( fileid -- ior ) flush if current, then CLOSE-FILE\" "
    .ascii ": CLOSE-BLOCK-FILE DUP BLOCK-FILE @ = IF FLUSH 0 BLOCK-FILE ! THEN CLOSE-FILE ; "
    .ascii "DOC\" LOAD ( i*x u -- j*x ) interpret block u\" "
    .ascii ": LOAD BLK @ >R DUP BLK ! BLOCK 1024 EVALUATE R> BLK ! ; "
    .ascii "DOC\" THRU ( i*x u1 u2 -- j*x ) LOAD u1..u2 inclusive\" "
    .ascii ": THRU 1+ SWAP ?DO I LOAD LOOP ; "
    .ascii "DOC\" LIST ( u -- ) display block u as 16 lines of 64 chars\" "
    .ascii ": LIST DUP SCR ! BLOCK 16 0 DO CR I 3 .R SPACE DUP 64 TYPE 64 + LOOP DROP CR ; "

    // Default MAIN if AutoLoad does not define one (kernel_eval \"MAIN\" at startup)
    .ascii "DOC\" MAIN ( -- ) default app entry; AutoLoad may redefine\" "
    .ascii ": MAIN ; "

    .byte 0  // null terminator

// REPL trampoline: restart_cell holds address of restart_cfa; that cell is XRESTART.
.align 8
restart_cfa:    .quad 0            // filled at boot: address of XRESTART code
restart_cell:   .quad 0            // filled at boot: -> restart_cfa
next_diag:      .skip 32
catch_ok_cell:  .quad 0

// Cached CFAs for assembler (filled by _boot_cache_cfa)
.align 8
cfa_lit:        .quad 0
cfa_exit:       .quad 0
cfa_slit:       .quad 0
cfa_cstr:       .quad 0
cfa_type:       .quad 0
cfa_branch:     .quad 0
cfa_0branch:    .quad 0
cfa_does_rt:    .quad 0
cfa_catch_ok:   .quad 0
cfa_local_init: .quad 0
cfa_local_at:   .quad 0
cfa_local_store: .quad 0

// Pending help for next : / CREATE / :NONAME (SETDOC / DOC")
pending_help_addr: .quad 0
pending_help_len:  .quad 0

// Locals compile-time + runtime
local_name_count:   .quad 0
local_init_count:   .quad 0
local_init_reverse: .quad 0
local_brace_phase:  .quad 0        // {: parse phase (not in VM regs — x19 is IP!)
local_names:        .skip LOCAL_MAX * LOCAL_NAME_STR
local_frame_depth:  .quad 0
local_frame_rsp:    .skip LOCAL_FRAME_MAX * 8
local_frame_n:      .skip LOCAL_FRAME_MAX * 8
local_frames:       .skip LOCAL_FRAME_MAX * LOCAL_MAX * 8
str_store_name:     .asciz "!"

// Boot catalog (structured records + name strings)
.include "boot_words.inc"

// ============================================================================
// User dictionary space (grows upward)
// Physical reserve: USER_DICT_MAX (64 MiB BSS, demand-zero — not all resident).
// Logical size: user_dict_size_cell (default 1 MiB; GROWMEMORYMB raises it).
// Base never moves so dictionary CFAs stay valid across grow.
// ============================================================================
.align 8
user_dict_size_cell:
    .quad USER_DICT_DEFAULT
grow_memory_used:
    .quad 0                        // GROWMEMORYMB once per process
user_dict_area:
    .skip USER_DICT_MAX

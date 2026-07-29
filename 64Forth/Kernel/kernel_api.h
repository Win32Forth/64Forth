//
//  kernel_api.h
//  64Forth
//
//  Public domain.
//
//  C ABI for the PickleForth ARM64 kernel embedded in the Swift host.
//

#ifndef SIXTYFOURFORTH_KERNEL_API_H
#define SIXTYFOURFORTH_KERNEL_API_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int kernel_init(void);
int kernel_eval(const char *line, size_t n);

void kernel_set_emit(void (*fn)(int c));
void kernel_set_key(int (*fn)(void));

/// KEY? — non-blocking: return non-zero if a key is available (does not consume it).
void kernel_set_key_q(int (*fn)(void));

/// TIME&DATE — fill out[6] with sec, min, hour, day, month, year (local time).
void kernel_set_time_date(void (*fn)(int64_t out[6]));

/// File-Access multiplexor. op codes in forth.s; returns ior (0 = ok).
/// ptr is optional c-addr / buffer; o1/o2/o3 optional results.
typedef long long (*kernel_file_op_fn)(long long op, long long a, long long b, long long c, long long d,
                                       void *ptr, long long *o1, long long *o2, long long *o3);
void kernel_set_file_op(kernel_file_op_fn fn);

/// FROMLIB / FROM-LIBRARY — host arms Library resolve for next load/CHDIR.
void kernel_set_fromlib(void (*fn)(void));

/// Disarm FROMLIB (e.g. REQUIRE skipped because file already loaded).
void kernel_set_fromlib_clear(void (*fn)(void));

/// Called when a file INCLUDE/FLOAD SOURCE ends (SOURCE-ID was > 0) so the host
/// can restore the previous load cwd (nested relative path resolution).
void kernel_set_end_include(void (*fn)(void));

/// INCLUDE / FLOAD / REQUIRE.
/// path_len == 0 → bare (host open panel). On success set *out_ptr / *out_len
/// (buffer valid until host frees after kernel_eval). Return 0 ok, -1 fail/cancel.
typedef int (*kernel_load_file_fn)(const char *path, size_t path_len,
                                   const char **out_ptr, size_t *out_len);
void kernel_set_load_file(kernel_load_file_fn fn);

/// Resolve load name → absolute registry key (consumes FROMLIB). Return 0 ok, -1 fail.
/// Writes UTF-8 path (no trailing NUL required; *out_len set).
typedef int (*kernel_resolve_key_fn)(const char *path, size_t path_len,
                                     char *out, size_t out_max, size_t *out_len);
void kernel_set_resolve_key(kernel_resolve_key_fn fn);

/// Absolute path of last successful load_file (REQUIRE registry). Return 0 ok, -1 none.
typedef int (*kernel_last_load_key_fn)(char *out, size_t out_max, size_t *out_len);
void kernel_set_last_load_key(kernel_last_load_key_fn fn);

/// CHDIR — path_len == 0 → bare folder picker.
void kernel_set_chdir(void (*fn)(const char *path, size_t n));

/// PWD — print logical cwd.
void kernel_set_pwd(void (*fn)(void));

/// DIR — path_len == 0 → list cwd (or Library if FROMLIB armed).
void kernel_set_dir(void (*fn)(const char *path, size_t n));

/// EDIT — path_len == 0 → open panel; else open named file in system editor + cwd.
/// Honors FROMLIB (Library resolve; does not permanently chdir into Library).
void kernel_set_edit(void (*fn)(const char *path, size_t n));

/// \S / \s on the console SOURCE (SOURCE-ID 0): sticky flag for multi-line paste stop.
/// Returns 1 if set since last call, else 0; always clears the flag (TZForth-style).
int kernel_take_repl_batch_stop(void);

/// Memory-fault recovery (SIGSEGV / SIGBUS). Kernel installs handlers at init;
/// host may reinstall. longjmps to the active kernel_eval / QUIT setjmp.
void kernel_on_memory_fault(int sig);

/// 1 if a memory fault was recovered since last take (sticky; cleared on read).
int kernel_take_fault_flag(void);

void kernel_cold_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SIXTYFOURFORTH_KERNEL_API_H */

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

/// FROMLIB / FROM-LIBRARY — host arms Library resolve for next load/CHDIR.
void kernel_set_fromlib(void (*fn)(void));

/// Disarm FROMLIB (e.g. REQUIRE skipped because file already loaded).
void kernel_set_fromlib_clear(void (*fn)(void));

/// INCLUDE / FLOAD / REQUIRE.
/// path_len == 0 → bare (host open panel). On success set *out_ptr / *out_len
/// (buffer valid until host frees after kernel_eval). Return 0 ok, -1 fail/cancel.
typedef int (*kernel_load_file_fn)(const char *path, size_t path_len,
                                   const char **out_ptr, size_t *out_len);
void kernel_set_load_file(kernel_load_file_fn fn);

/// CHDIR — path_len == 0 → bare folder picker.
void kernel_set_chdir(void (*fn)(const char *path, size_t n));

/// PWD — print logical cwd.
void kernel_set_pwd(void (*fn)(void));

/// DIR — path_len == 0 → list cwd (or Library if FROMLIB armed).
void kernel_set_dir(void (*fn)(const char *path, size_t n));

void kernel_cold_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SIXTYFOURFORTH_KERNEL_API_H */

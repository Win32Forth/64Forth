/* emit-run.m — load 64EMIT02, bind host_app_* slots, run ITC entry.
 * Public domain.
 *
 *   cc -arch arm64 -O2 -fobjc-arc -framework AppKit \
 *      -o emit-run emit-run.m
 *   ./emit-run /path/to/app.img
 *   EMIT_HEADLESS=1 ./emit-run app.img   # open returns -1
 *   Inside a .app: no args → Contents/Resources/app.img
 */
#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <limits.h>
#include <sys/mman.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#include <mach-o/dyld.h>
#endif

#include "emit-host.inc"

static uint8_t *g_code;
static uint64_t g_code_len;

/* Bundle layout: MacOS/<bin> → ../Resources/app.img. Also try cwd app.img. */
static int resolve_default_img(char *out, size_t out_sz) {
  char exe[PATH_MAX];
  uint32_t n = (uint32_t)sizeof(exe);
  if (_NSGetExecutablePath(exe, &n) != 0)
    return -1;
  char resolved[PATH_MAX];
  if (!realpath(exe, resolved))
    strncpy(resolved, exe, sizeof(resolved) - 1);
  /* strip MacOS/<bin> → Contents */
  char *slash = strrchr(resolved, '/');
  if (!slash)
    return -1;
  *slash = '\0';
  slash = strrchr(resolved, '/');
  if (!slash)
    return -1;
  *slash = '\0'; /* Contents */
  if ((size_t)snprintf(out, out_sz, "%s/Resources/app.img", resolved) >= out_sz)
    return -1;
  if (access(out, R_OK) == 0)
    return 0;
  if (access("app.img", R_OK) == 0) {
    strncpy(out, "app.img", out_sz - 1);
    out[out_sz - 1] = '\0';
    return 0;
  }
  return -1;
}

static void on_sig(int sig, siginfo_t *si, void *ucontext) {
  (void)sig;
  uint64_t pc = 0;
#if defined(__APPLE__) && defined(__arm64__)
  ucontext_t *uc = (ucontext_t *)ucontext;
  pc = (uint64_t)uc->uc_mcontext->__ss.__pc;
  fprintf(stderr, "emit-run: signal at pc=%llx addr=%p\n",
          (unsigned long long)pc, si ? si->si_addr : NULL);
  fprintf(stderr, "  x19=%llx x20=%llx x21=%llx x22=%llx x23=%llx x1=%llx\n",
          (unsigned long long)uc->uc_mcontext->__ss.__x[19],
          (unsigned long long)uc->uc_mcontext->__ss.__x[20],
          (unsigned long long)uc->uc_mcontext->__ss.__x[21],
          (unsigned long long)uc->uc_mcontext->__ss.__x[22],
          (unsigned long long)uc->uc_mcontext->__ss.__x[23],
          (unsigned long long)uc->uc_mcontext->__ss.__x[1]);
  if (g_code && pc >= (uint64_t)(uintptr_t)g_code &&
      pc < (uint64_t)(uintptr_t)g_code + g_code_len)
    fprintf(stderr, "  pc off in code = %llx\n",
            (unsigned long long)(pc - (uint64_t)(uintptr_t)g_code));
  else
    fprintf(stderr, "  pc NOT in code buf (%p len %llu)\n",
            (void *)g_code, (unsigned long long)g_code_len);
#endif
  _Exit(139);
}

#define EMIT_PAGE        0x4000u
#define EMIT_STACK_BYTES 0x100000u
#define EMIT_RP_BYTES    0x8000u
#define EMIT_HDR         64u

static void die(const char *msg) {
  fprintf(stderr, "emit-run: %s\n", msg);
  exit(1);
}

static uint64_t rd_u64(const uint8_t *p) {
  uint64_t v;
  memcpy(&v, p, 8);
  return v;
}

static uint32_t rd_u32(const uint8_t *p) {
  uint32_t v;
  memcpy(&v, p, 4);
  return v;
}

static void rebase_cell(uint8_t *cell, uint64_t code_base, uint64_t code_len,
                        uint64_t data_base, uint64_t data_len,
                        uint8_t *code, uint8_t *data) {
  uint64_t v = rd_u64(cell);
  if (v >= code_base && v < code_base + code_len) {
    uint64_t nv = v - code_base + (uint64_t)(uintptr_t)code;
    memcpy(cell, &nv, 8);
  } else if (data_len && v >= data_base && v < data_base + data_len) {
    uint64_t nv = v - data_base + (uint64_t)(uintptr_t)data;
    memcpy(cell, &nv, 8);
  }
}

/*
 * ITC trampoline (mirrors Emitter run.fth RUN-EMIT-CFA).
 * Gadgets (8-aligned):
 *   retc: LDR X30,[X23],#8 ; RET
 *   cfar: .quad retc
 *   body: .quad cfar     ← RPUSH this as return IP
 */
static void __attribute__((noinline)) run_itc(void *cfa, void *dsp, void *rp) {
  uint8_t *g = (uint8_t *)mmap(NULL, EMIT_PAGE, PROT_READ | PROT_WRITE,
                               MAP_ANON | MAP_PRIVATE, -1, 0);
  if (g == MAP_FAILED) die("gadget mmap");
  /* retc at g+0 */
  uint32_t *ins = (uint32_t *)g;
  ins[0] = 0xF84086FE; /* LDR X30, [X23], #8 */
  ins[1] = 0xD65F03C0; /* RET */
  uint64_t retc = (uint64_t)(uintptr_t)g;
  uint64_t *cfar = (uint64_t *)(g + 16);
  uint64_t *body = (uint64_t *)(g + 24);
  *cfar = retc;
  *body = (uint64_t)(uintptr_t)cfar;
  if (mprotect(g, EMIT_PAGE, PROT_READ | PROT_EXEC) != 0) die("gadget mprotect");
#if defined(__APPLE__)
  sys_icache_invalidate(g, 32);
#endif

  /*
   * Gadget RET restores X30 and RETs. X30 must be the address after this
   * asm (so run_itc's epilogue runs). Caller LR would skip the epilogue and
   * corrupt the C stack — unlike in-process RUN-EMIT where the trampoline
   * is the whole callee.
   */
  __asm__ volatile(
    "mov x19, %0\n\t"
    "mov x22, x19\n\t"
    "movz x28, #0\n\t"
    "movz x20, #0\n\t"
    "mov x23, %1\n\t"
    "mov x21, %2\n\t"
    "adr x30, 1f\n\t"
    "str x30, [x23, #-8]!\n\t"
    "mov x0, %3\n\t"
    "str x0, [x23, #-8]!\n\t"
    "add x19, x21, #8\n\t"
    "ldr x21, [x19], #8\n\t"
    "ldr x1, [x21]\n\t"
    "br x1\n\t"
    "1:\n\t"
    :
    : "r"(dsp), "r"(rp), "r"(cfa), "r"(body)
    : "x0", "x1", "x2", "x3", "x16", "x17",
      "x19", "x20", "x21", "x22", "x23", "x28", "x30", "memory"
  );
}

int main(int argc, char **argv) {
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = on_sig;
  sa.sa_flags = SA_SIGINFO;
  sigaction(SIGSEGV, &sa, NULL);
  sigaction(SIGBUS, &sa, NULL);

  const char *path = NULL;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--headless") == 0 || strcmp(argv[i], "--agent") == 0)
      emit_headless = 1;
    else if (argv[i][0] != '-')
      path = argv[i];
  }
  if (getenv("EMIT_HEADLESS") && getenv("EMIT_HEADLESS")[0] == '1')
    emit_headless = 1;
  char img_buf[PATH_MAX];
  if (!path) {
    if (resolve_default_img(img_buf, sizeof(img_buf)) != 0) {
      fprintf(stderr, "usage: %s [--headless] image.img\n", argv[0]);
      fprintf(stderr, "  (or place app.img in Contents/Resources/ for .app)\n");
      return 2;
    }
    path = img_buf;
  }

  FILE *f = fopen(path, "rb");
  if (!f) die("open image");
  if (fseek(f, 0, SEEK_END) != 0) die("seek");
  long flen = ftell(f);
  if (flen < (long)EMIT_HDR) die("image too small");
  rewind(f);
  uint8_t *file = (uint8_t *)malloc((size_t)flen);
  if (!file || fread(file, 1, (size_t)flen, f) != (size_t)flen) die("read");
  fclose(f);

  if (memcmp(file, "64EMIT02", 8) != 0) die("bad magic");
  uint64_t flags     = rd_u64(file + 8);
  uint64_t code_len  = rd_u64(file + 16);
  uint64_t data_len  = rd_u64(file + 24);
  uint64_t entry_off = rd_u64(file + 32);
  uint64_t reloc_n   = rd_u64(file + 40);
  uint64_t code_base = rd_u64(file + 48);
  uint64_t data_base = rd_u64(file + 56);
  (void)flags;

  const uint8_t *rel = file + EMIT_HDR + code_len + data_len;
  uint64_t host_bytes = reloc_n * 8;
  if ((uint64_t)flen < EMIT_HDR + code_len + data_len + host_bytes + 8)
    die("truncated image");
  uint64_t ptr_n = rd_u64(rel + host_bytes);
  uint64_t need = EMIT_HDR + code_len + data_len + host_bytes + 8 + ptr_n * 8;
  if ((uint64_t)flen < need) die("truncated image (ptr)");

  uint32_t code_bytes = (uint32_t)((code_len + EMIT_PAGE - 1) & ~(uint64_t)(EMIT_PAGE - 1));
  uint32_t data_bytes = (uint32_t)((data_len + EMIT_PAGE - 1) & ~(uint64_t)(EMIT_PAGE - 1));
  if (data_bytes < EMIT_PAGE) data_bytes = EMIT_PAGE;
  uint32_t total = code_bytes + data_bytes + EMIT_STACK_BYTES;

  uint8_t *buf = (uint8_t *)mmap(NULL, total, PROT_READ | PROT_WRITE,
                                 MAP_ANON | MAP_PRIVATE, -1, 0);
  if (buf == MAP_FAILED) die("mmap");
  memcpy(buf, file + EMIT_HDR, (size_t)code_len);
  g_code = buf;
  g_code_len = code_len;
  uint8_t *data = buf + code_bytes;
  if (data_len)
    memcpy(data, file + EMIT_HDR + code_len, (size_t)data_len);

  /* Explicit pointer cells only (ARM prim bodies stay untouched). */
  const uint8_t *ptrs = rel + host_bytes + 8;
  for (uint64_t i = 0; i < ptr_n; i++) {
    uint32_t off = rd_u32(ptrs + i * 8);
    uint32_t spc = rd_u32(ptrs + i * 8 + 4);
    uint8_t *cell = spc ? (data + off) : (buf + off);
    if (spc) {
      if (off + 8 > data_len) die("ptr data off");
    } else {
      if (off + 8 > code_len) die("ptr code off");
    }
    rebase_cell(cell, code_base, code_len, data_base, data_len, buf, data);
  }

  /* Host-call fixups: .quad MAGIC|slot → host_fn[slot] */
  for (uint64_t i = 0; i < reloc_n; i++) {
    uint32_t off = rd_u32(rel + i * 8);
    uint32_t slot = rd_u32(rel + i * 8 + 4);
    if (off + 8 > code_len) die("reloc off");
    if (slot >= 10 || !host_fn[slot]) die("reloc slot");
    uint64_t fn = (uint64_t)(uintptr_t)host_fn[slot];
    memcpy(buf + off, &fn, 8);
  }
  if (mprotect(buf, code_bytes, PROT_READ | PROT_EXEC) != 0) die("mprotect");
#if defined(__APPLE__)
  sys_icache_invalidate(buf, code_bytes);
#endif

  void *dsp = buf + total - 64;
  void *rp  = (uint8_t *)dsp - EMIT_RP_BYTES;
  void *cfa = buf + entry_off;

  if (getenv("EMIT_DEBUG")) {
    uint64_t *c = (uint64_t *)cfa;
    fprintf(stderr, "emit-run: buf=%p data=%p cfa=%p entry=%llu\n",
            (void *)buf, (void *)data, cfa, (unsigned long long)entry_off);
    fprintf(stderr, "  CFA[0]=%llx CFA[1]=%llx CFA[2]=%llx\n",
            (unsigned long long)c[0], (unsigned long long)c[1],
            (unsigned long long)c[2]);
    fprintf(stderr, "  [CFA[0]] code word=%x\n",
            *(uint32_t *)(uintptr_t)c[0]);
  }

  if (!emit_headless) {
    emit_ensure_app();
  }
  run_itc(cfa, dsp, rp);

  if (!emit_headless && emit_opened) {
    [NSApp run];
  }
  return 0;
}

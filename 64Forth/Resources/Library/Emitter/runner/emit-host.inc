/* emit-host.inc — thin GRAPHICS host for Emitter stand-alone runner.
 * Implements host_app_* slots 0–8 (AppOutputHost ABI), slot 9 (MS@ /
 * gettimeofday), slots 10–11 (malloc / free), slots 12–14 (BI-MUL /
 * BI-DIVMOD / BI-ISQRT). Public domain.
 */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/time.h>

enum { EMIT_COLS_MAX = 256, EMIT_ROWS_MAX = 128, EMIT_KEYCAP = 64 };

typedef int64_t (*emit_host_fn)(int64_t, int64_t);

#include "emit-bi.inc"

static int emit_opened = 0;
static int emit_cols = 80, emit_rows = 25;
static char emit_app_name[256] = "64Emitter";
static uint8_t *emit_cells = NULL;
static int emit_cell_n = 0;
static uint8_t *emit_pix = NULL;
static int emit_pix_n = 0, emit_pix_w = 640, emit_pix_h = 400, emit_pix_stride = 80;
static int emit_has_pix = 0;
static int64_t emit_keys[EMIT_KEYCAP];
static int emit_kr = 0, emit_kw = 0;
static NSWindow *emit_window = nil;
static NSView *emit_view = nil;
static CGFloat emit_cw = 9.0, emit_ch = 16.0;
static int emit_headless = 0; /* set if --agent / EMIT_HEADLESS */

static void emit_key_push(int64_t c) {
  int n = (emit_kw + 1) % EMIT_KEYCAP;
  if (n == emit_kr) return;
  emit_keys[emit_kw] = c;
  emit_kw = n;
}

static int64_t emit_key_pop(void) {
  if (emit_kr == emit_kw) return -1;
  int64_t c = emit_keys[emit_kr];
  emit_kr = (emit_kr + 1) % EMIT_KEYCAP;
  return c;
}

static int64_t emit_map_key(NSEvent *ev) {
  switch ([ev keyCode]) {
    case 123: return 203;
    case 124: return 205;
    case 125: return 208;
    case 126: return 200;
    case 53:  return 0x1B;
    case 49:  return 0x20;
    default: break;
  }
  NSString *chars = [ev charactersIgnoringModifiers];
  if (chars && [chars length] > 0) {
    unichar u = [chars characterAtIndex:0];
    if (u < 128) return (int64_t)u;
  }
  return -1;
}

@interface EmitGridView : NSView
@end
@implementation EmitGridView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty {
  [[NSColor blackColor] setFill];
  NSRectFill(self.bounds);
  if (emit_has_pix && emit_pix) {
    [[NSColor colorWithCalibratedRed:0.7 green:1.0 blue:0.7 alpha:1] setFill];
    CGFloat dw = self.bounds.size.width - 8;
    CGFloat dh = self.bounds.size.height - 8;
    CGFloat sx = dw / (CGFloat)emit_pix_w;
    CGFloat sy = dh / (CGFloat)emit_pix_h;
    for (int y = 0; y < emit_pix_h; y++) {
      int row = y * emit_pix_stride;
      for (int x = 0; x < emit_pix_w; x++) {
        uint8_t b = emit_pix[row + (x >> 3)];
        if (b & (1u << (x & 7))) {
          NSRectFill(NSMakeRect(4 + x * sx, 4 + (emit_pix_h - 1 - y) * sy,
                                fmax(1, sx), fmax(1, sy)));
        }
      }
    }
  }
  if (!emit_cells) return;
  NSFont *font = [NSFont monospacedSystemFontOfSize:emit_ch - 2 weight:NSFontWeightRegular];
  NSDictionary *attrs = @{
    NSFontAttributeName: font,
    NSForegroundColorAttributeName:
      [NSColor colorWithCalibratedRed:0.7 green:1.0 blue:0.7 alpha:1]
  };
  for (int y = 0; y < emit_rows; y++) {
    for (int x = 0; x < emit_cols; x++) {
      uint8_t ch = emit_cells[y * emit_cols + x];
      if (ch == 32) continue;
      NSString *s;
      if (ch == 219) s = @"\u2588";
      else if (ch < 32 || ch > 126) s = @"?";
      else s = [NSString stringWithFormat:@"%c", (char)ch];
      [s drawAtPoint:NSMakePoint(x * emit_cw + 4, (emit_rows - 1 - y) * emit_ch + 4)
      withAttributes:attrs];
    }
  }
}
- (void)keyDown:(NSEvent *)ev {
  int64_t c = emit_map_key(ev);
  if (c >= 0) emit_key_push(c);
}
@end

@interface EmitWinDelegate : NSObject <NSWindowDelegate>
@end
@implementation EmitWinDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;
  emit_opened = 0;
  emit_key_push(0x1B);
  emit_window = nil;
  emit_view = nil;
  /* ITC may have already returned; stop [NSApp run] so the process exits.
   * stop: alone often sits until the next event — post a wake-up. */
  if (NSApp) {
    [NSApp stop:nil];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                        subtype:0
                                          data1:0
                                          data2:0];
    [NSApp postEvent:wake atStart:YES];
  }
  return YES;
}
@end

static EmitWinDelegate *emit_delegate = nil;

static void emit_ensure_app(void) {
  if (NSApp) return;
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
}

/* ITC runs on the main thread before [NSApp run]; dispatch_sync(main) deadlocks. */
static void emit_on_main_sync(void (^block)(void)) {
  if ([NSThread isMainThread])
    block();
  else
    dispatch_sync(dispatch_get_main_queue(), block);
}

static int64_t host_app_open(int64_t cols, int64_t rows) {
  if (emit_headless) return -1;
  if (cols < 1) cols = 80;
  if (rows < 1) rows = 25;
  if (cols > EMIT_COLS_MAX) cols = EMIT_COLS_MAX;
  if (rows > EMIT_ROWS_MAX) rows = EMIT_ROWS_MAX;
  emit_cols = (int)cols;
  emit_rows = (int)rows;
  emit_cell_n = emit_cols * emit_rows;
  free(emit_cells);
  emit_cells = (uint8_t *)malloc((size_t)emit_cell_n);
  if (emit_cells) memset(emit_cells, 32, (size_t)emit_cell_n);
  emit_on_main_sync(^{
    emit_ensure_app();
    NSFont *font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    emit_ch = font.ascender - font.descender + 2;
    emit_cw = [@"M" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    if (emit_cw < 1) emit_cw = 9;
    if (emit_ch < 1) emit_ch = 16;
    CGFloat cw = emit_cols * emit_cw + 8;
    CGFloat ch = emit_rows * emit_ch + 8;
    if (!emit_delegate) emit_delegate = [EmitWinDelegate new];
    if (!emit_window) {
      emit_window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(100, 80, cw, ch)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
      emit_view = [[EmitGridView alloc] initWithFrame:NSMakeRect(0, 0, cw, ch)];
      emit_window.contentView = emit_view;
      emit_window.delegate = emit_delegate;
    } else {
      [emit_window setContentSize:NSMakeSize(cw, ch)];
      emit_view.frame = NSMakeRect(0, 0, cw, ch);
    }
    emit_window.title = [NSString stringWithUTF8String:emit_app_name];
    [emit_window makeKeyAndOrderFront:nil];
    [emit_window makeFirstResponder:emit_view];
    [NSApp activateIgnoringOtherApps:YES];
    emit_opened = 1;
    [emit_view setNeedsDisplay:YES];
  });
  return 0;
}

static int64_t host_app_close(int64_t a, int64_t b) {
  (void)a; (void)b;
  /* Clear flag sync so main() does not enter [NSApp run] after WINDOW-OFF. */
  emit_opened = 0;
  emit_key_push(0x1B);
  emit_kr = emit_kw = 0;
  emit_on_main_sync(^{
    [emit_window orderOut:nil];
    emit_window = nil;
    emit_view = nil;
  });
  return 0;
}

static int64_t host_app_blit(int64_t addr, int64_t nbytes) {
  if (!emit_opened || !addr || nbytes <= 0 || !emit_cells) return 0;
  int n = (int)nbytes;
  if (n > emit_cell_n) n = emit_cell_n;
  memcpy(emit_cells, (const void *)(uintptr_t)addr, (size_t)n);
  dispatch_async(dispatch_get_main_queue(), ^{
    [emit_view setNeedsDisplay:YES];
    [emit_window displayIfNeeded];
  });
  return 0;
}

static int64_t host_app_pblit(int64_t addr, int64_t nbytes) {
  if (!emit_opened || !addr || nbytes <= 0) return 0;
  emit_pix_stride = (emit_pix_w + 7) / 8;
  int need = emit_pix_stride * emit_pix_h;
  if (!emit_pix || emit_pix_n < need) {
    free(emit_pix);
    emit_pix = (uint8_t *)malloc((size_t)need);
    emit_pix_n = need;
  }
  int n = (int)nbytes;
  if (n > need) n = need;
  memcpy(emit_pix, (const void *)(uintptr_t)addr, (size_t)n);
  emit_has_pix = 1;
  dispatch_async(dispatch_get_main_queue(), ^{
    [emit_view setNeedsDisplay:YES];
    [emit_window displayIfNeeded];
  });
  return 0;
}

/* ITC owns the main thread before [NSApp run]; drain events so KEY works. */
static void emit_pump_events(NSTimeInterval timeout) {
  if (emit_headless || !NSApp) return;
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
  for (;;) {
    NSEvent *ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                     untilDate:until
                                        inMode:NSDefaultRunLoopMode
                                       dequeue:YES];
    if (!ev) break;
    [NSApp sendEvent:ev];
  }
}

static int64_t host_app_keyq(int64_t a, int64_t b) {
  (void)a; (void)b;
  emit_pump_events(0.001);
  if (emit_kr == emit_kw) return 0;
  return -1;
}

/*
 * Wait for a graphics-window key (interactive host_app_key semantics).
 * GRAPHICS KEY also loops on −1:
 *   BEGIN (APP-KEY) DUP 0< WHILE DROP (APP-PUMP) REPEAT
 * Blocking here means even a single (APP-KEY) call waits; returning −1 on
 * empty still works with that Forth loop. Headless: ESC once.
 * Do not map !emit_opened → ESC (WINDOW-OFF clears the flag after KEY).
 */
static int64_t host_app_key(int64_t a, int64_t b) {
  (void)a; (void)b;
  if (emit_headless)
    return 0x1B;
  for (;;) {
    emit_pump_events(0.05);
    int64_t k = emit_key_pop();
    if (k >= 0)
      return k;
  }
}

static int64_t host_app_name(int64_t addr, int64_t nbytes) {
  if (addr && nbytes > 0) {
    size_t n = (size_t)nbytes;
    if (n > sizeof emit_app_name - 1) n = sizeof emit_app_name - 1;
    memcpy(emit_app_name, (const void *)(uintptr_t)addr, n);
    emit_app_name[n] = 0;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (emit_window)
      emit_window.title = [NSString stringWithUTF8String:emit_app_name];
  });
  return 0;
}

static int64_t host_app_tone(int64_t freq, int64_t dur) {
  (void)freq;
  int tenths = (int)dur;
  if (tenths < 0) tenths = 0;
  if (tenths > 50) tenths = 50;
  if (tenths == 0) return 0;
  dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); });
  usleep((useconds_t)(tenths * 100000));
  return 0;
}

static int64_t host_app_pump(int64_t a, int64_t b) {
  (void)a; (void)b;
  emit_pump_events(0.01);
  if (emit_headless) usleep(10000);
  return 0;
}

/* Slot 9: C ABI match for MS@'s bl _gettimeofday (x0=timeval*, x1=tz*). */
static int64_t host_ms_gettimeofday(int64_t tv, int64_t tz) {
  return (int64_t)gettimeofday((struct timeval *)(uintptr_t)tv,
                               (struct timezone *)(uintptr_t)tz);
}

/* Slot 10: ALLOCATE's bl _malloc (x0=size). Returns pointer or 0. */
static int64_t host_malloc(int64_t sz, int64_t unused) {
  (void)unused;
  if (sz <= 0) return 0;
  return (int64_t)(uintptr_t)malloc((size_t)sz);
}

/* Slot 11: FREE's bl _free (x0=ptr). */
static int64_t host_free(int64_t ptr, int64_t unused) {
  (void)unused;
  free((void *)(uintptr_t)ptr);
  return 0;
}

/* Slots 12–14: BI hooks. Forth leaves a,b,r / num,den,quot,rem / a,r in
 * x0..x3 then BLR into the veneer. emit_host_fn is (x0,x1) only — capture
 * x2/x3 before any C prologue can clobber them (-O2). */
__attribute__((noinline, optnone))
static int64_t host_bi_mul_slot(int64_t a, int64_t b) {
  int64_t r;
  __asm__ volatile("mov %0, x2" : "=r"(r));
  emit_bi_mul(a, b, r);
  return 0;
}
__attribute__((noinline, optnone))
static int64_t host_bi_divmod_slot(int64_t num, int64_t den) {
  int64_t quot, rem;
  __asm__ volatile("mov %0, x2\n\tmov %1, x3" : "=r"(quot), "=r"(rem));
  emit_bi_divmod(num, den, quot, rem);
  return 0;
}
__attribute__((noinline, optnone))
static int64_t host_bi_isqrt_slot(int64_t a, int64_t r) {
  emit_bi_isqrt(a, r);
  return 0;
}

/* Slot table — must match Emitter reloc.fth HOST-APP slots 0–14. */
static emit_host_fn host_fn[15] = {
  host_app_open,
  host_app_close,
  host_app_blit,
  host_app_pblit,
  host_app_keyq,
  host_app_key,
  host_app_name,
  host_app_tone,
  host_app_pump,
  host_ms_gettimeofday,
  host_malloc,
  host_free,
  host_bi_mul_slot,
  host_bi_divmod_slot,
  host_bi_isqrt_slot
};

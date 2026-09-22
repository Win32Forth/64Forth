/* emit-host.inc — thin GRAPHICS host for Emitter stand-alone runner.
 * Implements host_app_* slots 0–8 (AppOutputHost ABI), slot 9 (MS@ /
 * gettimeofday), slots 10–11 (malloc / free), slots 12–14 (BI-MUL /
 * BI-DIVMOD / BI-ISQRT), slot 15 (host_app_mouse), slot 16 (cblit),
 * slots 17–20 (APP-IMG-CHOOSE/LOAD/SIZE/RENDER).
 * Public domain.
 */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/time.h>
#include <limits.h>

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
static int emit_pix_depth = 1; /* 1 | 8 | 32 */
static int emit_has_pix = 0;
static uint8_t *emit_bgra = NULL;
static int emit_bgra_n = 0;
static uint32_t emit_palette[256];
static int emit_palette_ready = 0;

static void emit_init_palette(void) {
  static const uint8_t rgb16[16][3] = {
    {0,0,0},{0,0,170},{0,170,0},{0,170,170},
    {170,0,0},{170,0,170},{170,85,0},{170,170,170},
    {85,85,85},{85,85,255},{85,255,85},{85,255,255},
    {255,85,85},{255,85,255},{255,255,85},{255,255,255}
  };
  int i, r, g, b, idx;
  if (emit_palette_ready) return;
  for (i = 0; i < 16; i++) {
    emit_palette[i] = (uint32_t)rgb16[i][2] | ((uint32_t)rgb16[i][1] << 8) |
                      ((uint32_t)rgb16[i][0] << 16) | 0xFF000000u;
  }
  idx = 16;
  for (r = 0; r < 6; r++)
    for (g = 0; g < 6; g++)
      for (b = 0; b < 6; b++) {
        uint8_t R = (uint8_t)(r * 51), G = (uint8_t)(g * 51), B = (uint8_t)(b * 51);
        emit_palette[idx++] = (uint32_t)B | ((uint32_t)G << 8) | ((uint32_t)R << 16) | 0xFF000000u;
      }
  for (i = 0; i < 24; i++) {
    uint8_t v = (uint8_t)(8 + i * 10);
    if (v > 255) v = 255;
    emit_palette[232 + i] = (uint32_t)v | ((uint32_t)v << 8) | ((uint32_t)v << 16) | 0xFF000000u;
  }
  emit_palette_ready = 1;
}
static int64_t emit_keys[EMIT_KEYCAP];
static int emit_kr = 0, emit_kw = 0;
static int64_t emit_mouse_x = 0, emit_mouse_y = 0, emit_mouse_buttons = 0;
static NSWindow *emit_window = nil;
static NSView *emit_view = nil;
static CGFloat emit_cw = 9.0, emit_ch = 16.0;
static int emit_headless = 0; /* set if --agent / EMIT_HEADLESS */

/* Decoded source image for (APP-IMG-*) — BGRA, top row first. */
static uint8_t *emit_img_bgra = NULL;
static int emit_img_w = 0, emit_img_h = 0, emit_img_n = 0;
/* Argv --image / drag-drop staged path; consumed by choose or take. */
static char emit_img_staged[PATH_MAX];
static int emit_img_staged_set = 0;

static void emit_img_clear(void) {
  free(emit_img_bgra);
  emit_img_bgra = NULL;
  emit_img_w = 0;
  emit_img_h = 0;
  emit_img_n = 0;
}

static void emit_img_stage_path(const char *path) {
  if (!path || !path[0]) {
    emit_img_staged_set = 0;
    emit_img_staged[0] = '\0';
    return;
  }
  strncpy(emit_img_staged, path, sizeof(emit_img_staged) - 1);
  emit_img_staged[sizeof(emit_img_staged) - 1] = '\0';
  emit_img_staged_set = 1;
}

static void emit_clear_mouse(void) {
  emit_mouse_x = 0;
  emit_mouse_y = 0;
  emit_mouse_buttons = 0;
}

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
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea *area in self.trackingAreas)
    [self removeTrackingArea:area];
  NSTrackingAreaOptions opts =
    NSTrackingActiveInKeyWindow | NSTrackingMouseMoved |
    NSTrackingInVisibleRect | NSTrackingEnabledDuringMouseDrag;
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:opts
                                                       owner:self
                                                    userInfo:nil]];
}
/* Map AppKit view point → Forth PLOT coords (origin bottom-left). */
- (void)reportMouse:(NSEvent *)ev {
  int pw = emit_has_pix ? (emit_pix_w > 0 ? emit_pix_w : 640) : 640;
  int ph = emit_has_pix ? (emit_pix_h > 0 ? emit_pix_h : 400) : 400;
  CGFloat dw = fmax(1, self.bounds.size.width - 8);
  CGFloat dh = fmax(1, self.bounds.size.height - 8);
  CGFloat sx = dw / (CGFloat)pw;
  CGFloat sy = dh / (CGFloat)ph;
  NSPoint local = [self convertPoint:ev.locationInWindow fromView:nil];
  int x = (int)floor((local.x - 4) / sx);
  int y = (int)floor((local.y - 4) / sy);
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x >= pw) x = pw - 1;
  if (y >= ph) y = ph - 1;
  /* NSEvent.pressedMouseButtons: bit0 left, bit1 right, bit2 middle. */
  emit_mouse_x = x;
  emit_mouse_y = y;
  emit_mouse_buttons = (int64_t)([NSEvent pressedMouseButtons] & 0x7);
}
- (void)drawRect:(NSRect)dirty {
  [[NSColor blackColor] setFill];
  NSRectFill(self.bounds);
  if (emit_has_pix && emit_pix) {
    int need = emit_pix_w * emit_pix_h * 4;
    int x, y, i, n;
    uint8_t *d;
    CGColorSpaceRef cs;
    CGDataProviderRef prov;
    CGImageRef img;
    CGContextRef ctx;
    emit_init_palette();
    if (!emit_bgra || emit_bgra_n < need) {
      free(emit_bgra);
      emit_bgra = (uint8_t *)malloc((size_t)need);
      emit_bgra_n = need;
    }
    d = emit_bgra;
    if (emit_pix_depth == 8) {
      n = emit_pix_w * emit_pix_h;
      if (n > emit_pix_n) n = emit_pix_n;
      for (i = 0; i < n; i++) {
        uint32_t c = emit_palette[emit_pix[i]];
        d[i * 4] = (uint8_t)(c & 0xFF);
        d[i * 4 + 1] = (uint8_t)((c >> 8) & 0xFF);
        d[i * 4 + 2] = (uint8_t)((c >> 16) & 0xFF);
        d[i * 4 + 3] = 0xFF;
      }
    } else if (emit_pix_depth == 32) {
      n = need;
      if (n > emit_pix_n) n = emit_pix_n;
      memcpy(d, emit_pix, (size_t)n);
      for (i = 3; i < n; i += 4) if (d[i] == 0) d[i] = 0xFF;
    } else {
      for (y = 0; y < emit_pix_h; y++) {
        int row = y * emit_pix_stride;
        for (x = 0; x < emit_pix_w; x++) {
          int o = (y * emit_pix_w + x) * 4;
          if (emit_pix[row + (x >> 3)] & (1u << (x & 7))) {
            d[o] = 178; d[o + 1] = 255; d[o + 2] = 178; d[o + 3] = 255;
          } else {
            d[o] = 0; d[o + 1] = 0; d[o + 2] = 0; d[o + 3] = 255;
          }
        }
      }
    }
    cs = CGColorSpaceCreateDeviceRGB();
    prov = CGDataProviderCreateWithData(NULL, d, (size_t)need, NULL);
    img = CGImageCreate(emit_pix_w, emit_pix_h, 8, 32, emit_pix_w * 4, cs,
                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                        prov, NULL, false, kCGRenderingIntentDefault);
    ctx = [[NSGraphicsContext currentContext] CGContext];
    if (ctx && img) {
      CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
      CGContextDrawImage(ctx, CGRectMake(4, 4, self.bounds.size.width - 8,
                                         self.bounds.size.height - 8), img);
    }
    if (img) CGImageRelease(img);
    if (prov) CGDataProviderRelease(prov);
    if (cs) CGColorSpaceRelease(cs);
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
- (void)mouseDown:(NSEvent *)ev {
  [self.window makeFirstResponder:self];
  [self reportMouse:ev];
}
- (void)mouseDragged:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)mouseUp:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)rightMouseDown:(NSEvent *)ev {
  [self.window makeFirstResponder:self];
  [self reportMouse:ev];
}
- (void)rightMouseDragged:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)rightMouseUp:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)otherMouseDown:(NSEvent *)ev {
  [self.window makeFirstResponder:self];
  [self reportMouse:ev];
}
- (void)otherMouseDragged:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)otherMouseUp:(NSEvent *)ev { [self reportMouse:ev]; }
- (void)mouseMoved:(NSEvent *)ev { [self reportMouse:ev]; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                            options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
  return urls.count > 0 ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                            options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
  if (urls.count < 1) return NO;
  emit_img_stage_path(urls[0].path.UTF8String);
  return YES;
}
@end

@interface EmitWinDelegate : NSObject <NSWindowDelegate>
@end
@implementation EmitWinDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;
  emit_opened = 0;
  emit_key_push(0x1B);
  emit_clear_mouse();
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
      [emit_view registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
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
    /* Drop stale ESC from a prior WINDOW-OFF so a later KEY waits. */
    emit_kr = emit_kw = 0;
    emit_clear_mouse();
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
  emit_clear_mouse();
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

static int64_t host_app_cblit_depth(int64_t addr, int64_t nbytes, int64_t depth) {
  int d, stride, need, n;
  if (!emit_opened || !addr || nbytes <= 0) return 0;
  if (depth == 8) {
    d = 8; stride = emit_pix_w; need = emit_pix_w * emit_pix_h;
  } else if (depth == 32) {
    d = 32; stride = emit_pix_w * 4; need = emit_pix_w * emit_pix_h * 4;
  } else {
    d = 1; stride = (emit_pix_w + 7) / 8; need = stride * emit_pix_h;
  }
  if (!emit_pix || emit_pix_n < need) {
    free(emit_pix);
    emit_pix = (uint8_t *)malloc((size_t)need);
    emit_pix_n = need;
  }
  n = (int)nbytes;
  if (n > need) n = need;
  memcpy(emit_pix, (const void *)(uintptr_t)addr, (size_t)n);
  if (n < need) memset(emit_pix + n, 0, (size_t)(need - n));
  emit_pix_depth = d;
  emit_pix_stride = stride;
  emit_has_pix = 1;
  dispatch_async(dispatch_get_main_queue(), ^{
    [emit_view setNeedsDisplay:YES];
    [emit_window displayIfNeeded];
  });
  return 0;
}

static int64_t host_app_pblit(int64_t addr, int64_t nbytes) {
  return host_app_cblit_depth(addr, nbytes, 1);
}

/* Slot 16: (APP-CBLIT) bl _host_app_cblit — x0=addr, x1=nbytes, x2=depth. */
__attribute__((noinline, optnone))
static int64_t host_app_cblit_slot(int64_t addr, int64_t nbytes) {
  int64_t depth;
  __asm__ volatile("mov %0, x2" : "=r"(depth));
  return host_app_cblit_depth(addr, nbytes, depth);
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

/* Slot 15: (APP-MOUSE) bl _host_app_mouse — x0=&x, x1=&y, x2=&buttons.
 * Capture x2 before the C prologue can clobber it (same pattern as BI). */
static void host_app_mouse(int64_t *x, int64_t *y, int64_t *buttons) {
  if (emit_headless || !emit_opened) {
    if (x) *x = 0;
    if (y) *y = 0;
    if (buttons) *buttons = 0;
    return;
  }
  if (x) *x = emit_mouse_x;
  if (y) *y = emit_mouse_y;
  if (buttons) *buttons = emit_mouse_buttons;
}

__attribute__((noinline, optnone))
static int64_t host_app_mouse_slot(int64_t x_ptr, int64_t y_ptr) {
  int64_t buttons_ptr;
  __asm__ volatile("mov %0, x2" : "=r"(buttons_ptr));
  host_app_mouse((int64_t *)(uintptr_t)x_ptr,
                 (int64_t *)(uintptr_t)y_ptr,
                 (int64_t *)(uintptr_t)buttons_ptr);
  return 0;
}

/* --- Image viewer (slots 17–20): NSImage decode → BGRA sample --- */

static int64_t emit_img_ingest_nsimage(NSImage *image) {
  if (!image) return -2;
  NSSize sz = image.size;
  int w = (int)lround(sz.width);
  int h = (int)lround(sz.height);
  if (w < 1 || h < 1) return -2;
  /* Cap absurd sizes (viewer only samples into 640×400). */
  if (w > 8192) w = 8192;
  if (h > 8192) h = 8192;
  int need = w * h * 4;
  uint8_t *buf = (uint8_t *)malloc((size_t)need);
  if (!buf) return -2;
  memset(buf, 0, (size_t)need);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(
      buf, (size_t)w, (size_t)h, 8, (size_t)w * 4, cs,
      kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
  if (!ctx) {
    if (cs) CGColorSpaceRelease(cs);
    free(buf);
    return -2;
  }
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  NSGraphicsContext *prev = [NSGraphicsContext currentContext];
  NSGraphicsContext *ngc =
      [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
  [NSGraphicsContext setCurrentContext:ngc];
  [[NSColor blackColor] setFill];
  NSRectFill(NSMakeRect(0, 0, w, h));
  [image drawInRect:NSMakeRect(0, 0, w, h)
           fromRect:NSZeroRect
          operation:NSCompositingOperationCopy
           fraction:1.0
     respectFlipped:YES
              hints:nil];
  [NSGraphicsContext setCurrentContext:prev];
  CGContextRelease(ctx);
  if (cs) CGColorSpaceRelease(cs);
  emit_img_clear();
  emit_img_bgra = buf;
  emit_img_w = w;
  emit_img_h = h;
  emit_img_n = need;
  return 0;
}

static int64_t emit_img_load_path(const char *path) {
  if (!path || !path[0]) return -2;
  @autoreleasepool {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:@(path)];
    if (!image) {
      emit_img_clear();
      return -2;
    }
    return emit_img_ingest_nsimage(image);
  }
}

static int64_t host_app_img_load(int64_t addr, int64_t nbytes) {
  if (!addr || nbytes <= 0) return -2;
  size_t n = (size_t)nbytes;
  if (n > 4096) n = 4096;
  char path[4097];
  memcpy(path, (const void *)(uintptr_t)addr, n);
  path[n] = '\0';
  /* Trim trailing whitespace/newlines. */
  while (n > 0 && (path[n - 1] == ' ' || path[n - 1] == '\n' ||
                   path[n - 1] == '\r' || path[n - 1] == '\t')) {
    path[--n] = '\0';
  }
  return emit_img_load_path(path);
}

static int64_t host_app_img_choose(int64_t a, int64_t b) {
  (void)a;
  (void)b;
  if (emit_headless) return -1;
  /* Prefer staged argv / drag-drop path once. */
  if (emit_img_staged_set) {
    char staged[PATH_MAX];
    strncpy(staged, emit_img_staged, sizeof(staged) - 1);
    staged[sizeof(staged) - 1] = '\0';
    emit_img_staged_set = 0;
    emit_img_staged[0] = '\0';
    return emit_img_load_path(staged);
  }
  __block int64_t ior = -1;
  emit_on_main_sync(^{
    emit_ensure_app();
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Image";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    /* Any file; NSImage load fails → ior -2 (avoids deprecated allowedFileTypes). */
    NSModalResponse resp;
    if (emit_window) {
      __block NSModalResponse r = NSModalResponseCancel;
      dispatch_semaphore_t sem = dispatch_semaphore_create(0);
      [panel beginSheetModalForWindow:emit_window
                    completionHandler:^(NSModalResponse result) {
                      r = result;
                      dispatch_semaphore_signal(sem);
                    }];
      while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        emit_pump_events(0.05);
      }
      resp = r;
    } else {
      resp = [panel runModal];
    }
    if (resp != NSModalResponseOK || !panel.URL) {
      ior = -1;
      return;
    }
    ior = emit_img_load_path(panel.URL.path.UTF8String);
  });
  return ior;
}

static void host_app_img_size(int64_t *w, int64_t *h) {
  if (w) *w = (int64_t)emit_img_w;
  if (h) *h = (int64_t)emit_img_h;
}

__attribute__((noinline, optnone))
static int64_t host_app_img_size_slot(int64_t w_ptr, int64_t h_ptr) {
  host_app_img_size((int64_t *)(uintptr_t)w_ptr, (int64_t *)(uintptr_t)h_ptr);
  return 0;
}

static int64_t host_app_img_render(void *dest, int64_t dest_w, int64_t dest_h,
                                   int64_t cx, int64_t cy, int64_t zoom100) {
  int dw, dh, z, sx, sy, ix, iy, o, s, half_w, half_h;
  uint8_t *out;
  if (!dest || dest_w <= 0 || dest_h <= 0 || emit_img_w <= 0 || emit_img_h <= 0 ||
      !emit_img_bgra)
    return -1;
  dw = (int)dest_w;
  dh = (int)dest_h;
  z = (int)zoom100;
  if (z < 1) z = 1;
  out = (uint8_t *)dest;
  half_w = dw / 2;
  half_h = dh / 2;
  for (sy = 0; sy < dh; sy++) {
    for (sx = 0; sx < dw; sx++) {
      ix = (int)cx + (sx - half_w) * 100 / z;
      iy = (int)cy + (sy - half_h) * 100 / z;
      o = (sy * dw + sx) * 4;
      if (ix < 0 || iy < 0 || ix >= emit_img_w || iy >= emit_img_h) {
        out[o] = 0;
        out[o + 1] = 0;
        out[o + 2] = 0;
        out[o + 3] = 255;
      } else {
        s = (iy * emit_img_w + ix) * 4;
        out[o] = emit_img_bgra[s];
        out[o + 1] = emit_img_bgra[s + 1];
        out[o + 2] = emit_img_bgra[s + 2];
        out[o + 3] = 255;
      }
    }
  }
  return 0;
}

/* Slot 20: bl _host_app_img_render — x0=dest x1=w x2=h x3=cx x4=cy x5=zoom100 */
__attribute__((noinline, optnone))
static int64_t host_app_img_render_slot(int64_t dest, int64_t dest_w) {
  int64_t dest_h, cx, cy, zoom100;
  __asm__ volatile("mov %0, x2\n\tmov %1, x3\n\tmov %2, x4\n\tmov %3, x5"
                   : "=r"(dest_h), "=r"(cx), "=r"(cy), "=r"(zoom100));
  return host_app_img_render((void *)(uintptr_t)dest, dest_w, dest_h, cx, cy,
                             zoom100);
}

/* Slot table — must match Emitter reloc.fth HOST-APP slots 0–20. */
static emit_host_fn host_fn[21] = {
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
  host_bi_isqrt_slot,
  host_app_mouse_slot,
  host_app_cblit_slot,
  host_app_img_choose,
  host_app_img_load,
  host_app_img_size_slot,
  host_app_img_render_slot
};

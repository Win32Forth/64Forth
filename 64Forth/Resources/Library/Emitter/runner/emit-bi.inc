/* emit-bi.inc — stand-alone BI-MUL / BI-DIVMOD / BI-ISQRT (base 10^9 limbs).
 * Layout matches BigInteger/big-int.fth and Host/BigIntHost.swift.
 * Public domain.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

enum { BI_BASE = 1000000000 };

static int64_t *bi_cell(int64_t addr) {
  return (int64_t *)(uintptr_t)addr;
}
static int64_t bi_rd(int64_t *p) { return p ? *p : 0; }
static void bi_wr(int64_t *p, int64_t v) { if (p) *p = v; }

static int bi_cap(int64_t *bi) {
  int c = (int)bi_rd(bi);
  return c < 0 ? 0 : c;
}
static int bi_len(int64_t *bi) {
  int n = (int)bi_rd(bi + 1);
  return n < 0 ? 0 : n;
}
static void bi_set_len(int64_t *bi, int n) { bi_wr(bi + 1, n < 0 ? 0 : n); }
static void bi_set_sgn(int64_t *bi, int s) { bi_wr(bi + 2, s < 0 ? -1 : 1); }
static int64_t *bi_limb(int64_t *bi, int i) { return bi + 3 + i; }

static int bi_read(int64_t *bi, int64_t **out_limbs, int *out_sign) {
  int cap = bi_cap(bi), n = bi_len(bi), i;
  if (n > cap) n = cap;
  if (n <= 0) { *out_limbs = NULL; *out_sign = 1; return 0; }
  int64_t *a = (int64_t *)malloc((size_t)n * sizeof(int64_t));
  if (!a) { *out_limbs = NULL; *out_sign = 1; return 0; }
  for (i = 0; i < n; i++) a[i] = bi_rd(bi_limb(bi, i));
  while (n > 0 && a[n - 1] == 0) n--;
  if (n == 0) { free(a); *out_limbs = NULL; *out_sign = 1; return 0; }
  *out_limbs = a;
  *out_sign = bi_rd(bi + 2) < 0 ? -1 : 1;
  return n;
}

static void bi_write(int64_t *bi, int sign, int64_t *limbs, int n) {
  int cap, i;
  while (n > 0 && limbs[n - 1] == 0) n--;
  if (n <= 0) { bi_set_len(bi, 0); bi_set_sgn(bi, 1); return; }
  cap = bi_cap(bi);
  if (n > cap) {
    fprintf(stderr, "emit-bi: capacity exceeded need=%d cap=%d\n", n, cap);
    return;
  }
  for (i = 0; i < n; i++) bi_wr(bi_limb(bi, i), limbs[i]);
  bi_set_len(bi, n);
  bi_set_sgn(bi, sign < 0 ? -1 : 1);
}

static int bi_cmp(const int64_t *a, int na, const int64_t *b, int nb) {
  int i;
  if (na != nb) return na < nb ? -1 : 1;
  for (i = na - 1; i >= 0; i--)
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  return 0;
}

static int64_t *bi_mul_limbs(const int64_t *a, int na, const int64_t *b, int nb, int *out_n) {
  int i, j, k, nc;
  int64_t *c, carry, p;
  if (na == 0 || nb == 0) { *out_n = 0; return NULL; }
  nc = na + nb;
  c = (int64_t *)calloc((size_t)(nc + 1), sizeof(int64_t));
  if (!c) { *out_n = 0; return NULL; }
  for (i = 0; i < na; i++) {
    carry = 0;
    for (j = 0; j < nb; j++) {
      p = a[i] * b[j] + c[i + j] + carry;
      c[i + j] = p % BI_BASE;
      carry = p / BI_BASE;
    }
    k = i + nb;
    while (carry) {
      if (k >= nc) { nc++; c = (int64_t *)realloc(c, (size_t)(nc + 1) * sizeof(int64_t)); c[nc] = 0; }
      p = c[k] + carry;
      c[k] = p % BI_BASE;
      carry = p / BI_BASE;
      k++;
    }
  }
  while (nc > 0 && c[nc - 1] == 0) nc--;
  *out_n = nc;
  return c;
}

static int64_t *bi_add_limbs(const int64_t *a, int na, const int64_t *b, int nb, int *out_n) {
  int n = na > nb ? na : nb, i;
  int64_t *c = (int64_t *)calloc((size_t)(n + 1), sizeof(int64_t));
  int64_t carry = 0, s;
  if (!c) { *out_n = 0; return NULL; }
  for (i = 0; i < n; i++) {
    s = (i < na ? a[i] : 0) + (i < nb ? b[i] : 0) + carry;
    c[i] = s % BI_BASE;
    carry = s / BI_BASE;
  }
  c[n] = carry;
  n = n + (carry ? 1 : 0);
  while (n > 0 && c[n - 1] == 0) n--;
  *out_n = n;
  return c;
}

static int64_t *bi_sub_limbs(const int64_t *a, int na, const int64_t *b, int nb, int *out_n) {
  int i;
  int64_t *c = (int64_t *)calloc((size_t)na, sizeof(int64_t));
  int64_t borrow = 0, d;
  if (!c) { *out_n = 0; return NULL; }
  for (i = 0; i < na; i++) {
    d = a[i] - (i < nb ? b[i] : 0) - borrow;
    if (d < 0) { d += BI_BASE; borrow = 1; } else borrow = 0;
    c[i] = d;
  }
  while (na > 0 && c[na - 1] == 0) na--;
  *out_n = na;
  return c;
}

static int64_t *bi_mul_small(const int64_t *x, int nx, int64_t k, int *out_n) {
  int i;
  int64_t *out, carry = 0, p;
  if (k == 0 || nx == 0) { *out_n = 0; return NULL; }
  out = (int64_t *)calloc((size_t)(nx + 1), sizeof(int64_t));
  if (!out) { *out_n = 0; return NULL; }
  for (i = 0; i < nx; i++) {
    p = x[i] * k + carry;
    out[i] = p % BI_BASE;
    carry = p / BI_BASE;
  }
  out[nx] = carry;
  nx = nx + (carry ? 1 : 0);
  while (nx > 0 && out[nx - 1] == 0) nx--;
  *out_n = nx;
  return out;
}

static void bi_divmod_limbs(const int64_t *u_in, int nu, const int64_t *v_in, int nv,
                            int64_t **oq, int *onq, int64_t **or_, int *onr) {
  int64_t *u = NULL, *v = NULL, *q = NULL, *uu = NULL;
  int i, n, m, j;
  int nr_local = 0, *pnr = onr ? onr : &nr_local;
  int64_t *r_local = NULL, **pr = or_ ? or_ : &r_local;
  if (oq) { *oq = NULL; }
  if (onq) { *onq = 0; }
  if (or_) { *or_ = NULL; }
  if (onr) { *onr = 0; }
  if (nv <= 0) return;
  u = (int64_t *)malloc((size_t)nu * sizeof(int64_t));
  v = (int64_t *)malloc((size_t)nv * sizeof(int64_t));
  if (!u || !v) { free(u); free(v); return; }
  memcpy(u, u_in, (size_t)nu * sizeof(int64_t));
  memcpy(v, v_in, (size_t)nv * sizeof(int64_t));
  while (nu > 0 && u[nu - 1] == 0) nu--;
  while (nv > 0 && v[nv - 1] == 0) nv--;
  if (nu == 0) { free(u); free(v); return; }
  if (bi_cmp(u, nu, v, nv) < 0) {
    *pr = u; *pnr = nu; free(v); return;
  }
  if (nv == 1) {
    int64_t d = v[0], rem = 0, cur;
    q = (int64_t *)calloc((size_t)nu, sizeof(int64_t));
    for (i = nu - 1; i >= 0; i--) {
      cur = rem * (int64_t)BI_BASE + u[i];
      q[i] = cur / d;
      rem = cur % d;
    }
    while (nu > 0 && q[nu - 1] == 0) nu--;
    if (oq) *oq = q; else free(q);
    if (onq) *onq = nu;
    if (rem) {
      int64_t *rr = (int64_t *)malloc(sizeof(int64_t));
      if (rr) { rr[0] = rem; *pr = rr; *pnr = 1; }
    }
    free(u); free(v);
    if (!or_ && r_local) free(r_local);
    return;
  }
  n = nv; m = nu - n;
  uu = (int64_t *)calloc((size_t)(nu + 1), sizeof(int64_t));
  q = (int64_t *)calloc((size_t)(m + 1), sizeof(int64_t));
  if (!uu || !q) { free(u); free(v); free(uu); free(q); return; }
  memcpy(uu, u, (size_t)nu * sizeof(int64_t));
  for (j = m; j >= 0; j--) {
    int64_t lo = 0, hi = BI_BASE - 1, lead = v[n - 1];
    int64_t numHi = uu[j + n] * (int64_t)BI_BASE + uu[j + n - 1];
    if (lead > 0) {
      int64_t t = numHi / lead;
      if (t < hi) hi = t;
    }
    while (lo < hi) {
      int64_t mid = (lo + hi + 1) / 2;
      int np = 0, nw;
      int64_t *prod = bi_mul_small(v, n, mid, &np);
      int64_t *w = (int64_t *)malloc((size_t)(n + 1) * sizeof(int64_t));
      nw = n + 1;
      memcpy(w, uu + j, (size_t)nw * sizeof(int64_t));
      while (nw > 0 && w[nw - 1] == 0) nw--;
      if (bi_cmp(prod, np, w, nw) <= 0) lo = mid;
      else hi = mid - 1;
      free(prod); free(w);
    }
    if (lo > 0) {
      int np = 0, ii;
      int64_t *prod = bi_mul_small(v, n, lo, &np);
      int64_t borrow = 0, d;
      for (ii = 0; ii < n + 1; ii++) {
        d = uu[j + ii] - (ii < np ? prod[ii] : 0) - borrow;
        if (d < 0) { d += BI_BASE; borrow = 1; } else borrow = 0;
        uu[j + ii] = d;
      }
      free(prod);
    }
    q[j] = lo;
  }
  i = m + 1;
  while (i > 0 && q[i - 1] == 0) i--;
  if (oq) *oq = q; else free(q);
  if (onq) *onq = i;
  i = n + 1;
  while (i > 0 && uu[i - 1] == 0) i--;
  if (i > 0) {
    int64_t *rr = (int64_t *)malloc((size_t)i * sizeof(int64_t));
    if (rr) { memcpy(rr, uu, (size_t)i * sizeof(int64_t)); *pr = rr; *pnr = i; }
  }
  free(u); free(v); free(uu);
  if (!or_ && r_local) free(r_local);
}

static int64_t *bi_isqrt_limbs(const int64_t *a, int na, int *out_n) {
  int64_t *x = NULL, *prev = NULL;
  int nx, nprev, guard, initLen, i;
  *out_n = 0;
  if (na <= 0) return NULL;
  if (na == 1) {
    int64_t v = a[0], t = (int64_t)sqrt((double)v);
    while ((t + 1) * (t + 1) <= v) t++;
    while (t * t > v) t--;
    if (t == 0) return NULL;
    x = (int64_t *)malloc(sizeof(int64_t));
    if (!x) return NULL;
    x[0] = t; *out_n = 1; return x;
  }
  initLen = (na + 1) / 2;
  x = (int64_t *)calloc((size_t)initLen, sizeof(int64_t));
  if (!x) return NULL;
  nx = initLen;
  x[initLen - 1] = (int64_t)sqrt((double)a[na - 1]) + 1;
  if (x[initLen - 1] < 1) x[initLen - 1] = 1;
  if (x[initLen - 1] >= BI_BASE) x[initLen - 1] = BI_BASE - 1;
  for (guard = 0; guard < 10000; guard++) {
    int64_t *q = NULL, *s = NULL, *half = NULL;
    int nq = 0, ns = 0, nh = 0;
    int64_t carry = 0, cur;
    nprev = nx;
    free(prev);
    prev = (int64_t *)malloc((size_t)nx * sizeof(int64_t));
    if (prev) memcpy(prev, x, (size_t)nx * sizeof(int64_t));
    bi_divmod_limbs(a, na, x, nx, &q, &nq, NULL, NULL);
    s = bi_add_limbs(x, nx, q, nq, &ns);
    free(q);
    half = (int64_t *)calloc((size_t)(ns ? ns : 1), sizeof(int64_t));
    for (i = ns - 1; i >= 0; i--) {
      cur = carry * (int64_t)BI_BASE + s[i];
      half[i] = cur / 2;
      carry = cur % 2;
    }
    free(s);
    nh = ns;
    while (nh > 0 && half[nh - 1] == 0) nh--;
    free(x);
    if (nh <= 0) { x = (int64_t *)malloc(sizeof(int64_t)); x[0] = 1; nx = 1; free(half); }
    else { x = half; nx = nh; }
    if (prev && nprev == nx && memcmp(prev, x, (size_t)nx * sizeof(int64_t)) == 0) break;
  }
  free(prev);
  for (;;) {
    int nsq = 0, nxp = 0, nsq2 = 0;
    int64_t *sq = bi_mul_limbs(x, nx, x, nx, &nsq);
    int64_t one = 1, *xp, *sq2;
    if (bi_cmp(sq, nsq, a, na) <= 0) {
      xp = bi_add_limbs(x, nx, &one, 1, &nxp);
      sq2 = bi_mul_limbs(xp, nxp, xp, nxp, &nsq2);
      free(sq);
      if (bi_cmp(sq2, nsq2, a, na) <= 0) {
        free(x); free(sq2); x = xp; nx = nxp; continue;
      }
      free(xp); free(sq2); break;
    }
    free(sq);
    { int64_t *xs = bi_sub_limbs(x, nx, &one, 1, &nxp); free(x); x = xs; nx = nxp; }
  }
  *out_n = nx;
  return x;
}

static void emit_bi_mul(int64_t a, int64_t b, int64_t r) {
  int64_t *la = NULL, *lb = NULL, *lr = NULL;
  int na, nb, nr, sa, sb;
  na = bi_read(bi_cell(a), &la, &sa);
  nb = bi_read(bi_cell(b), &lb, &sb);
  lr = bi_mul_limbs(la, na, lb, nb, &nr);
  bi_write(bi_cell(r), sa * sb, lr, nr);
  free(la); free(lb); free(lr);
}

static void emit_bi_divmod(int64_t num, int64_t den, int64_t quot, int64_t rem) {
  int64_t *ln = NULL, *ld = NULL, *lq = NULL, *lr = NULL;
  int nn, nd, nq, nr, sn, sd;
  nn = bi_read(bi_cell(num), &ln, &sn);
  nd = bi_read(bi_cell(den), &ld, &sd);
  if (nd == 0 || nn == 0) {
    bi_write(bi_cell(quot), 1, NULL, 0);
    bi_write(bi_cell(rem), 1, NULL, 0);
    free(ln); free(ld);
    return;
  }
  bi_divmod_limbs(ln, nn, ld, nd, &lq, &nq, &lr, &nr);
  bi_write(bi_cell(quot), nq ? sn * sd : 1, lq, nq);
  bi_write(bi_cell(rem), nr ? sn : 1, lr, nr);
  free(ln); free(ld); free(lq); free(lr);
}

static void emit_bi_isqrt(int64_t a, int64_t r) {
  int64_t *la = NULL, *lr = NULL;
  int na, nr, sa;
  na = bi_read(bi_cell(a), &la, &sa);
  lr = bi_isqrt_limbs(la, na, &nr);
  bi_write(bi_cell(r), 1, lr, nr);
  free(la); free(lr);
}


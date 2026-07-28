//
//  BigIntHost.swift
//  64Forth
//
//  Public domain.
//
//  Host multiprecision for BI-MUL / BI-DIVMOD / BI-ISQRT (TZForth lineage).
//  Layout matches Resources/Library/BigInteger/big-int.fth (base 10^9 limbs).
//

import Foundation

/// Raw multiprecision helpers. Addresses are process pointers to ALLOCATE'd cells.
enum BigIntHost {
    private static let biBase: Int64 = 1_000_000_000
    private static let cell = 8

    /// Sticky count of capacity overflows (result would not fit). Soft-fail used to
    /// zero the destination, which made π (and other BI) collapse to 0.
    private(set) static var capacityOverflows: Int = 0

    // MARK: - Memory

    /// Preserve all bits of a kernel cell used as a raw pointer (ASLR-safe).
    private static func asAddr(_ cell: Int64) -> Int {
        Int(bitPattern: UInt(bitPattern: Int(truncatingIfNeeded: cell)))
    }

    private static func readCell(_ addr: Int) -> Int64 {
        UnsafePointer<Int64>(bitPattern: addr)!.pointee
    }

    private static func writeCell(_ addr: Int, _ v: Int64) {
        UnsafeMutablePointer<Int64>(bitPattern: addr)!.pointee = v
    }

    private static func biCap(_ bi: Int) -> Int {
        let c = Int(readCell(bi))
        return c < 0 ? 0 : c
    }
    private static func biLen(_ bi: Int) -> Int {
        let n = Int(readCell(bi + cell))
        return n < 0 ? 0 : n
    }
    private static func biSgn(_ bi: Int) -> Int {
        let s = Int(readCell(bi + 2 * cell))
        return s < 0 ? -1 : 1
    }
    private static func biLimbAddr(_ bi: Int, _ i: Int) -> Int {
        bi + 3 * cell + i * cell
    }
    private static func biSetLen(_ bi: Int, _ n: Int) {
        writeCell(bi + cell, Int64(max(0, n)))
    }
    private static func biSetSgn(_ bi: Int, _ s: Int) {
        writeCell(bi + 2 * cell, Int64(s < 0 ? -1 : 1))
    }

    private static func biReadLimbs(_ bi: Int) -> (sign: Int, limbs: [Int64]) {
        let cap = biCap(bi)
        var n = biLen(bi)
        // Clamp: corrupt/oversize len must not read past the allocation.
        if n > cap { n = cap }
        if n <= 0 { return (1, []) }
        var limbs = [Int64]()
        limbs.reserveCapacity(n)
        for i in 0..<n {
            limbs.append(readCell(biLimbAddr(bi, i)))
        }
        while limbs.last == 0 { limbs.removeLast() }
        if limbs.isEmpty { return (1, []) }
        return (biSgn(bi), limbs)
    }

    private static func biWriteLimbs(_ bi: Int, sign: Int, limbs: [Int64]) {
        var ls = limbs
        while ls.last == 0 { ls.removeLast() }
        if ls.isEmpty {
            biSetLen(bi, 0)
            biSetSgn(bi, 1)
            return
        }
        let cap = biCap(bi)
        if ls.count > cap {
            // TZForth throws here. We must not zero the destination (that made PI. print 0).
            // Leave the buffer unchanged so callers can detect a missing update; count overflows.
            capacityOverflows += 1
            let msg = "BigIntHost: BI capacity exceeded (need \(ls.count) limbs, cap \(cap))\n"
            fputs("64Forth \(msg)", stderr)
            FileHost.shared.onMessage?(msg)
            return
        }
        for i in 0..<ls.count {
            writeCell(biLimbAddr(bi, i), ls[i])
        }
        biSetLen(bi, ls.count)
        biSetSgn(bi, sign < 0 ? -1 : 1)
    }

    // MARK: - Limb arithmetic

    private static func biMulLimbs(_ a: [Int64], _ b: [Int64]) -> [Int64] {
        if a.isEmpty || b.isEmpty { return [] }
        var c = [Int64](repeating: 0, count: a.count + b.count)
        let base = biBase
        for i in 0..<a.count {
            var carry: Int64 = 0
            for j in 0..<b.count {
                let p = a[i] * b[j] + c[i + j] + carry
                c[i + j] = p % base
                carry = p / base
            }
            var k = i + b.count
            while carry != 0 {
                if k >= c.count { c.append(0) }
                let p = c[k] + carry
                c[k] = p % base
                carry = p / base
                k += 1
            }
        }
        while c.last == 0 { c.removeLast() }
        return c
    }

    private static func biCmpAbs(_ a: [Int64], _ b: [Int64]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        var i = a.count - 1
        while i >= 0 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    private static func biAddAbs(_ a: [Int64], _ b: [Int64]) -> [Int64] {
        let base = biBase
        let n = max(a.count, b.count)
        var c = [Int64](repeating: 0, count: n + 1)
        var carry: Int64 = 0
        for i in 0..<n {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            let s = av + bv + carry
            c[i] = s % base
            carry = s / base
        }
        c[n] = carry
        while c.last == 0 { c.removeLast() }
        return c
    }

    private static func biSubAbs(_ a: [Int64], _ b: [Int64]) -> [Int64] {
        let base = biBase
        var c = [Int64](repeating: 0, count: a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            let bv = i < b.count ? b[i] : 0
            var d = a[i] - bv - borrow
            if d < 0 {
                d += base
                borrow = 1
            } else {
                borrow = 0
            }
            c[i] = d
        }
        while c.last == 0 { c.removeLast() }
        return c
    }

    private static func biDivModLimbs(_ uIn: [Int64], _ vIn: [Int64]) -> (q: [Int64], r: [Int64]) {
        if vIn.isEmpty { return ([], []) }
        var u = uIn
        var v = vIn
        while u.last == 0 { u.removeLast() }
        while v.last == 0 { v.removeLast() }
        if u.isEmpty { return ([], []) }
        if biCmpAbs(u, v) < 0 { return ([], u) }

        let base = biBase

        if v.count == 1 {
            let d = v[0]
            var rem: Int64 = 0
            var q = [Int64](repeating: 0, count: u.count)
            var i = u.count - 1
            while i >= 0 {
                let cur = rem * base + u[i]
                q[i] = cur / d
                rem = cur % d
                i -= 1
            }
            while q.last == 0 { q.removeLast() }
            let r: [Int64] = rem == 0 ? [] : [rem]
            return (q, r)
        }

        let n = v.count
        let m = u.count - n
        var uu = u + [Int64(0)]
        var q = [Int64](repeating: 0, count: m + 1)

        func mulSmall(_ x: [Int64], _ k: Int64) -> [Int64] {
            if k == 0 || x.isEmpty { return [] }
            var out = [Int64](repeating: 0, count: x.count + 1)
            var carry: Int64 = 0
            for i in 0..<x.count {
                let p = x[i] * k + carry
                out[i] = p % base
                carry = p / base
            }
            out[x.count] = carry
            while out.last == 0 { out.removeLast() }
            return out
        }

        func window(_ start: Int) -> [Int64] {
            var w = Array(uu[start..<(start + n + 1)])
            while w.last == 0 { w.removeLast() }
            return w
        }

        func subFromWindow(_ prod: [Int64], start: Int) {
            var borrow: Int64 = 0
            for i in 0..<(n + 1) {
                let pv = i < prod.count ? prod[i] : 0
                var d = uu[start + i] - pv - borrow
                if d < 0 {
                    d += base
                    borrow = 1
                } else {
                    borrow = 0
                }
                uu[start + i] = d
            }
        }

        for j in stride(from: m, through: 0, by: -1) {
            var lo: Int64 = 0
            var hi: Int64 = base - 1
            let numHi = uu[j + n] * base + uu[j + n - 1]
            let lead = v[n - 1]
            if lead > 0 {
                hi = min(hi, numHi / lead)
            }
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                let prod = mulSmall(v, mid)
                if biCmpAbs(prod, window(j)) <= 0 {
                    lo = mid
                } else {
                    hi = mid - 1
                }
            }
            if lo > 0 {
                subFromWindow(mulSmall(v, lo), start: j)
            }
            q[j] = lo
        }
        while q.last == 0 { q.removeLast() }
        var r = Array(uu.prefix(n + 1))
        while r.last == 0 { r.removeLast() }
        return (q, r)
    }

    private static func biIsqrtLimbs(_ a: [Int64]) -> [Int64] {
        if a.isEmpty { return [] }
        if a.count == 1 {
            var x = Int64(Double(a[0]).squareRoot())
            while (x + 1) * (x + 1) <= a[0] { x += 1 }
            while x * x > a[0] { x -= 1 }
            return x == 0 ? [] : [x]
        }
        var x: [Int64]
        let initLen = (a.count + 1) / 2
        x = [Int64](repeating: 0, count: initLen)
        x[initLen - 1] = max(1, Int64(Double(a[a.count - 1]).squareRoot()) + 1)
        if x[initLen - 1] >= biBase {
            x[initLen - 1] = biBase - 1
        }
        var prev: [Int64] = []
        var guardCount = 0
        while x != prev && guardCount < 10_000 {
            guardCount += 1
            prev = x
            let (q, _) = biDivModLimbs(a, x)
            let s = biAddAbs(x, q)
            var carry: Int64 = 0
            var half = [Int64](repeating: 0, count: s.count)
            var i = s.count - 1
            while i >= 0 {
                let cur = carry * biBase + s[i]
                half[i] = cur / 2
                carry = cur % 2
                i -= 1
            }
            while half.last == 0 { half.removeLast() }
            x = half.isEmpty ? [1] : half
        }
        while true {
            let sq = biMulLimbs(x, x)
            if biCmpAbs(sq, a) <= 0 {
                let xp = biAddAbs(x, [1])
                let sq2 = biMulLimbs(xp, xp)
                if biCmpAbs(sq2, a) <= 0 {
                    x = xp
                    continue
                }
                break
            } else {
                x = biSubAbs(x, [1])
            }
        }
        return x
    }

    // MARK: - C ABI entry points

    static func mul(a: Int64, b: Int64, r: Int64) {
        let aa = asAddr(a), bb = asAddr(b), rr = asAddr(r)
        let (sa, la) = biReadLimbs(aa)
        let (sb, lb) = biReadLimbs(bb)
        biWriteLimbs(rr, sign: sa * sb, limbs: biMulLimbs(la, lb))
    }

    static func divmod(num: Int64, den: Int64, quot: Int64, rem: Int64) {
        let nn = asAddr(num), dd = asAddr(den), qq = asAddr(quot), rr = asAddr(rem)
        let (sn, ln) = biReadLimbs(nn)
        let (sd, ld) = biReadLimbs(dd)
        if ld.isEmpty {
            biWriteLimbs(qq, sign: 1, limbs: [])
            biWriteLimbs(rr, sign: 1, limbs: [])
            return
        }
        if ln.isEmpty {
            biWriteLimbs(qq, sign: 1, limbs: [])
            biWriteLimbs(rr, sign: 1, limbs: [])
            return
        }
        let (q, rlimbs) = biDivModLimbs(ln, ld)
        let qs = q.isEmpty ? 1 : sn * sd
        let rs = rlimbs.isEmpty ? 1 : sn
        biWriteLimbs(qq, sign: qs, limbs: q)
        biWriteLimbs(rr, sign: rs, limbs: rlimbs)
    }

    static func isqrt(a: Int64, r: Int64) {
        let aa = asAddr(a), rr = asAddr(r)
        let (_, la) = biReadLimbs(aa)
        biWriteLimbs(rr, sign: 1, limbs: biIsqrtLimbs(la))
    }

    /// Heap self-test for mul / divmod / multi-limb isqrt (called once at host boot).
    /// Returns nil on success, or an error string.
    static func selfTest() -> String? {
        func allocBI(cap: Int) -> UnsafeMutablePointer<Int64> {
            let words = 3 + cap
            let p = UnsafeMutablePointer<Int64>.allocate(capacity: words)
            p.initialize(repeating: 0, count: words)
            p[0] = Int64(cap)
            p[1] = 0
            p[2] = 1
            return p
        }
        func freeBI(_ p: UnsafeMutablePointer<Int64>, cap: Int) {
            p.deinitialize(count: 3 + cap)
            p.deallocate()
        }
        func cell(_ p: UnsafeMutablePointer<Int64>) -> Int64 {
            Int64(bitPattern: UInt64(UInt(bitPattern: p)))
        }
        func setU(_ p: UnsafeMutablePointer<Int64>, _ u: Int64) {
            if u == 0 {
                p[1] = 0
                p[2] = 1
                return
            }
            var x = u
            var i = 0
            while x != 0 {
                p[3 + i] = x % biBase
                x /= biBase
                i += 1
            }
            p[1] = Int64(i)
            p[2] = 1
        }
        func getU(_ p: UnsafeMutablePointer<Int64>) -> Int64? {
            let n = Int(p[1])
            if n <= 0 { return 0 }
            if n > 3 { return nil }
            var v: Int64 = 0
            var place: Int64 = 1
            for i in 0..<n {
                let limb = p[3 + i]
                if limb < 0 || limb >= biBase { return nil }
                v += limb * place
                place *= biBase
            }
            return v
        }

        capacityOverflows = 0
        let cap = 16
        let a = allocBI(cap: cap)
        let b = allocBI(cap: cap)
        let r = allocBI(cap: cap)
        let q = allocBI(cap: cap)
        let rem = allocBI(cap: cap)
        defer {
            freeBI(a, cap: cap); freeBI(b, cap: cap); freeBI(r, cap: cap)
            freeBI(q, cap: cap); freeBI(rem, cap: cap)
        }

        setU(a, 123); setU(b, 456)
        mul(a: cell(a), b: cell(b), r: cell(r))
        if getU(r) != 56088 { return "mul 123*456 failed (\(String(describing: getU(r))))" }

        setU(a, biBase)
        setU(b, biBase)
        mul(a: cell(a), b: cell(b), r: cell(r))
        // 1e18 = limbs [0, 0, 1]
        if r[1] != 3 || r[3] != 0 || r[4] != 0 || r[5] != 1 {
            return "mul 1e9*1e9 limbs failed len=\(r[1]) L0=\(r[3]) L1=\(r[4]) L2=\(r[5])"
        }

        isqrt(a: cell(r), r: cell(q))
        if getU(q) != biBase { return "isqrt(1e18) failed (\(String(describing: getU(q))))" }

        setU(a, 100); setU(b, 7)
        divmod(num: cell(a), den: cell(b), quot: cell(q), rem: cell(rem))
        if getU(q) != 14 || getU(rem) != 2 {
            return "divmod 100/7 failed q=\(String(describing: getU(q))) r=\(String(describing: getU(rem)))"
        }

        if capacityOverflows != 0 {
            return "unexpected capacity overflow during self-test"
        }
        return nil
    }
}

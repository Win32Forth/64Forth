//
//  FloatHost.swift
//  64Forth
//
//  Public domain.
//
//  ANS floating-point (IEEE 64-bit) — ported from TZForthFloat.swift.
//  Separate 16-deep F-stack; ops invoked via kernel float_op multiplex.
//  Word headers live in the FP vocabulary (not FORTH).
//

import Foundation

/// Float-op multiplex codes (must match forth.s FOP_*).
enum FloatOpCode: Int64 {
    case fdepth = 1
    case fdrop = 2
    case fdup = 3
    case fswap = 4
    case fover = 5
    case frot = 6
    case fplus = 7
    case fminus = 8
    case fstar = 9
    case fslash = 10
    case fnegate = 11
    case fabs = 12
    case fmax = 13
    case fmin = 14
    case fzeroeq = 15
    case fzerolt = 16
    case flt = 17
    case fgt = 18
    case feq = 19
    case fne = 20
    case ftilde = 21
    case fat = 22          // F@  a = addr
    case fstore = 23       // F!  a = addr
    case sfat = 24
    case sfstore = 25
    case dfat = 26
    case dfstore = 27
    case stf = 28          // S>F a = n
    case fts = 29          // F>S → o1
    case dtf = 30          // D>F a=lo b=hi
    case ftd = 31          // F>D → o1=lo o2=hi
    case tofloat = 32      // >FLOAT ptr=c-addr b=u → o1=flag
    case fdot = 33
    case fsdot = 34
    case fedot = 35
    case precision = 36    // → o1
    case setprecision = 37 // a = u
    case represent = 38    // a=caddr b=u → o1=k o2=sign o3=exact
    case floats = 39       // a=n → o1
    case floatplus = 40    // a=addr → o1
    case sfloats = 41
    case sfloatplus = 42
    case dfloats = 43
    case dfloatplus = 44
    case fsqrt = 45
    case fpow = 46
    case fexp = 47
    case fexpm1 = 48
    case fln = 49
    case flnp1 = 50
    case flog = 51
    case falog = 52
    case fsin = 53
    case fcos = 54
    case ftan = 55
    case fasin = 56
    case facos = 57
    case fatan = 58
    case fatan2 = 59
    case fsincos = 60      // pushes sin then cos
    case fsinh = 61
    case fcosh = 62
    case ftanh = 63
    case fasinh = 64
    case facosh = 65
    case fatanh = 66
    case floor = 67
    case fround = 68
    case fmod = 69
    case falign = 70       // a=addr → o1
    case sfalign = 71
    case dfalign = 72
    case faligned = 73     // a=addr → o1 flag
    case sfaligned = 74
    case dfaligned = 75
    case parseLit = 100    // ptr + b=len → o1=ok o2=bits (no fpush)
    case fpushBits = 101   // a=bits
    case fpopBits = 102    // → o1=bits
    case fdepthRaw = 103   // same as fdepth
}

final class FloatHost {
    static let shared = FloatHost()

    static let fstackSize = 16
    private var stack: [Double] = []
    private(set) var precision: Int = 6

    /// Character emit (set by KernelBridge to console path).
    var onEmit: ((String) -> Void)?

    private init() {}

    func reset() {
        stack.removeAll(keepingCapacity: true)
        precision = 6
    }

    // MARK: - F-stack

    private func fpush(_ v: Double) {
        if stack.count >= Self.fstackSize {
            // Soft: drop oldest policy not ANS; just ignore push on overflow
            return
        }
        stack.append(v)
    }

    private func fpop() -> Double {
        guard !stack.isEmpty else { return 0 }
        return stack.removeLast()
    }

    private func fpeek(_ u: Int) -> Double {
        let i = stack.count - 1 - u
        guard i >= 0, i < stack.count else { return 0 }
        return stack[i]
    }

    var fdepth: Int { stack.count }

    // MARK: - Memory (real host pointers)

    private func readFloat(at addr: Int64) -> Double {
        guard addr != 0,
              let p = UnsafeRawPointer(bitPattern: UInt(bitPattern: Int(addr))) else { return 0 }
        var bits: UInt64 = 0
        memcpy(&bits, p, 8)
        return Double(bitPattern: bits)
    }

    private func writeFloat(at addr: Int64, _ value: Double) {
        guard addr != 0,
              let p = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: Int(addr))) else { return }
        var bits = value.bitPattern
        memcpy(p, &bits, 8)
    }

    private func readSingle(at addr: Int64) -> Double {
        guard addr != 0,
              let p = UnsafeRawPointer(bitPattern: UInt(bitPattern: Int(addr))) else { return 0 }
        var bits: UInt32 = 0
        memcpy(&bits, p, 4)
        return Double(Float(bitPattern: bits))
    }

    private func writeSingle(at addr: Int64, _ value: Double) {
        guard addr != 0,
              let p = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: Int(addr))) else { return }
        var bits = Float(value).bitPattern
        memcpy(p, &bits, 4)
    }

    static func floatToBits(_ v: Double) -> Int64 {
        Int64(bitPattern: v.bitPattern)
    }

    static func bitsToFloat(_ bits: Int64) -> Double {
        Double(bitPattern: UInt64(bitPattern: bits))
    }

    // MARK: - Parse (from TZForth)

    func looksLikeFloatToken(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let upper = name.uppercased()
        if upper.contains("E") { return true }
        if upper.contains(".") {
            // Trailing-only "." is a double number, not a float
            if upper.hasSuffix(".") && upper.filter({ $0 == "." }).count == 1 {
                let stem = String(upper.dropLast())
                if !stem.isEmpty && stem.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) {
                    return false
                }
            }
            return true
        }
        if upper.hasSuffix("D") {
            let stem = String(upper.dropLast())
            return !stem.isEmpty && stem.allSatisfy { $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
        }
        return false
    }

    func parseTextFloat(_ name: String) -> Double? {
        guard looksLikeFloatToken(name) else { return nil }
        return parseFloatString(name)
    }

    func parseFloatString(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("+") { s = String(s.dropFirst()) }
        guard !s.isEmpty else { return nil }
        var upper = s.uppercased()
        if upper.hasSuffix("D") {
            upper = String(upper.dropLast()) + "E0"
            s = String(s.dropLast()) + "e0"
        }
        if upper.hasSuffix("E") {
            s += "0"
            upper += "0"
        }
        if let v = Double(s) { return v }
        if let v = Double(upper) { return v }
        return nil
    }

    /// ANS >FLOAT
    func parseGreaterFloatString(_ text: String) -> Double? {
        guard !text.isEmpty else { return 0 }
        if text.allSatisfy({ $0.isWhitespace }) { return 0 }
        if text.contains(where: { $0.isWhitespace }) { return nil }

        let chars = Array(text)
        var i = 0
        var sign: Double = 1
        if i < chars.count, chars[i] == "+" || chars[i] == "-" {
            if chars[i] == "-" { sign = -1 }
            i += 1
        }
        guard i < chars.count else { return nil }

        var intPart: Double = 0
        var fracPart: Double = 0
        var fracDivisor: Double = 1
        var hasInt = false
        var hasFrac = false

        if chars[i].isNumber {
            hasInt = true
            while i < chars.count, chars[i].isNumber {
                intPart = intPart * 10 + Double(chars[i].wholeNumberValue ?? 0)
                i += 1
            }
        }
        if i < chars.count, chars[i] == "." {
            i += 1
            while i < chars.count, chars[i].isNumber {
                hasFrac = true
                fracPart = fracPart * 10 + Double(chars[i].wholeNumberValue ?? 0)
                fracDivisor *= 10
                i += 1
            }
        }
        guard hasInt || hasFrac else { return nil }
        var value = sign * (intPart + fracPart / fracDivisor)

        if i < chars.count {
            let marker = chars[i]
            if marker == "e" || marker == "E" || marker == "d" || marker == "D" {
                i += 1
                var expSign = 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                    if chars[i] == "-" { expSign = -1 }
                    i += 1
                }
                var expValue = 0
                while i < chars.count, chars[i].isNumber {
                    expValue = expValue * 10 + (chars[i].wholeNumberValue ?? 0)
                    i += 1
                }
                value *= pow(10.0, Double(expSign * expValue))
            } else if marker == "+" || marker == "-" {
                let expSign = marker == "-" ? -1 : 1
                i += 1
                guard i < chars.count, chars[i].isNumber else { return nil }
                var expValue = 0
                while i < chars.count, chars[i].isNumber {
                    expValue = expValue * 10 + (chars[i].wholeNumberValue ?? 0)
                    i += 1
                }
                value *= pow(10.0, Double(expSign * expValue))
            } else {
                return nil
            }
        }
        guard i == chars.count else { return nil }
        return value
    }

    // MARK: - Format (TZForth)

    private func roundLeadingDigits(_ digits: String, keep: Int) -> String {
        guard keep > 0 else { return "" }
        let chars = Array(digits)
        guard !chars.isEmpty else { return "" }
        var lead = Array(chars.prefix(keep))
        if chars.count > keep, chars[keep] >= Character("5") {
            for i in (0..<lead.count).reversed() {
                if lead[i] == Character("9") {
                    lead[i] = Character("0")
                } else if let v = lead[i].asciiValue {
                    lead[i] = Character(UnicodeScalar(v + 1))
                    return String(lead)
                }
            }
            return "1" + String(repeating: "0", count: keep)
        }
        return String(lead)
    }

    private func forthFmMod(_ d: Int, _ divisor: Int) -> (remainder: Int, quotient: Int) {
        guard divisor != 0 else { return (0, 0) }
        var quotient = d / divisor
        var remainder = d % divisor
        if (d ^ divisor) < 0 && remainder != 0 {
            quotient -= 1
            remainder += divisor
        }
        return (remainder, quotient)
    }

    private func floatRepresentSignificand(
        _ value: Double,
        u: Int,
        writeTo buffer: Int64?
    ) -> (k: Int, charFlag: Int, exact: Bool, digits: [UInt8]) {
        let width = max(1, u)
        var scratch = [UInt8](repeating: UInt8(ascii: "0"), count: width)
        if let buffer, buffer != 0 {
            let p = UnsafeMutablePointer<UInt8>(bitPattern: UInt(bitPattern: Int(buffer)))
            for i in 0..<width { p?[i] = UInt8(ascii: "0") }
        }
        if value.isNaN || value.isInfinite {
            return (0, 0, false, scratch)
        }
        if value == 0 {
            scratch[0] = UInt8(ascii: "0")
            if let buffer, buffer != 0 {
                UnsafeMutablePointer<UInt8>(bitPattern: UInt(bitPattern: Int(buffer)))?.pointee = UInt8(ascii: "0")
            }
            return (0, 0, true, scratch)
        }
        let absValue = abs(value)
        var k = Int(floor(log10(absValue))) + 1
        let scale = pow(10.0, Double(width - k))
        var significand = (absValue * scale).rounded(.toNearestOrAwayFromZero)
        let upper = pow(10.0, Double(width))
        if significand >= upper {
            significand /= 10
            k += 1
        }
        let digits = String(format: "%0\(width).0f", significand)
        let chars = Array(digits.utf8.prefix(width))
        for (i, b) in chars.enumerated() {
            scratch[i] = b
            if let buffer, buffer != 0 {
                UnsafeMutablePointer<UInt8>(bitPattern: UInt(bitPattern: Int(buffer)))?[i] = b
            }
        }
        let charFlag = value < 0 ? -1 : 0
        return (k, charFlag, true, scratch)
    }

    private func floatRepresentScratch(_ value: Double) -> (k: Int, charFlag: Int, exact: Bool, digits: [UInt8]) {
        floatRepresentSignificand(value, u: max(1, precision), writeTo: nil)
    }

    func formatFloatOutput(_ value: Double) -> String {
        if value.isNaN { return "NaN " }
        if value.isInfinite {
            return value.sign == .minus ? "-Infinity " : "Infinity "
        }
        let rep = floatRepresentScratch(value)
        if !rep.exact {
            let text = String(bytes: rep.digits, encoding: .ascii) ?? ""
            let trimmed = text.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            return (rep.charFlag != 0 ? "-" : "") + trimmed + " "
        }
        let prec = max(1, precision)
        let k = rep.k
        let digits = String(bytes: rep.digits, encoding: .ascii) ?? ""
        var out = rep.charFlag != 0 ? "-" : ""
        if k <= 0 {
            out += "0."
            if k < 0 { out += String(repeating: "0", count: -k) }
            let sigShow = max(0, prec + k)
            if sigShow > 0 { out += roundLeadingDigits(digits, keep: sigShow) }
        } else {
            let lead = min(k, prec)
            out += String(digits.prefix(lead))
            out += "."
            if k < prec {
                var frac = String(digits.dropFirst(k))
                while frac.last == "0" { frac.removeLast() }
                out += frac
            }
        }
        return out + " "
    }

    private func formatFloatEngineering(_ value: Double) -> String {
        if value.isNaN { return "NaN " }
        if value.isInfinite {
            return value.sign == .minus ? "-Infinity " : "Infinity "
        }
        let rep = floatRepresentScratch(value)
        if !rep.exact {
            let text = String(bytes: rep.digits, encoding: .ascii) ?? ""
            let trimmed = text.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            return (rep.charFlag != 0 ? "-" : "") + trimmed + " "
        }
        let digits = String(bytes: rep.digits, encoding: .ascii) ?? ""
        let exp = rep.k - 1
        var out = rep.charFlag != 0 ? "-" : ""
        if !digits.isEmpty {
            out += String(digits.prefix(1))
            out += "."
            if digits.count > 1 { out += String(digits.dropFirst()) }
        }
        out += "E\(exp)"
        return out + " "
    }

    private func formatFloatFixed(_ value: Double) -> String {
        if value.isNaN { return "NaN " }
        if value.isInfinite {
            return value.sign == .minus ? "-Infinity " : "Infinity "
        }
        let rep = floatRepresentScratch(value)
        if !rep.exact {
            let text = String(bytes: rep.digits, encoding: .ascii) ?? ""
            let trimmed = text.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            return (rep.charFlag != 0 ? "-" : "") + trimmed + " "
        }
        let prec = max(1, precision)
        let k = rep.k
        let n = k - 1
        let (rem, quot) = forthFmMod(n, 3)
        let engExp = quot * 3
        let leadDigits = rem + 1
        let digits = String(bytes: rep.digits, encoding: .ascii) ?? ""
        var out = rep.charFlag != 0 ? "-" : ""
        let typeCount = min(leadDigits, prec)
        if leadDigits > 0 {
            out += String(digits.prefix(typeCount))
        } else {
            out += "0"
        }
        if leadDigits > typeCount {
            out += String(repeating: "0", count: leadDigits - typeCount)
        }
        out += "."
        let fracStart = max(0, leadDigits)
        if fracStart < prec {
            out += String(digits.dropFirst(fracStart))
        }
        out += "E\(engExp)"
        return out + " "
    }

    private func floatTilde(_ r1: Double, _ r2: Double, _ u: Double) -> Bool {
        if u == 0 { return r1.bitPattern == r2.bitPattern }
        let diff = abs(r1 - r2)
        if diff.isNaN { return false }
        if u > 0 { return diff < u }
        let limit = abs(u) * (abs(r1) + abs(r2))
        if limit.isNaN { return false }
        return diff < limit
    }

    private func floatAtan2(y: Double, x: Double) -> Double {
        if y.isNaN || x.isNaN { return .nan }
        return atan2(y, x)
    }

    private func emit(_ s: String) {
        onEmit?(s)
    }

    private func flag(_ b: Bool) -> Int64 { b ? -1 : 0 }

    // MARK: - Multiplex

    /// Returns ior (0=ok). Results in o1/o2/o3.
    @discardableResult
    func dispatch(
        op: Int64,
        a: Int64,
        b: Int64,
        c: Int64,
        d: Int64,
        ptr: UnsafeMutableRawPointer?,
        o1: UnsafeMutablePointer<Int64>?,
        o2: UnsafeMutablePointer<Int64>?,
        o3: UnsafeMutablePointer<Int64>?
    ) -> Int64 {
        guard let code = FloatOpCode(rawValue: op) else { return -1 }
        o1?.pointee = 0
        o2?.pointee = 0
        o3?.pointee = 0

        switch code {
        case .fdepth, .fdepthRaw:
            o1?.pointee = Int64(fdepth)
        case .fdrop:
            _ = fpop()
        case .fdup:
            fpush(fpeek(0))
        case .fswap:
            let r1 = fpop(); let r2 = fpop()
            fpush(r1); fpush(r2)
        case .fover:
            fpush(fpeek(1))
        case .frot:
            let r3 = fpop(); let r2 = fpop(); let r1 = fpop()
            fpush(r2); fpush(r3); fpush(r1)
        case .fplus:
            let r2 = fpop(); let r1 = fpop(); fpush(r1 + r2)
        case .fminus:
            let r2 = fpop(); let r1 = fpop(); fpush(r1 - r2)
        case .fstar:
            let r2 = fpop(); let r1 = fpop(); fpush(r1 * r2)
        case .fslash:
            let r2 = fpop(); let r1 = fpop(); fpush(r1 / r2)
        case .fnegate:
            fpush(-fpop())
        case .fabs:
            fpush(abs(fpop()))
        case .fmax:
            let r2 = fpop(); let r1 = fpop(); fpush(max(r1, r2))
        case .fmin:
            let r2 = fpop(); let r1 = fpop(); fpush(min(r1, r2))
        case .fzeroeq:
            o1?.pointee = flag(fpop() == 0)
        case .fzerolt:
            o1?.pointee = flag(fpop() < 0)
        case .flt:
            let r2 = fpop(); let r1 = fpop(); o1?.pointee = flag(r1 < r2)
        case .fgt:
            let r2 = fpop(); let r1 = fpop(); o1?.pointee = flag(r1 > r2)
        case .feq:
            let r2 = fpop(); let r1 = fpop(); o1?.pointee = flag(r1 == r2)
        case .fne:
            let r2 = fpop(); let r1 = fpop(); o1?.pointee = flag(r1 != r2)
        case .ftilde:
            let u = fpop(); let r2 = fpop(); let r1 = fpop()
            o1?.pointee = flag(floatTilde(r1, r2, u))
        case .fat, .dfat:
            fpush(readFloat(at: a))
        case .fstore, .dfstore:
            writeFloat(at: a, fpop())
        case .sfat:
            fpush(readSingle(at: a))
        case .sfstore:
            writeSingle(at: a, fpop())
        case .stf:
            fpush(Double(a))
        case .fts:
            o1?.pointee = Int64(fpop().rounded(.towardZero))
        case .dtf:
            // lo a, hi b as signed double-cell → approximate via Double
            let lo = UInt64(bitPattern: a)
            let hi = b
            // Build Int128-ish: hi<<64|lo for signed
            if hi == 0 || hi == -1 {
                fpush(Double(a))
            } else {
                fpush(Double(hi) * 18446744073709551616.0 + Double(lo))
            }
        case .ftd:
            let r = fpop().rounded(.towardZero)
            let v: Int64
            if r >= Double(Int64.max) { v = Int64.max }
            else if r <= Double(Int64.min) { v = Int64.min }
            else { v = Int64(r) }
            o1?.pointee = v
            o2?.pointee = r < 0 ? -1 : 0
        case .tofloat:
            let u = Int(b)
            var bytes = [UInt8]()
            if let ptr, u > 0 {
                let p = ptr.assumingMemoryBound(to: UInt8.self)
                for i in 0..<u { bytes.append(p[i]) }
            }
            let text = String(bytes: bytes, encoding: .utf8) ?? ""
            if let v = parseGreaterFloatString(text) {
                fpush(v)
                o1?.pointee = -1
            } else {
                o1?.pointee = 0
            }
        case .fdot:
            emit(formatFloatOutput(fpop()))
        case .fsdot:
            emit(formatFloatEngineering(fpop()))
        case .fedot:
            emit(formatFloatFixed(fpop()))
        case .precision:
            o1?.pointee = Int64(precision)
        case .setprecision:
            precision = max(1, Int(a))
        case .represent:
            let r = fpop()
            let res = floatRepresentSignificand(r, u: Int(b), writeTo: a)
            o1?.pointee = Int64(res.k)
            o2?.pointee = Int64(res.charFlag)
            o3?.pointee = res.exact ? -1 : 0
        case .floats, .dfloats:
            o1?.pointee = a &* 8
        case .sfloats:
            o1?.pointee = a &* 4
        case .floatplus, .dfloatplus:
            o1?.pointee = a &+ 8
        case .sfloatplus:
            o1?.pointee = a &+ 4
        case .fsqrt:
            fpush(sqrt(fpop()))
        case .fpow:
            let r2 = fpop(); let r1 = fpop(); fpush(pow(r1, r2))
        case .fexp:
            fpush(exp(fpop()))
        case .fexpm1:
            fpush(expm1(fpop()))
        case .fln:
            fpush(log(fpop()))
        case .flnp1:
            fpush(log1p(fpop()))
        case .flog:
            fpush(log10(fpop()))
        case .falog:
            fpush(pow(10.0, fpop()))
        case .fsin:
            fpush(sin(fpop()))
        case .fcos:
            fpush(cos(fpop()))
        case .ftan:
            fpush(tan(fpop()))
        case .fasin:
            fpush(asin(fpop()))
        case .facos:
            fpush(acos(fpop()))
        case .fatan:
            fpush(atan(fpop()))
        case .fatan2:
            let x = fpop(); let y = fpop(); fpush(floatAtan2(y: y, x: x))
        case .fsincos:
            let r = fpop()
            fpush(sin(r))
            fpush(cos(r))
        case .fsinh:
            fpush(sinh(fpop()))
        case .fcosh:
            fpush(cosh(fpop()))
        case .ftanh:
            fpush(tanh(fpop()))
        case .fasinh:
            fpush(asinh(fpop()))
        case .facosh:
            fpush(acosh(fpop()))
        case .fatanh:
            fpush(atanh(fpop()))
        case .floor:
            fpush(Foundation.floor(fpop()))
        case .fround:
            fpush(fpop().rounded())
        case .fmod:
            let r2 = fpop(); let r1 = fpop()
            fpush(r1.truncatingRemainder(dividingBy: r2))
        case .falign, .dfalign:
            o1?.pointee = (a + 7) & ~7
        case .sfalign:
            o1?.pointee = (a + 3) & ~3
        case .faligned, .dfaligned:
            o1?.pointee = flag((a & 7) == 0)
        case .sfaligned:
            o1?.pointee = flag((a & 3) == 0)
        case .parseLit:
            let u = Int(b)
            var bytes = [UInt8]()
            if let ptr, u > 0 {
                let p = ptr.assumingMemoryBound(to: UInt8.self)
                for i in 0..<u { bytes.append(p[i]) }
            }
            let text = String(bytes: bytes, encoding: .utf8) ?? ""
            if let v = parseTextFloat(text) {
                o1?.pointee = 1
                o2?.pointee = Self.floatToBits(v)
            } else {
                o1?.pointee = 0
            }
        case .fpushBits:
            fpush(Self.bitsToFloat(a))
        case .fpopBits:
            o1?.pointee = Self.floatToBits(fpop())
        }
        return 0
    }
}

import Foundation

/// The file name the legacy app gave an avatar: `MD5(lowercased pseudo)` as 32 lower-case hex digits, in the same
/// `Caches/cache/avatars` folder (writer `ParseMessagesOperation.m:340-347`, reader `MPListView.swift:911-917`, both
/// @ `87fe0d1c`). MD5 here is a file name only, never a security measure: a name that collides with another pseudo's
/// at worst shows that pseudo's avatar, so the digest is implemented in the engine (no CryptoKit on Linux, no dependency).
enum LegacyAvatarName {
    /// The names to look for, most likely first. Legacy lower-cased the pseudo exactly as the page printed it, with any
    /// U+200B HFR inserts into long pseudos; `AvatarCache` strips them, so both spellings are tried.
    static func candidates(forPseudo pseudo: String) -> [String] {
        let raw = pseudo.lowercased()
        let stripped = pseudo.filter { $0 != "\u{200B}" }.lowercased()
        var names: [String] = []
        for key in [raw, stripped] where !key.isEmpty {
            let name = hex(md5(Array(key.utf8)))
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        return String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }

    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    /// RFC 1321. The constants are the sines' fractional parts, as the RFC defines them.
    private static let constants: [UInt32] = (0..<64).map { (index: Int) -> UInt32 in
        let value: Double = abs(sin(Double(index + 1))) * 4_294_967_296
        return UInt32(value)
    }

    static func md5(_ message: [UInt8]) -> [UInt8] {
        var a0: UInt32 = 0x6745_2301
        var b0: UInt32 = 0xefcd_ab89
        var c0: UInt32 = 0x98ba_dcfe
        var d0: UInt32 = 0x1032_5476
        var padded = message + [0x80]
        while padded.count % 64 != 56 { padded.append(0) }
        let bitLength = UInt64(message.count) &* 8
        for shift in 0..<8 { padded.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(8 * shift))) }
        for chunk in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 16)
            for index in 0..<16 {
                let base = chunk + index * 4
                let b0 = UInt32(padded[base])
                let b1 = UInt32(padded[base + 1]) << 8
                let b2 = UInt32(padded[base + 2]) << 16
                let b3 = UInt32(padded[base + 3]) << 24
                words[index] = b0 | b1 | b2 | b3
            }
            var a = a0, b = b0, c = c0, d = d0
            for step in 0..<64 {
                var f: UInt32
                var g: Int
                switch step {
                case 0..<16: f = (b & c) | (~b & d); g = step
                case 16..<32: f = (d & b) | (~d & c); g = (5 * step + 1) % 16
                case 32..<48: f = b ^ c ^ d; g = (3 * step + 5) % 16
                default: f = c ^ (b | ~d); g = (7 * step) % 16
                }
                f = f &+ a &+ constants[step] &+ words[g]
                a = d; d = c; c = b
                b = b &+ ((f << shifts[step]) | (f >> (32 - shifts[step])))
            }
            a0 = a0 &+ a; b0 = b0 &+ b; c0 = c0 &+ c; d0 = d0 &+ d
        }
        var digest: [UInt8] = []
        for word in [a0, b0, c0, d0] {
            for shift in 0..<4 { digest.append(UInt8(truncatingIfNeeded: word >> UInt32(8 * shift))) }
        }
        return digest
    }
}

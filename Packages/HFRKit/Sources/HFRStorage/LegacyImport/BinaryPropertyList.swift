import Foundation

/// A node of a binary property list, keyed-archive references (`UID`) included.
///
/// `PropertyListSerialization` returns those references as an opaque class on both Darwin and Linux, so the legacy
/// `NSKeyedArchiver` files (`smiley_favorites_cache2`, `SmileyCache.m:388-439`) are read with this small reader of the
/// public `bplist00` format instead (CoreFoundation `CFBinaryPList.c`): no unarchiver, no class is instantiated.
indirect enum PlistNode: Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case date(Date)
    case data(Data)
    case string(String)
    case uid(Int)
    case array([PlistNode])
    case dictionary([String: PlistNode])
}

/// Why a binary property list could not be read. Carries no byte of the file.
enum BinaryPlistError: Error, Equatable {
    case notBinaryPlist
    case malformed
}

/// Reads a `bplist00` document into `PlistNode`s.
struct BinaryPropertyList {
    private let bytes: [UInt8]
    private let offsets: [Int]
    private let referenceSize: Int
    private var depth = 0
    private var visited = 0

    /// Upper bound on nested containers: a legacy archive nests three levels; a cycle stops here.
    private static let maximumDepth = 64
    /// Floor of the bound on objects read, references counted each time: a file whose containers list the same
    /// container many times (a shared-reference graph) would otherwise be read an exponential number of times.
    static let minimumNodeBudget = 100_000
    /// Reads allowed per object of the file above the floor. A keyed archive reads each object about 4.5 times
    /// (shared key strings and class references are read again for every favourite), so a legitimate archive of any
    /// size stays far under it, while a shared-reference graph exceeds it after a few levels.
    static let nodesPerObject = 20

    /// Parses `data` and returns its top object.
    static func parse(_ data: Data) throws(BinaryPlistError) -> PlistNode {
        var reader = try BinaryPropertyList(data: data)
        return try reader.topObject()
    }

    private let topIndex: Int

    private init(data: Data) throws(BinaryPlistError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 40, bytes.starts(with: Array("bplist00".utf8)) else { throw .notBinaryPlist }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6])
        let referenceSize = Int(bytes[trailer + 7])
        let count = try Self.integer(bytes, at: trailer + 8, size: 8)
        let top = try Self.integer(bytes, at: trailer + 16, size: 8)
        let tableStart = try Self.integer(bytes, at: trailer + 24, size: 8)
        guard (1...8).contains(offsetSize), (1...8).contains(referenceSize), count > 0, top < count,
              tableStart >= 8, count <= (trailer - tableStart) / offsetSize else { throw .malformed }
        var offsets: [Int] = []
        offsets.reserveCapacity(count)
        for index in 0..<count {
            let offset = try Self.integer(bytes, at: tableStart + index * offsetSize, size: offsetSize)
            guard offset >= 8, offset < tableStart else { throw .malformed }
            offsets.append(offset)
        }
        self.bytes = bytes
        self.offsets = offsets
        self.referenceSize = referenceSize
        self.topIndex = top
    }

    private mutating func topObject() throws(BinaryPlistError) -> PlistNode {
        try object(at: topIndex)
    }

    private mutating func object(at index: Int) throws(BinaryPlistError) -> PlistNode {
        guard index >= 0, index < offsets.count else { throw .malformed }
        visited += 1
        guard visited <= max(Self.minimumNodeBudget, Self.nodesPerObject * offsets.count) else { throw .malformed }
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw .malformed }
        let start = offsets[index]
        let kind = bytes[start] >> 4
        let info = Int(bytes[start] & 0x0F)
        switch kind {
        case 0xA, 0xD: return try container(kind: kind, info: info, at: start)
        case 0x4, 0x5, 0x6: return try bytesObject(kind: kind, info: info, at: start)
        default: return try scalar(kind: kind, info: info, at: start)
        }
    }

    /// Null, booleans, integers, reals, dates and keyed-archive references.
    private func scalar(kind: UInt8, info: Int, at start: Int) throws(BinaryPlistError) -> PlistNode {
        switch (kind, info) {
        case (0x0, 0x0): return .null
        case (0x0, 0x8): return .bool(false)
        case (0x0, 0x9): return .bool(true)
        case (0x1, 0...3): return .integer(try Self.signedInteger(bytes, at: start + 1, size: 1 << info))
        case (0x2, _): return .real(try Self.real(bytes, at: start + 1, size: 1 << min(info, 4)))
        case (0x3, _): return .date(Date(timeIntervalSinceReferenceDate: try Self.real(bytes, at: start + 1, size: 8)))
        case (0x8, _): return .uid(try Self.integer(bytes, at: start + 1, size: info + 1))
        default: throw .malformed
        }
    }

    /// Data, ASCII strings and UTF-16 strings.
    private func bytesObject(kind: UInt8, info: Int, at start: Int) throws(BinaryPlistError) -> PlistNode {
        let (length, first) = try self.length(info: info, at: start)
        switch kind {
        case 0x4:
            return .data(Data(try slice(first, length)))
        case 0x5:
            guard let text = String(bytes: try slice(first, length), encoding: .ascii) else { throw .malformed }
            return .string(text)
        default:
            let raw = Array(try slice(first, length * 2))
            let units = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
            return .string(String(decoding: units, as: UTF16.self))
        }
    }

    /// Arrays and dictionaries (string keys only, as every legacy archive).
    private mutating func container(kind: UInt8, info: Int, at start: Int) throws(BinaryPlistError) -> PlistNode {
        let (count, first) = try self.length(info: info, at: start)
        if kind == 0xA {
            var items: [PlistNode] = []
            for position in 0..<count {
                items.append(try object(at: try reference(first, position)))
            }
            return .array(items)
        }
        var entries: [String: PlistNode] = [:]
        for position in 0..<count {
            guard case .string(let key) = try object(at: try reference(first, position)) else { throw .malformed }
            entries[key] = try object(at: try reference(first, count + position))
        }
        return .dictionary(entries)
    }

    /// The element count of a container or string, and where its content starts.
    private func length(info: Int, at start: Int) throws(BinaryPlistError) -> (Int, Int) {
        guard info == 0x0F else { return (info, start + 1) }
        guard start + 1 < bytes.count, bytes[start + 1] >> 4 == 0x1 else { throw .malformed }
        let size = 1 << Int(bytes[start + 1] & 0x0F)
        guard size <= 8 else { throw .malformed }
        let length = try Self.integer(bytes, at: start + 2, size: size)
        guard length <= bytes.count else { throw .malformed }
        return (length, start + 2 + size)
    }

    private func reference(_ first: Int, _ position: Int) throws(BinaryPlistError) -> Int {
        try Self.integer(bytes, at: first + position * referenceSize, size: referenceSize)
    }

    private func slice(_ start: Int, _ length: Int) throws(BinaryPlistError) -> ArraySlice<UInt8> {
        guard length >= 0, start >= 0, start <= bytes.count - length else { throw .malformed }
        return bytes[start..<(start + length)]
    }

    private static func integer(_ bytes: [UInt8], at start: Int, size: Int) throws(BinaryPlistError) -> Int {
        guard size >= 1, size <= 8, start >= 0, start <= bytes.count - size else { throw .malformed }
        var value: UInt64 = 0
        for byte in bytes[start..<(start + size)] { value = value << 8 | UInt64(byte) }
        guard value <= UInt64(Int.max) else { throw .malformed }
        return Int(value)
    }

    private static func signedInteger(_ bytes: [UInt8], at start: Int, size: Int) throws(BinaryPlistError) -> Int {
        guard start >= 0, start <= bytes.count - size else { throw .malformed }
        var value: UInt64 = 0
        for byte in bytes[start..<(start + size)] { value = value << 8 | UInt64(byte) }
        // Eight-byte integers are signed in the format; shorter ones are unsigned.
        return size == 8 ? Int(Int64(bitPattern: value)) : Int(value)
    }

    private static func real(_ bytes: [UInt8], at start: Int, size: Int) throws(BinaryPlistError) -> Double {
        guard size == 4 || size == 8, start >= 0, start <= bytes.count - size else { throw .malformed }
        var value: UInt64 = 0
        for byte in bytes[start..<(start + size)] { value = value << 8 | UInt64(byte) }
        return size == 8 ? Double(bitPattern: value) : Double(Float(bitPattern: UInt32(value)))
    }
}

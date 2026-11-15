import Foundation
import HFRModels
@testable import HFRClient

/// A forum side that answers from scripts and records every call: no `HFRSession` exists in these tests, so no request can
/// leave the process.
actor ScriptedMPStorageRemote: MPStorageRemote {
    enum Call: Equatable {
        case find
        case read(Int)
        case save(ours: String, base: String?, post: Int)
        case create
    }

    private(set) var calls: [Call] = []
    var finds: [Result<Int?, MPStorageTransportError>] = []
    var reads: [Result<MPStorageSnapshot, MPStorageTransportError>] = []
    var saves: [Result<MPStorageSaveResult, MPStorageTransportError>] = []
    var creations: [Result<MPStorageCreation, MPStorageTransportError>] = []
    /// Set by `hold()`: the next read waits until `release()`.
    private var gate: CheckedContinuation<Void, Never>?
    private var holdsNextRead = false
    private var waitingForHold: [CheckedContinuation<Void, Never>] = []

    init(
        finds: [Result<Int?, MPStorageTransportError>] = [],
        reads: [Result<MPStorageSnapshot, MPStorageTransportError>] = [],
        saves: [Result<MPStorageSaveResult, MPStorageTransportError>] = [],
        creations: [Result<MPStorageCreation, MPStorageTransportError>] = []
    ) {
        self.finds = finds
        self.reads = reads
        self.saves = saves
        self.creations = creations
    }

    func findThread() async throws(MPStorageTransportError) -> Int? {
        calls.append(.find)
        return try Self.next(&finds).get()
    }

    func read(post: Int) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        calls.append(.read(post))
        if holdsNextRead {
            holdsNextRead = false
            await withCheckedContinuation { continuation in
                gate = continuation
                waitingForHold.forEach { $0.resume() }
                waitingForHold = []
            }
        }
        return try Self.next(&reads).get()
    }

    func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        let oursText = (try? MPStorageCodec.encodeForWriting(ours)) ?? "?"
        let baseText = base.flatMap { try? MPStorageCodec.encodeForWriting($0) }
        calls.append(.save(ours: oursText, base: baseText, post: location.post))
        return try Self.next(&saves).get()
    }

    func create(stamp: MPStorageStamp) async throws(MPStorageTransportError) -> MPStorageCreation {
        calls.append(.create)
        return try Self.next(&creations).get()
    }

    /// The next read waits for `release()`.
    func hold() { holdsNextRead = true }

    /// Returns once a held read is waiting.
    func waitUntilHeld() async {
        guard gate == nil else { return }
        await withCheckedContinuation { waitingForHold.append($0) }
    }

    /// Lets the held read go on.
    func release() {
        gate?.resume()
        gate = nil
    }

    private static func next<Value>(_ script: inout [Result<Value, MPStorageTransportError>]) -> Result<Value, MPStorageTransportError> {
        script.isEmpty ? .failure(.unexpectedPage) : script.removeFirst()
    }
}

/// The copy in memory, with the number of saves.
actor InMemoryMPStorageSyncPersistence: MPStorageSyncPersistence {
    private(set) var stored: MPStorageSyncCopy
    private(set) var saveCount = 0
    var failsSaves = false

    init(_ copy: MPStorageSyncCopy = MPStorageSyncCopy()) {
        stored = copy
    }

    func load() async throws(MPStorageSyncError) -> MPStorageSyncCopy { stored }

    func save(_ copy: MPStorageSyncCopy) async throws(MPStorageSyncError) {
        guard !failsSaves else { throw .storage(reason: "disk full") }
        stored = copy
        saveCount += 1
    }

    func failSaves() { failsSaves = true }
}

/// Documents and snapshots of the sync tests, on LOT-052's captured document.
enum MPStorageSyncFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let stamp = MPStorageStamp(date: now)

    static func location(_ post: Int = MPStorageCapture.post) -> MPStorageLocation {
        MPStorageLocation(post: post, numreponse: MPStorageCapture.numreponse, editURL: URL(fileURLWithPath: "/edit"))
    }

    static func document(blocking names: [String] = [], flags: [MPStorageMPFlag] = []) throws -> MPStorageDocument {
        var document = try MPStorageCodec.decode(MPStorageCapture.storedText)
        for name in names { _ = try document.addBlocklistEntry(username: name, stamp: stamp) }
        for flag in flags { _ = try document.upsertMPFlag(flag, stamp: stamp) }
        return document
    }

    static func text(blocking names: [String] = [], flags: [MPStorageMPFlag] = []) throws -> String {
        try MPStorageCodec.encodeForWriting(try document(blocking: names, flags: flags))
    }

    static func snapshot(blocking names: [String] = [], post: Int = MPStorageCapture.post) throws -> MPStorageSnapshot {
        MPStorageSnapshot(location: location(post), text: try text(blocking: names), document: try document(blocking: names))
    }

    static func saved(blocking names: [String], wrote: Bool = true) throws -> MPStorageSaveResult {
        MPStorageSaveResult(snapshot: try snapshot(blocking: names), conflicts: [], wrote: wrote)
    }
}

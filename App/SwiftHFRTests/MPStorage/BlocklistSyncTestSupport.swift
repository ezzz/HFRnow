import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR

extension FakeMPStorageRemote {
    /// Another client wrote the document.
    func replaceText(_ newText: String) { text = newText }

    /// Saves merge with the forum's copy, as LOT-052's transport does.
    func mergeOnSave() { merges = true }

    /// The usernames of the forum document as it stands.
    func blocklist() throws -> [String] {
        BlocklistSyncPlan.usernames(in: try MPStorageCodec.decode(text))
    }
}

/// A `0.1` document whose blocklist holds `names` (and `tombstones`, ids as written).
func blocklistDocumentText(_ names: [String], tombstones: [String] = []) -> String {
    let list = names.map { #"{"createDate":1700000000000,"username":"\#($0)"}"# }.joined(separator: ",")
    let dead = tombstones.map { #"{"deleteDate":1790000000000,"id":"\#($0)"}"# }.joined(separator: ",")
    let tombstoneKey = tombstones.isEmpty ? "" : #","tombstones":[\#(dead)]"#
    return #"{"data":[{"blacklist":{"list":[\#(list)]\#(tombstoneKey)},"bookmarks":{"list":[]},"mpFlags":{"list":[]},"version":"0.1"}]}"#
}

/// Holds every read until released (a sync in flight).
actor ReadGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Reads waiting for the release.
    private(set) var waiting = 0

    func wait() async {
        if open { return }
        waiting += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// The scripted forum with its reads held by a gate.
struct GatedMPStorageRemote: MPStorageRemote {
    let inner: FakeMPStorageRemote
    let gate: ReadGate

    func findThread() async throws(MPStorageTransportError) -> Int? { try await inner.findThread() }

    func read(post: Int) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        await gate.wait()
        return try await inner.read(post: post)
    }

    func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        try await inner.save(ours, base: base, at: location, stamp: stamp)
    }

    func create(stamp: MPStorageStamp) async throws(MPStorageTransportError) -> MPStorageCreation { try await inner.create(stamp: stamp) }
}

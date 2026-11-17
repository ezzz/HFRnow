import Foundation
import HFRModels

extension SyncedListsStore {
    // MARK: Initial-sync rule, applies and pushes

    /// The initial-sync rule for every list: the cloud's list replaces the local one (positions merge); a non-empty
    /// local list the cloud lacks is pushed.
    func reconcile() async {
        guard isActive else { return }
        await reconcile(key: Self.allowlistKey, read: { await self.allowlistItems() }, replace: { items in
            _ = try await self.pseudoLists.replaceAllowlist(with: items)
        })
        await mergeRehostHistory()
        for account in await accounts() {
            if let key = cloudKey(.superFavorites, account: account) {
                await reconcile(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try await self.superFavorites.replace(items, account: account)
                })
            }
            if let key = cloudKey(.smileyFavorites, account: account) {
                await reconcile(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try await self.smileyFavorites.replace(items, account: account)
                })
            }
            await pushPositions(account: account)
        }
    }

    /// The initial-sync rule for one list, refined by Amendment 2: a list changed here since it was last synced is
    /// pushed (this device is its later writer, for example after a sign-out); otherwise the cloud's list replaces it,
    /// and a non-empty local list the cloud lacks is pushed.
    func reconcile<Item: Codable & Hashable & Sendable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async throws -> Void
    ) async {
        guard let local = await read(), ownerIsSignedIn else { return }
        let cloudValue = cloud.value(forKey: key)
        if let cloudValue, SyncedListEnvelope<Item>(cloudValue) == nil { return }
        if let last = synced[key], SyncedListEnvelope(items: local).value.digest != last {
            push(local, forKey: key)
            return
        }
        guard let envelope = cloudValue.flatMap({ SyncedListEnvelope<Item>($0) }) else {
            if local.isEmpty {
                record(SyncedListEnvelope(items: local).value, forKey: key)
            } else {
                push(local, forKey: key)
            }
            return
        }
        await replaceLocal(key: key, with: envelope.items, read: read, replace: replace)
    }

    /// Writes another device's list over the local one and records it as synced; a refused save records nothing, so
    /// the list is not taken for a change made here.
    func replaceLocal<Item: Codable & Hashable & Sendable>(
        key: String, with items: [Item], read: () async -> [Item]?, replace: ([Item]) async throws -> Void
    ) async {
        if await read() != items {
            do { try await replace(items) } catch { return }
        }
        if let applied = await read() { record(SyncedListEnvelope(items: applied).value, forKey: key) }
    }

    /// A server change of one list key: the cloud's list replaces the local one, positions merge.
    func apply(_ key: String) async {
        guard isActive, cloud.value(forKey: key) != nil else { return }
        if key == Self.rehostHistoryKey {
            await mergeRehostHistory()
            return
        }
        if key == Self.allowlistKey {
            await applyCloudList(key: key, read: { await self.allowlistItems() }, replace: { items in
                _ = try await self.pseudoLists.replaceAllowlist(with: items)
            })
            return
        }
        for account in await accounts() {
            if key == cloudKey(.superFavorites, account: account) {
                await applyCloudList(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try await self.superFavorites.replace(items, account: account)
                })
            } else if key == cloudKey(.smileyFavorites, account: account) {
                await applyCloudList(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try await self.smileyFavorites.replace(items, account: account)
                })
            } else if key == cloudKey(.positions, account: account) {
                await mergeCloudPositions(key: key, account: account)
            }
        }
    }

    /// Another device's list: it replaces the local one, unless the local one changed here since its last sync (a
    /// change whose signal is still queued, or one the cloud refused): this device then writes last.
    func applyCloudList<Item: Codable & Hashable & Sendable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async throws -> Void
    ) async {
        guard let local = await read(), ownerIsSignedIn, let value = cloud.value(forKey: key),
              let envelope = SyncedListEnvelope<Item>(value) else { return }
        if let last = synced[key], SyncedListEnvelope(items: local).value.digest != last {
            push(local, forKey: key)
            return
        }
        await replaceLocal(key: key, with: envelope.items, read: read, replace: replace)
    }

    /// After a saved local change: each list that changed here since it was last synced is pushed whole, empty
    /// included. A list never synced meets the initial-sync rule instead.
    func pushLists() async {
        guard isActive else { return }
        await pushIfChanged(key: Self.allowlistKey, read: { await self.allowlistItems() }, replace: { items in
            _ = try await self.pseudoLists.replaceAllowlist(with: items)
        })
        await mergeRehostHistory()
        for account in await accounts() {
            if let key = cloudKey(.superFavorites, account: account) {
                await pushIfChanged(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try await self.superFavorites.replace(items, account: account)
                })
            }
            if let key = cloudKey(.smileyFavorites, account: account) {
                await pushIfChanged(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try await self.smileyFavorites.replace(items, account: account)
                })
            }
        }
    }

    func pushIfChanged<Item: Codable & Hashable & Sendable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async throws -> Void
    ) async {
        guard let last = synced[key] else {
            await reconcile(key: key, read: read, replace: replace)
            return
        }
        guard let local = await read() else { return }
        // Unchanged here: a different cloud list is another device's change, applied when its notification comes.
        guard SyncedListEnvelope(items: local).value.digest != last else { return }
        if let value = cloud.value(forKey: key), SyncedListEnvelope<Item>(value) == nil { return }
        push(local, forKey: key)
    }

    func pushAllPositions() async {
        positionsPending = false
        for account in await accounts() {
            await pushPositions(account: account)
        }
    }

    /// The cloud's positions are merged first, so a push never drops what another device recorded; then the newest
    /// `positionsLimit` are pushed when their places differ from the cloud's (dates alone never cause a push).
    func pushPositions(account: String) async {
        guard isActive, await positionRecords(account) != nil, let key = cloudKey(.positions, account: account)
        else { return }
        guard await mergeCloudPositions(key: key, account: account) else { return }
        let local = Array(await positions.records(for: account).prefix(Self.positionsLimit))
        let cloudRecords = cloud.value(forKey: key).flatMap { SyncedListEnvelope<ReadingPositionRecord>($0) }?.items ?? []
        guard Self.places(local) != Self.places(cloudRecords) else { return }
        push(local, forKey: key)
    }

    /// Merges the cloud's positions into the account's, dates as recorded (a date clamped to this device's clock would
    /// make devices disagree on the winner). Returns false when the cloud value is unreadable or the merge could not be
    /// saved, so nothing is pushed over the cloud's records.
    @discardableResult
    func mergeCloudPositions(key: String, account: String) async -> Bool {
        guard stale[Slot.positions.rawValue] == nil, ownerIsSignedIn else { return false }
        guard let value = cloud.value(forKey: key) else { return true }
        guard let envelope = SyncedListEnvelope<ReadingPositionRecord>(value) else { return false }
        do {
            _ = try await positions.merge(envelope.items, account: account)
            return true
        } catch {
            return false
        }
    }

    func push<Item: Codable & Hashable & Sendable>(_ items: [Item], forKey key: String) {
        let value = SyncedListEnvelope(items: items).value
        guard write(value, forKey: key) else { return }
        record(value, forKey: key)
    }

    /// Writes one value with the schema version; false when it may not be written.
    func write(_ value: SyncedValue, forKey key: String) -> Bool {
        // The Apple ID may have switched since the caller checked `isActive`: never write a list into another one's store.
        guard ownerIsSignedIn, cloudSchemaIsReadable else { return false }
        cloud.set(value, forKey: key)
        if cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) != .int(SyncedSettingsStore.schemaVersion) {
            cloud.set(.int(SyncedSettingsStore.schemaVersion), forKey: SyncedSettingsStore.schemaVersionKey)
        }
        return true
    }

    /// The upload history's rule for every event (#966, Amendment 4): the cloud's uploads and removals are merged into
    /// the device's history by id, then the `rehostHistoryLimit` newest and the removals are pushed when they differ from
    /// the cloud's. Adds made on two devices both survive; a removal on one removes the upload on the others. Nothing is
    /// pushed when the merge could not be saved, nor over a cloud value this build cannot read.
    func mergeRehostHistory() async {
        guard isActive, let rehostHistory, stale[Slot.rehostHistory.rawValue] == nil,
              await rehostHistory.loadFailure() == nil, ownerIsSignedIn else { return }
        let cloudValue = cloud.value(forKey: Self.rehostHistoryKey)
        let cloudEnvelope = cloudValue.flatMap(RehostHistoryEnvelope.init)
        if cloudValue != nil, cloudEnvelope == nil { return }
        let merged: RehostUploadHistoryDocument
        do {
            merged = try await rehostHistory.merge(images: cloudEnvelope?.items ?? [], removals: cloudEnvelope?.removals ?? [])
        } catch {
            return
        }
        // A cloud change that came during the merge is merged by its own event: never write over it unmerged.
        guard cloud.value(forKey: Self.rehostHistoryKey) == cloudValue else { return }
        let next = RehostHistoryEnvelope(merged, limit: Self.rehostHistoryLimit)
        guard next.signature != cloudEnvelope?.signature else { return }
        // An empty history the cloud lacks is not worth a key.
        if cloudEnvelope == nil, next.items.isEmpty, next.removals.isEmpty { return }
        _ = write(next.value, forKey: Self.rehostHistoryKey)
    }

    /// Keeps the digest of the list last synced under `key`, on the device: a later difference is a change made here.
    func record(_ value: SyncedValue, forKey key: String) {
        guard !Self.isPositionsKey(key) else { return }
        synced[key] = value.digest
        saveDeviceState()
    }

    // MARK: Local lists

    func allowlistItems() async -> [PseudoListEntry]? {
        guard stale[Slot.allowlist.rawValue] == nil, await pseudoLists.loadFailure() == nil else { return nil }
        return await pseudoLists.allowlist()
    }

    func superFavoriteItems(_ account: String) async -> [SuperFavorite]? {
        guard stale[Slot.superFavorites.rawValue] == nil, await superFavorites.loadFailure() == nil else { return nil }
        return await superFavorites.favorites(for: account)
    }

    func smileyFavoriteItems(_ account: String) async -> [AppSmileyFavorite]? {
        guard stale[Slot.smileyFavorites.rawValue] == nil, await smileyFavorites.loadFailure() == nil else { return nil }
        return await smileyFavorites.favorites(for: account)
    }

    func positionRecords(_ account: String) async -> [ReadingPositionRecord]? {
        guard stale[Slot.positions.rawValue] == nil, await positions.loadFailure() == nil else { return nil }
        return await positions.records(for: account)
    }
}

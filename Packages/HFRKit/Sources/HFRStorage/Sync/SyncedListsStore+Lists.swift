import Foundation
import HFRModels

extension SyncedListsStore {
    // MARK: Initial-sync rule, applies and pushes

    /// The initial-sync rule for every list: the cloud's list replaces the local one (positions merge); a non-empty
    /// local list the cloud lacks is pushed.
    func reconcile() async {
        guard isActive else { return }
        await reconcile(key: Self.allowlistKey, read: { await self.allowlistItems() }, replace: { items in
            _ = try? await self.pseudoLists.replaceAllowlist(with: items)
        })
        for account in await accounts() {
            if let key = cloudKey(.superFavorites, account: account) {
                await reconcile(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try? await self.superFavorites.replace(items, account: account)
                })
            }
            if let key = cloudKey(.smileyFavorites, account: account) {
                await reconcile(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try? await self.smileyFavorites.replace(items, account: account)
                })
            }
            await pushPositions(account: account)
        }
    }

    func reconcile<Item: Codable & Hashable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async -> Void
    ) async {
        guard let local = await read() else { return }
        guard let value = cloud.value(forKey: key) else {
            if local.isEmpty {
                known[key] = SyncedListEnvelope<Item>(items: []).value
            } else {
                push(local, forKey: key)
            }
            return
        }
        guard let envelope = SyncedListEnvelope<Item>(value) else { return }
        if envelope.items != local { await replace(envelope.items) }
        if let applied = await read() { known[key] = SyncedListEnvelope(items: applied).value }
    }

    /// A server change of one list key: the cloud's list replaces the local one, positions merge.
    func apply(_ key: String) async {
        guard isActive, cloud.value(forKey: key) != nil else { return }
        if key == Self.allowlistKey {
            await replaceLocal(key: key, read: { await self.allowlistItems() }, replace: { items in
                _ = try? await self.pseudoLists.replaceAllowlist(with: items)
            })
            return
        }
        for account in await accounts() {
            if key == cloudKey(.superFavorites, account: account) {
                await replaceLocal(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try? await self.superFavorites.replace(items, account: account)
                })
            } else if key == cloudKey(.smileyFavorites, account: account) {
                await replaceLocal(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try? await self.smileyFavorites.replace(items, account: account)
                })
            } else if key == cloudKey(.positions, account: account) {
                await mergeCloudPositions(key: key, account: account)
            }
        }
    }

    func replaceLocal<Item: Codable & Hashable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async -> Void
    ) async {
        guard await read() != nil, let value = cloud.value(forKey: key),
              let envelope = SyncedListEnvelope<Item>(value) else { return }
        await replace(envelope.items)
        if let applied = await read() { known[key] = SyncedListEnvelope(items: applied).value }
    }

    /// After a saved local change: each list that changed here since it was last applied or pushed is pushed whole,
    /// empty included. A list never synced in this process meets the initial-sync rule instead.
    func pushLists() async {
        guard isActive else { return }
        await pushIfChanged(key: Self.allowlistKey, read: { await self.allowlistItems() }, replace: { items in
            _ = try? await self.pseudoLists.replaceAllowlist(with: items)
        })
        for account in await accounts() {
            if let key = cloudKey(.superFavorites, account: account) {
                await pushIfChanged(key: key, read: { await self.superFavoriteItems(account) }, replace: { items in
                    _ = try? await self.superFavorites.replace(items, account: account)
                })
            }
            if let key = cloudKey(.smileyFavorites, account: account) {
                await pushIfChanged(key: key, read: { await self.smileyFavoriteItems(account) }, replace: { items in
                    _ = try? await self.smileyFavorites.replace(items, account: account)
                })
            }
        }
    }

    func pushIfChanged<Item: Codable & Hashable>(
        key: String, read: () async -> [Item]?, replace: ([Item]) async -> Void
    ) async {
        guard let last = known[key] else {
            await reconcile(key: key, read: read, replace: replace)
            return
        }
        guard let local = await read() else { return }
        // Unchanged here: a different cloud list is another device's change, applied when its notification comes.
        guard SyncedListEnvelope(items: local).value != last else { return }
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
        guard isActive, stale[Slot.positions.rawValue] == nil, let key = cloudKey(.positions, account: account),
              await positions.loadFailure() == nil else { return }
        guard await mergeCloudPositions(key: key, account: account) else { return }
        let local = Array(await positions.records(for: account).prefix(Self.positionsLimit))
        let cloudRecords = cloud.value(forKey: key).flatMap { SyncedListEnvelope<ReadingPositionRecord>($0) }?.items ?? []
        guard Self.places(local) != Self.places(cloudRecords) else { return }
        push(local, forKey: key)
    }

    /// Merges the cloud's positions into the account's, dates as recorded (a date clamped to this device's clock would
    /// make devices disagree on the winner). Returns false when the cloud value is unreadable, so nothing is written
    /// over it.
    @discardableResult
    func mergeCloudPositions(key: String, account: String) async -> Bool {
        guard stale[Slot.positions.rawValue] == nil else { return false }
        guard let value = cloud.value(forKey: key) else { return true }
        guard let envelope = SyncedListEnvelope<ReadingPositionRecord>(value) else { return false }
        _ = try? await positions.merge(envelope.items, account: account)
        return true
    }

    func push<Item: Codable & Hashable>(_ items: [Item], forKey key: String) {
        guard cloudSchemaIsReadable else { return }
        let value = SyncedListEnvelope(items: items).value
        cloud.set(value, forKey: key)
        known[key] = value
        if cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) != .int(SyncedSettingsStore.schemaVersion) {
            cloud.set(.int(SyncedSettingsStore.schemaVersion), forKey: SyncedSettingsStore.schemaVersionKey)
        }
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
}

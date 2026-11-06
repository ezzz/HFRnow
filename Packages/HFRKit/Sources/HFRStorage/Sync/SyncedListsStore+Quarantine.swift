import Foundation

extension SyncedListsStore {
    // MARK: Setting aside and restoring

    /// Moves every synced local list, whatever its account, into the quarantine of `owner` and empties the stores, with
    /// the digests of the lists last synced for it, so a change made here before the switch is still pushed when it
    /// comes back. A store that cannot be read or emptied is marked stale: never pushed, set aside as soon as it can be.
    func setAside(owner previous: String) async {
        for slot in Slot.allCases {
            await setAside(slot, owner: previous, digests: true)
        }
        saveDeviceState()
    }

    func setAside(_ slot: Slot, owner previous: String, digests: Bool = false) async {
        guard await isReadable(slot) else {
            markStale(slot, owner: previous)
            return
        }
        let names = await listNames(slot)
        var values: [String: SyncedValue] = [:]
        for name in names {
            if let value = await localValue(slot, name: name) { values[slotKey(slot, name: name)] = value }
        }
        // Every digest of this store's lists, those emptied here since their last sync included (they hold no name).
        if digests {
            for (key, digest) in synced where slot.owns(key) { values[Self.digestPrefix + key] = .string(digest) }
        }
        quarantine(values, for: previous)
        var emptied = true
        for name in names where await !empty(slot, name: name) { emptied = false }
        if emptied {
            stale[slot.rawValue] = nil
        } else {
            markStale(slot, owner: previous)
        }
    }

    /// A store already stale still holds its first owner's lists.
    func markStale(_ slot: Slot, owner previous: String) {
        stale[slot.rawValue] = stale[slot.rawValue] ?? previous
    }

    /// The account keys (lists), the accounts as stored (positions) or the single allowlist a store holds.
    func listNames(_ slot: Slot) async -> [String] {
        switch slot {
        case .allowlist: [""]
        case .superFavorites: await superFavorites.accountKeys()
        case .smileyFavorites: await smileyFavorites.accountKeys()
        case .positions: await positions.accounts()
        }
    }

    /// The quarantine key of one list: the cloud key's form, with the stored account for positions.
    func slotKey(_ slot: Slot, name: String) -> String {
        slot == .allowlist ? Self.allowlistKey : "\(slot.rawValue).\(name)"
    }

    /// One local list as an envelope, nil when it is empty.
    func localValue(_ slot: Slot, name: String) async -> SyncedValue? {
        switch slot {
        case .allowlist: Self.nonEmpty(await pseudoLists.allowlist())
        case .superFavorites: Self.nonEmpty(await superFavorites.favorites(for: name))
        case .smileyFavorites: Self.nonEmpty(await smileyFavorites.favorites(for: name))
        case .positions: Self.nonEmpty(await positions.records(for: name))
        }
    }

    static func nonEmpty<Item: Codable & Hashable>(_ items: [Item]) -> SyncedValue? {
        items.isEmpty ? nil : SyncedListEnvelope(items: items).value
    }

    /// Empties one local list; false when the store refused.
    func empty(_ slot: Slot, name: String) async -> Bool {
        do {
            switch slot {
            case .allowlist: _ = try await pseudoLists.replaceAllowlist(with: [])
            case .superFavorites: _ = try await superFavorites.replace([], account: name)
            case .smileyFavorites: _ = try await smileyFavorites.replace([], account: name)
            case .positions: _ = try await positions.removeAccount(name)
            }
            return true
        } catch {
            return false
        }
    }

    func isReadable(_ slot: Slot) async -> Bool {
        switch slot {
        case .allowlist: await pseudoLists.loadFailure() == nil
        case .superFavorites: await superFavorites.loadFailure() == nil
        case .smileyFavorites: await smileyFavorites.loadFailure() == nil
        case .positions: await positions.loadFailure() == nil
        }
    }

    /// A store that could not be set aside at an Apple ID change: once readable, its content goes to the quarantine of
    /// the Apple ID it belongs to, unless that Apple ID owns the lists again. A store found empty (its unreadable data
    /// discarded, which signals it) has nothing of that Apple ID left.
    func settleStaleStores() async {
        for (prefix, staleOwner) in stale.sorted(by: { $0.key < $1.key }) {
            guard let slot = Slot(rawValue: prefix) else {
                stale[prefix] = nil
                continue
            }
            if let owner, owner == staleOwner || (cloud.isCurrentAccount(staleOwner) && cloud.isCurrentAccount(owner)) {
                stale[prefix] = nil
            } else if await isReadable(slot) {
                stale[prefix] = nil
                restoreDeferred = true
                if await hasContent(slot) { await setAside(slot, owner: staleOwner) }
            }
        }
        saveDeviceState()
        // The owner's quarantined lists that could not come back at the switch (a stale store, a switch paused by an
        // unwritable device file) come back once they can, once: a list the user empties later is not refilled.
        if restoreDeferred, let owner, cloud.isCurrentAccount(owner), !stateUnsaved {
            restoreDeferred = false
            await restore(for: owner)
        }
    }

    func hasContent(_ slot: Slot) async -> Bool {
        for name in await listNames(slot) where await localValue(slot, name: name) != nil { return true }
        return false
    }

    /// Brings back the quarantined lists of the Apple ID `identity` where the local list is empty. A list that cannot be
    /// restored (its store stale, or a local list already there) stays in the quarantine.
    func restore(for identity: String) async {
        for (holder, entry) in unsaved where cloud.isCurrentAccount(holder) {
            let left = await restore(entry.values)
            unsaved[holder] = left.isEmpty ? nil : SyncQuarantineEntry(savedAt: entry.savedAt, values: left)
        }
        let saved = (device.document()?.quarantine ?? [:]).filter { cloud.isCurrentAccount($0.key) }
        for (holder, entry) in saved.sorted(by: { $0.key < $1.key }) {
            let left = await restore(entry.values)
            _ = try? device.mutate { document throws(SmallStoreError) in
                guard left != entry.values else { return false }
                document.quarantine[holder] = left.isEmpty ? nil : SyncQuarantineEntry(savedAt: entry.savedAt, values: left)
                return true
            }
        }
    }

    /// Restores each list it can, with its digest; returns what it could not restore.
    private func restore(_ values: [String: SyncedValue]) async -> [String: SyncedValue] {
        var left: [String: SyncedValue] = [:]
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            if key.hasPrefix(Self.digestPrefix) {
                let listKey = String(key.dropFirst(Self.digestPrefix.count))
                // A digest goes with its list; alone (the list was empty), it comes back where the list is empty.
                guard values[listKey] == nil else { continue }
                if await isEmptyLocally(listKey), case .string(let digest) = value {
                    synced[listKey] = digest
                } else {
                    left[key] = value
                }
            } else if await restore(value, key: key) {
                if case .string(let digest)? = values[Self.digestPrefix + key] { synced[key] = digest }
            } else {
                left[key] = value
                left[Self.digestPrefix + key] = values[Self.digestPrefix + key]
            }
        }
        saveDeviceState()
        return left
    }

    private func isEmptyLocally(_ key: String) async -> Bool {
        let name = String(key.drop { $0 != "." }.dropFirst())
        switch slot(of: key) {
        case .allowlist: return await allowlistItems()?.isEmpty == true
        case .superFavorites: return await superFavoriteItems(name)?.isEmpty == true
        case .smileyFavorites: return await smileyFavoriteItems(name)?.isEmpty == true
        case .positions: return false
        }
    }

    private func restore(_ value: SyncedValue, key: String) async -> Bool {
        let name = String(key.drop { $0 != "." }.dropFirst())
        do {
            switch slot(of: key) {
            case .allowlist:
                guard let items = SyncedListEnvelope<PseudoListEntry>(value)?.items, await allowlistItems()?.isEmpty == true
                else { return false }
                _ = try await pseudoLists.replaceAllowlist(with: items)
            case .superFavorites:
                guard let items = SyncedListEnvelope<SuperFavorite>(value)?.items,
                      await superFavoriteItems(name)?.isEmpty == true else { return false }
                _ = try await superFavorites.replace(items, account: name)
            case .smileyFavorites:
                guard let items = SyncedListEnvelope<AppSmileyFavorite>(value)?.items,
                      await smileyFavoriteItems(name)?.isEmpty == true else { return false }
                _ = try await smileyFavorites.replace(items, account: name)
            case .positions:
                guard let items = SyncedListEnvelope<ReadingPositionRecord>(value)?.items,
                      await positionRecords(name)?.isEmpty == true else { return false }
                _ = try await positions.merge(items, account: name)
            }
            return true
        } catch {
            return false
        }
    }

    func quarantine(_ values: [String: SyncedValue], for holder: String) {
        guard !values.isEmpty else { return }
        let now = clock()
        do throws(SmallStoreError) {
            _ = try device.mutate { document throws(SmallStoreError) in
                var entry = document.quarantine[holder] ?? SyncQuarantineEntry(savedAt: now, values: [:])
                entry.values.merge(values) { _, new in new }
                entry.savedAt = now
                document.quarantine[holder] = entry
                return true
            }
        } catch {
            var entry = unsaved[holder] ?? SyncQuarantineEntry(savedAt: now, values: [:])
            entry.values.merge(values) { _, new in new }
            entry.savedAt = now
            unsaved[holder] = entry
            deviceStateFailure = error
        }
    }

    /// Deletes quarantined lists older than the quarantine lifetime.
    func purge() {
        let limit = clock().addingTimeInterval(-SyncedSettingsStore.quarantineLifetime)
        unsaved = unsaved.filter { $0.value.savedAt > limit }
        guard let quarantine = device.document()?.quarantine, quarantine.values.contains(where: { $0.savedAt <= limit })
        else { return }
        _ = try? device.mutate { document throws(SmallStoreError) in
            document.quarantine = document.quarantine.filter { $0.value.savedAt > limit }
            return true
        }
    }

    /// Saves the owner, the stale stores, the digests and any quarantine kept in memory; while the file lags behind,
    /// the sync pauses (`isActive`).
    func saveDeviceState() {
        let owner = owner
        let stale = stale
        let synced = synced
        let unsaved = unsaved
        do throws(SmallStoreError) {
            _ = try device.mutate { document throws(SmallStoreError) in
                guard document.owner != owner || document.stale != stale || document.synced != synced || !unsaved.isEmpty
                else { return false }
                document.owner = owner
                document.stale = stale
                document.synced = synced
                for (holder, entry) in unsaved {
                    var merged = document.quarantine[holder] ?? entry
                    merged.values.merge(entry.values) { _, new in new }
                    merged.savedAt = max(merged.savedAt, entry.savedAt)
                    document.quarantine[holder] = merged
                }
                return true
            }
            self.unsaved = [:]
            stateUnsaved = false
        } catch {
            stateUnsaved = true
            deviceStateFailure = error
        }
    }
}

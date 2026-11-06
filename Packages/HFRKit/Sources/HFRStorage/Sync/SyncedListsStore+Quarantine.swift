import Foundation

extension SyncedListsStore {
    // MARK: Setting aside and restoring

    /// Moves every synced local list, whatever its account, into the quarantine of `owner` and empties the stores. A
    /// store that cannot be read or emptied is marked stale: never pushed, set aside as soon as it can be.
    func setAside(owner previous: String) async {
        for slot in Slot.allCases {
            await setAside(slot, owner: previous)
        }
        saveOwnership()
    }

    func setAside(_ slot: Slot, owner previous: String) async {
        guard await isReadable(slot) else {
            markStale(slot, owner: previous)
            return
        }
        let names = await listNames(slot)
        var values: [String: SyncedValue] = [:]
        for name in names {
            if let value = await localValue(slot, name: name) { values[slotKey(slot, name: name)] = value }
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
    /// the Apple ID it belongs to, unless that Apple ID owns the lists again.
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
                await setAside(slot, owner: staleOwner)
            }
        }
        saveOwnership()
    }

    /// Brings back the quarantined lists of the Apple ID `identity` where the local list is empty.
    func restore(for identity: String) async {
        var values: [String: SyncedValue] = [:]
        for (holder, entry) in unsaved where cloud.isCurrentAccount(holder) {
            values.merge(entry.values) { kept, _ in kept }
            unsaved[holder] = nil
        }
        let saved = (device.document()?.quarantine ?? [:]).filter { cloud.isCurrentAccount($0.key) }
        for entry in saved.values { values.merge(entry.values) { kept, _ in kept } }
        if !saved.isEmpty {
            _ = try? device.mutate { document throws(SmallStoreError) in
                for holder in saved.keys { document.quarantine[holder] = nil }
                return true
            }
        }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            await restore(value, key: key)
        }
    }

    func restore(_ value: SyncedValue, key: String) async {
        let name = String(key.drop { $0 != "." }.dropFirst())
        switch slot(of: key) {
        case .allowlist:
            guard let items = SyncedListEnvelope<PseudoListEntry>(value)?.items, await allowlistItems()?.isEmpty == true
            else { return }
            _ = try? await pseudoLists.replaceAllowlist(with: items)
        case .superFavorites:
            guard let items = SyncedListEnvelope<SuperFavorite>(value)?.items,
                  await superFavoriteItems(name)?.isEmpty == true else { return }
            _ = try? await superFavorites.replace(items, account: name)
        case .smileyFavorites:
            guard let items = SyncedListEnvelope<AppSmileyFavorite>(value)?.items,
                  await smileyFavoriteItems(name)?.isEmpty == true else { return }
            _ = try? await smileyFavorites.replace(items, account: name)
        case .positions:
            guard let items = SyncedListEnvelope<ReadingPositionRecord>(value)?.items,
                  await positions.loadFailure() == nil, await positions.records(for: name).isEmpty else { return }
            _ = try? await positions.merge(items, account: name)
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

    func saveOwnership() {
        let owner = owner
        let stale = stale
        do throws(SmallStoreError) {
            _ = try device.mutate { document throws(SmallStoreError) in
                guard document.owner != owner || document.stale != stale else { return false }
                document.owner = owner
                document.stale = stale
                return true
            }
        } catch {
            deviceStateFailure = error
        }
    }
}

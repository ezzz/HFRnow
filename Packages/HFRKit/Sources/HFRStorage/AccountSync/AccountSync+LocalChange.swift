import Foundation

// MARK: - Local change

extension AccountSync {
    /// Records `change`, made at `now`, in the state: its stamp, imported set and removal marker, each dated after what the
    /// copy and this device already hold for that account (#1390). `raw` is the copy the push will compare against (nil
    /// while off).
    static func record(_ change: AccountSyncChange, at now: Date, in state: inout AccountSyncState, copy raw: Data?) {
        switch change {
        case .login(let pseudo):
            let key = AccountKey.make(pseudo)
            state.stamps[key] = stamp(login: true, of: key, at: now, in: state, copy: raw)
            // Entered on this device: never dropped by a provisional switch-off (spec D8); the other imported
            // accounts stay lent until the confirming read.
            state.imported.remove(key)
        case .refresh(let pseudo):
            let key = AccountKey.make(pseudo)
            // Only new login cookies win the merge; a refresh of the same login keeps the copy's entry (#1390).
            state.stamps[key] = stamp(login: false, of: key, at: now, in: state, copy: raw)
        case .removal(let pseudo):
            let key = AccountKey.make(pseudo)
            // Dated after the last login the copy holds, so a removal on a device whose clock is late still wins.
            let removedAt = later(now, than: floorStamp(of: key, in: state, copy: raw).consentAt)
            state.stamps[key] = nil
            state.imported.remove(key)
            if state.isOn { state.removed[key] = removedAt }
        }
    }

    /// The stamp of a login (both dates) or a refresh (`credentialsAt` only) of `key` made at `now`, while `raw` is the
    /// copy the push will compare against (nil while off).
    private static func stamp(login: Bool, of key: String, at now: Date, in state: AccountSyncState, copy raw: Data?) -> AccountStamp {
        let floor = floorStamp(of: key, in: state, copy: raw)
        let consentAt = login ? later(now, than: floor.consentAt) : state.stamps[key]?.consentAt ?? .distantPast
        return AccountStamp(credentialsAt: later(now, than: floor.credentialsAt), consentAt: consentAt)
    }

    /// The latest dates this device knows for `key` (its own stamp, the copy's entry and removal markers). A change made
    /// here is stamped after them even when this device's clock is behind the device that wrote the copy (#1390): a
    /// re-login or new login cookies on a device whose clock is late must not lose the merge to an older login. An
    /// unreadable copy adds nothing: the reconcile that follows reports it.
    private static func floorStamp(of key: String, in state: AccountSyncState, copy raw: Data?) -> AccountStamp {
        var credentials = [state.stamps[key]?.credentialsAt]
        var consent = [state.stamps[key]?.consentAt, state.removed[key]]
        if let raw, case .full(_, let remote, let removed)? = try? AccountSyncEnvelope.decode(raw) {
            let entry = remote.first { AccountKey.make($0.account.pseudo) == key }
            credentials.append(entry?.credentialsAt)
            consent += [entry?.consentAt, removed[key]]
        }
        return AccountStamp(
            credentialsAt: credentials.compactMap { $0 }.max() ?? .distantPast, consentAt: consent.compactMap { $0 }.max() ?? .distantPast
        )
    }

    /// `now`, or just after `floor` when `floor` is not earlier.
    private static func later(_ now: Date, than floor: Date?) -> Date {
        guard let floor, floor >= now else { return now }
        return floor.addingTimeInterval(step)
    }
}

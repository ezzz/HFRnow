import Foundation
import HFRModels
import HFRNetwork

/// The account session as the refresh found it, read in one actor turn.
struct RefreshSeed: Sendable {
    /// Usable `md_user` value, nil when the session is logged out.
    let identity: String?
    /// Every non-expired cookie, the probe's starting jar.
    let cookies: [StoredCookie]
    /// The token the session held.
    let hashCheck: String?
}

/// What a confirmed refresh changes: cookies HFR set or removed, compared with the seed, and the page's token.
struct RefreshUpdate: Sendable {
    /// One changed jar key: the seed's cookies for it and the probe's (empty when HFR removed it).
    struct Change: Sendable {
        let key: String
        let seed: [StoredCookie]
        let after: [StoredCookie]
    }

    /// Every jar key whose cookies differ between the seed and the probe after the answer.
    let changes: [Change]
    /// The token read on the profile page.
    let hashCheck: String

    init(seed: [StoredCookie], after: [StoredCookie], hashCheck: String) {
        let before = Dictionary(grouping: seed, by: \.jarKey)
        let now = Dictionary(grouping: after, by: \.jarKey)
        let keys = Set(before.keys).union(now.keys).sorted()
        changes = keys.compactMap { key in
            let old = before[key] ?? []
            let new = now[key] ?? []
            return Set(old) == Set(new) ? nil : Change(key: key, seed: old, after: new)
        }
        self.hashCheck = hashCheck
    }
}

extension HFRSession {
    /// Identity, cookies and token in one actor turn, so the three describe the same moment.
    func refreshSeed(now: Date) -> RefreshSeed {
        RefreshSeed(identity: userKey(now: now), cookies: cookies(now: now), hashCheck: hashCheck)
    }

    /// Installs a confirmed refresh in one actor turn, without undoing what other requests did meanwhile.
    ///
    /// A cookie is written only when the session still holds, for its key, what the refresh started from: a newer
    /// value set by a concurrent request wins over the probe's copy. Same rule for `hash_check`. Checks cancellation on
    /// the actor itself, so a task cancelled on its way here changes nothing.
    func adoptRefresh(_ update: RefreshUpdate, seed: RefreshSeed, now: Date) throws(NetworkError) -> SessionHealth {
        if Task.isCancelled { throw .cancelled }
        guard let identity = seed.identity, userKey(now: now) == identity else { return .unconfirmed(.sessionChanged) }
        let current = Dictionary(grouping: cookies(now: now), by: \.jarKey)
        var writes: [StoredCookie] = []
        for change in update.changes where Set(current[change.key] ?? []) == Set(change.seed) {
            if change.after.isEmpty {
                // An expired copy deletes every cookie of that key (`mergeCookies`).
                writes += change.seed.map { cookie in
                    var removal = cookie
                    removal.expiresDate = now
                    return removal
                }
            } else {
                writes += change.after
            }
        }
        mergeCookies(writes, now: now)
        if hashCheck == seed.hashCheck { updateHashCheck(update.hashCheck) }
        return .valid
    }
}

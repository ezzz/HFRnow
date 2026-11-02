import Foundation
import HFRNetwork
import HFRParsing

/// What the profile screen needs from the forum: one member's public profile, fetched and parsed.
protocol UserProfileSource: Sendable {
    /// The public profile of member `memberID` (`/hfr/profil-<id>.htm`, HFR-PROTOCOL R9).
    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile
}

// Port of HFRswift/Swift/UserProfileView.swift (UserProfileService.fetchProfile) @ 21173e77. Differences: fetched without the
// account's cookies, and a page served at another URL is refused (LOT-116 spec, differences 1 and 2).
/// The live source: `PageFetcher.profile` (LOT-045) **without cookies**, then `UserProfileParser` (LOT-027).
///
/// The parser is verified on logged-out pages only (`R56a`, `R56b`); what a logged-in view adds is not captured (#124), so
/// the account's session is never sent for a profile. A page served at another URL (a redirect the captures do not show,
/// e.g. for a deleted member) is refused rather than read as a profile.
struct LiveUserProfileSource: UserProfileSource {
    let fetcher: PageFetcher

    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile {
        let raw: RawPage
        do throws(NetworkError) {
            raw = try await fetcher.profile(memberID: memberID, as: .anonymous)
        } catch {
            throw ListLoadError(error)
        }
        guard Self.isProfilePage(raw.finalURL, memberID: memberID) else { throw .unreadable }
        do throws(ParsingError) {
            return try UserProfileParser.parse(html: raw.text)
        } catch {
            throw .unreadable
        }
    }

    /// `https://forum.hardware.fr/hfr/profil-<memberID>.htm`, the only URL a profile is read from (HFR-PROTOCOL R9).
    static func isProfilePage(_ url: URL, memberID: Int) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == "forum.hardware.fr" && url.port == nil
            && url.user == nil && url.path(percentEncoded: true) == "/hfr/profil-\(memberID).htm"
    }
}

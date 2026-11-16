import HFRModels

/// The Messages list at 100 conversations per screen (#968, operator decision of 2026-11-16): screen `n` merges HFR's pages
/// `2n - 1` and `2n` of `cat=prive` (50 rows each, captures R13u1 and R95k), in order and without duplicates, so a conversation
/// that moved from one page to the other between the two requests shows once.
///
/// The answer's navigation counts screens: `last` is ⌈last HFR page / 2⌉ and `nextPath` is set while a later screen exists, so
/// `MessageListModel` pages by screens without knowing about HFR's pages. Page 2n is requested only when HFR's page 2n - 1 links
/// to a next page; when that second request fails, the whole screen fails (a half screen would hide rows without saying so).
struct ScreenedPrivateMessageSource: PrivateMessageSource {
    let base: any PrivateMessageSource

    func privateMessages(page screen: Int) async throws(ListLoadError) -> PrivateMessageListPage {
        let screen = max(screen, 1)
        let first = try await base.privateMessages(page: 2 * screen - 1)
        var second: PrivateMessageListPage?
        if first.navigation.nextPath != nil { second = try await base.privateMessages(page: 2 * screen) }
        let lastHFRPage = max(first.navigation.last, second?.navigation.last ?? 1, 2 * screen - 1)
        let hasNextScreen = (second ?? first).navigation.nextPath != nil
        let screens = max(Self.screenCount(lastHFRPage: lastHFRPage), hasNextScreen ? screen + 1 : screen)
        return PrivateMessageListPage(
            threads: Self.merged(first.threads, second?.threads ?? []),
            navigation: PageNavigation(
                current: screen, last: screens, isExact: first.navigation.isExact,
                nextPath: screen < screens ? "/screen/\(screen + 1)" : nil,
                previousPath: screen > 1 ? "/screen/\(screen - 1)" : nil
            ),
            newMessagePath: first.newMessagePath
        )
    }

    /// ⌈last HFR page / 2⌉, at least 1.
    static func screenCount(lastHFRPage: Int) -> Int { max((lastHFRPage + 1) / 2, 1) }

    /// `first` then `second`, a conversation already listed being skipped.
    static func merged(_ first: [PrivateMessageThread], _ second: [PrivateMessageThread]) -> [PrivateMessageThread] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }
}

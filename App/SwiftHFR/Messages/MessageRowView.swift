import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MPListView.swift (MPRowView) @ 87fe0d1c (earlier pointer: @ 2440d79). Differences: one info line under
// the title (`MessageRowInfoLine`, #900; legacy `MPListView.swift:775-793`, laid out by `TopicRowView`'s bottom row); the former
// three-line meta block became the experimental dense row, one line (`DenseRowFormat`, #905, #973); unread from the member's icon state
// (GAP-111); accent tint on unread rows (GAP-227); a stronger secondary colour for read titles in light (#651, GAP-227);
// "non lu" capsule for the correspondent's state (GAP-111); capsule at 4.5:1, outlined at half strength (LOT-162, #646).
/// One conversation row: avatar, subject, interlocutor(s), last message. Pure display.
struct MessageRowView: View {
    let thread: PrivateMessageThread
    /// The member's unread state as the list shows it (HFR's, until the thread is opened).
    let isUnread: Bool
    /// The row is the list's selection (iPad): the system highlight must show, so the tint steps aside.
    var isSelected = false
    /// A group row's MPStorage position, `⚑ <page> / <max>` (LOT-130); nil shows the interlocutors.
    var flagLabel: String?
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?
    /// 1 at the default Dynamic Type size; multiplies the avatar and marker sizes.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    var body: some View {
        HStack(spacing: scale.scaled(dynamicType * (density == .compact ? 8 : 12))) {
            let avatar = Self.avatarSubject(of: thread)
            MessageAvatarView(pseudo: avatar.pseudo, isGroup: avatar.isGroup)
                .frame(width: avatarSide, height: avatarSide)
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let label = MessageRowView.unreadByLabel(thread) {
                        // The correspondent's state, not the member's: legacy's leading badge (`MPListView.swift:430-436, 470` @ 2440d79),
                        // at half strength once the member has viewed the thread (legacy line 435).
                        // Outlined instead of half-strength once the member has viewed it: the half-strength fill measured 1.7:1 (#646).
                        BadgeCapsule(text: "non lu", isOutlined: !isUnread)
                            .accessibilityLabel(label)
                    }
                    Text(thread.summary.displayTitle)
                        .scaledFont(density.titleStyle)
                        .fontWeight(titleTone.weight)
                        .foregroundStyle(titleTone.style)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : density.titleLineLimit)
                }
                // EXPERIMENTAL(denseRows, #905, #973): replaces legacy's two-sided info line by one dense line (`DenseRowFormat`).
                if usesDenseRows { denseInfo } else { infoLine }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isUnread {
                let marker = scale.scaled(dynamicType * (density.markerSize + 2))
                Circle().fill(.tint).frame(width: marker, height: marker).accessibilityLabel("Non lu")
            }
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(density.rowInsets)
    }

    /// The default is legacy's one info line; Réglages › Expérimental › « Lignes denses » flips this.
    private var usesDenseRows: Bool { ExperimentalSettings.isOn(.denseRows, in: experimental) }

    /// Legacy's bottom row: interlocutor or group flag on the left, « last poster - time » on the right (`MPListView.swift:840-841`).
    @ViewBuilder private var infoLine: some View {
        let info = MessageRowInfoLine.make(thread: thread, flagLabel: flagLabel)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                if let leading = info.leading { Text(leading) }
                if let trailing = info.trailing { Text(trailing) }
            }
            .scaledFont(.caption).foregroundStyle(.secondary)
        } else if info.leading != nil || info.trailing != nil {
            HStack(spacing: 8) {
                if let leading = info.leading { Text(leading).lineLimit(1) }
                Spacer(minLength: 0)
                if let trailing = info.trailing { Text(trailing).lineLimit(1).layoutPriority(-1) }
            }
            .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    /// The dense row's single info line (#905, #973): interlocutor or « ⚑ page / pages », last poster, age; never wraps.
    @ViewBuilder private var denseInfo: some View {
        if let line = DenseRowFormat.messageInfo(thread: thread, flagLabel: flagLabel) {
            Text(line).scaledFont(.caption).foregroundStyle(.secondary)
                .denseInfoLine(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        }
    }

    /// The capsule's spoken label when the correspondent has not read the thread, else nil (#579).
    static func unreadByLabel(_ thread: PrivateMessageThread) -> String? {
        guard thread.isUnreadByOthers else { return nil }
        let names = thread.unreadBy.joined(separator: ", ")
        return names.isEmpty ? "Non lu par le destinataire" : "Non lu par \(names)"
    }

    /// What the avatar shows (#714): the correspondent of a one-to-one thread, never the account's own pseudo (the list's
    /// starter cell names the other member), and the group icon for a group, whether the parser read the tooltip or only
    /// HFR's "Interlocuteurs multiples" label (legacy `MPListView.swift:895-901` @ `87fe0d1c`, which tests the word "multiples";
    /// here the whole label, so a member whose pseudo holds that word keeps their avatar). A blank name has no avatar:
    /// the view then draws the monogram.
    static func avatarSubject(of thread: PrivateMessageThread) -> (pseudo: String?, isGroup: Bool) {
        let label = "Interlocuteurs multiples"
        let candidate = thread.interlocutors.first ?? thread.summary.starterOrInterlocutors
        let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if thread.isGroup || name.caseInsensitiveCompare(label) == .orderedSame { return (nil, true) }
        return (name.isEmpty ? nil : name, false)
    }

    /// The accent tint of an unread, unselected row; nil leaves the system background (#570).
    static func rowTint(isUnread: Bool, isSelected: Bool) -> RowTint? {
        isUnread && !isSelected ? RowTint() : nil
    }

    /// Primary and semibold when unread, secondary and regular when read (#651).
    private var titleTone: MessageTitleTone { .of(isUnread: isUnread) }

    /// Capped, so an accessibility size leaves the text its room.
    private var avatarSide: CGFloat { min(scale.scaled(dynamicType * density.avatarSize), 64) }
}

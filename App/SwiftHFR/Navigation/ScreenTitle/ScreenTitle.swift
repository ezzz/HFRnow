import SwiftUI
import UIKit

// New in SwiftHFR (#977, #978, #865; operator 2026-11-16): the current app opens its main screens with a large title; the collapsed
// title is a centred Liquid Glass pill like the Claude app's, instead of a plain inline title that takes a band of the screen.
/// How a screen shows its title.
enum ScreenTitleStyle: Equatable, Sendable {
    /// A main screen: a large title as the first row of the content, and the pill once that row has scrolled away.
    case largeThenPill
    /// A pushed screen (a category's topic list): the pill from the start.
    case pill

    /// Whether the pill is in the top bar, given whether the large title is still on screen.
    func showsPill(headerVisible: Bool) -> Bool {
        switch self {
        case .pill: true
        case .largeThenPill: !headerVisible
        }
    }

    /// What the top bar's centre slot holds. The slot is never left empty (#1012). Hypothesis, to confirm on the device (#893): the
    /// `toolbar(removing: .title)` of the first version took the pill's slot with it, so no pill appeared at all.
    func pillPresentation(headerVisible: Bool) -> PillPresentation {
        showsPill(headerVisible: headerVisible) ? .shown : .reserved
    }

    /// The title style of a topic list column: Favoris (the column with the favourites options) is a main screen, every other list
    /// is pushed from a forum row (#977, #978).
    static func topicList(isFavoritesRoot: Bool) -> ScreenTitleStyle {
        isFavoritesRoot ? .largeThenPill : .pill
    }
}

/// The state of the pill in the bar's centre slot.
enum PillPresentation: Equatable, Sendable {
    /// Drawn and tappable.
    case shown
    /// In the slot but invisible, inert and hidden from VoiceOver: the large title is still on screen.
    case reserved
}

/// What a tap on the pill does (#978): it shows the full title, which folds back on the next tap, a tap outside (the popover's own
/// dismissal) or after `foldDelay`.
struct TitlePillState: Equatable {
    /// Whether the full title is shown.
    var isExpanded = false
    /// How long the full title stays up.
    static let foldDelay = Duration.seconds(4)
    /// What VoiceOver announces after a copy.
    static let copiedAnnouncement = "Titre copié"

    /// A tap on the pill.
    mutating func tap() { isExpanded.toggle() }
    /// The end of the delay.
    mutating func fold() { isExpanded = false }
}

extension View {
    /// Gives the screen its title under the shared rule (#977, #978, #865). `visibility` tracks whether the `ScreenLargeTitle` row
    /// is on screen; a `.pill` screen has none and passes nil. The title stays the navigation title (back button,
    /// VoiceOver), but the system's own inline title is replaced by the pill, so no strip of the screen is kept for it and the content
    /// scrolls under the bar.
    func screenTitle(_ title: String, style: ScreenTitleStyle, visibility: TitleVisibility? = nil) -> some View {
        modifier(ScreenTitleModifier(title: title, style: style, visibility: visibility))
    }
}

private struct ScreenTitleModifier: ViewModifier {
    let title: String
    let style: ScreenTitleStyle
    let visibility: TitleVisibility?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PillSlot(title: title, style: style, visibility: visibility)
                }
                // The pill draws its own glass: the bar must not put a second capsule behind it.
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// Whether a main screen's large title is on screen. A class of its own, read only by `PillSlot`: if the list held this as `@State`
/// and read it in its `body`, every crossing of the large title would rebuild the whole list (#1015, suspect 1).
@MainActor @Observable
final class TitleVisibility {
    /// True at landing, while the large title is the first row on screen.
    var isHeaderVisible = true
    #if DEBUG
    /// Test seam (#1015): how many times the large title reported leaving or coming back.
    @ObservationIgnored private(set) var reports = 0
    #endif

    /// The large title's report: it is on screen or not.
    func report(_ visible: Bool) {
        isHeaderVisible = visible
        #if DEBUG
        reports += 1
        #endif
    }
}

/// The bar's centre slot: the pill, or its invisible placeholder (see `ScreenTitleStyle.pillPresentation`). It is the only reader of
/// `TitleVisibility`, so a crossing redraws this view and nothing else.
private struct PillSlot: View {
    let title: String
    let style: ScreenTitleStyle
    let visibility: TitleVisibility?

    var body: some View {
        // A `.pill` screen has no large title: nil reads as "gone".
        let presentation = style.pillPresentation(headerVisible: visibility?.isHeaderVisible ?? false)
        TitlePill(title: title, isActive: presentation == .shown)
            .opacity(presentation == .shown ? 1 : 0)
            .allowsHitTesting(presentation == .shown)
            .accessibilityHidden(presentation == .reserved)
    }
}

/// The large title of a main screen: the first row of its list or form, which scrolls with the content. It reports whether it is
/// on screen, so the pill takes over once it is gone.
struct ScreenLargeTitle: View {
    let title: String
    let visibility: TitleVisibility

    var body: some View {
        // Its own section: in an inset-grouped list, a row outside any section shares the implicit one, and this clear row would
        // take the first real row's rounded top corners.
        Section {
            Text(title)
                .scaledFont(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .accessibilityAddTraits(.isHeader)
                .onScrollVisibilityChange { visibility.report($0) }
        }
    }
}

/// The collapsed title: a Liquid Glass capsule, one line cut with « … », in the free space between the bar's buttons.
struct TitlePill: View {
    let title: String
    /// False while the pill is only holding its slot: an open full title folds then, instead of hanging on an invisible pill.
    var isActive = true
    @State private var state = TitlePillState()
    @State private var justCopied = false

    var body: some View {
        Text(justCopied ? "Copié" : title)
            .scaledFont(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            // The height of the bar's floating buttons.
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
            .onTapGesture { state.tap() }
            .onLongPressGesture { copy() }
            .popover(isPresented: $state.isExpanded) {
                Text(title)
                    .scaledFont(.headline)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
            .onChange(of: isActive) { _, active in
                if !active { state.fold() }
            }
            .task(id: state.isExpanded) {
                guard state.isExpanded else { return }
                try? await Task.sleep(for: TitlePillState.foldDelay)
                state.fold()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint("Touchez pour lire le titre en entier, maintenez pour le copier")
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityAction(named: "Copier le titre") { copy() }
    }

    private func copy() {
        UIPasteboard.general.string = title
        AccessibilityNotification.Announcement(TitlePillState.copiedAnnouncement).post()
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }
}

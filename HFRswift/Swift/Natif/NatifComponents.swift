//
//  NatifComponents.swift
//  HFRswift
//
//  Reusable building blocks of the "Natif calme" direction.
//

import SwiftUI

// MARK: - Unread indicators

/// Leading status of a topic row: filled dot = unread, ring = followed and up to date.
enum NatifTopicStatus {
    case unread
    case followed
}

struct NatifStatusIndicator: View {
    let status: NatifTopicStatus?
    @Environment(\.natif) private var natif

    var body: some View {
        Group {
            switch status {
            case .unread:
                Circle().fill(natif.accent)
            case .followed:
                Circle().strokeBorder(natif.accent, lineWidth: 1.5)
            case nil:
                Color.clear
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(status == nil)
        .accessibilityLabel(status == .unread ? "Non lu" : "Suivi")
    }
}

/// Unread counter: accent fill capsule, white semibold digits.
struct NatifCountCapsule: View {
    let count: Int
    @Environment(\.natif) private var natif

    var body: some View {
        Text(count, format: .number)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 21, minHeight: 21)
            .background(Capsule().fill(natif.accentFill))
            .accessibilityLabel("\(count) non lus")
    }
}

/// Red badge (Qualitay, tab badges outside the system `.badge`).
struct NatifRedBadge: View {
    let count: Int
    @Environment(\.natif) private var natif

    var body: some View {
        Text(count, format: .number)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(natif.destructive))
    }
}

// MARK: - Avatar

/// Remote avatar when available, otherwise a coloured circle with the pseudo's initial.
struct NatifAvatar: View {
    let pseudo: String?
    var image: UIImage? = nil
    var url: URL? = nil
    var size: CGFloat = 32

    private var initial: String {
        let trimmed = pseudo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let loaded) = phase {
                        loaded.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            if pseudo?.isEmpty == false {
                NatifAvatarColor.color(for: pseudo ?? "")
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Color.secondary.opacity(0.25)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.46))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Pictograms

/// 30 pt rounded square with an accent-tinted symbol, used by categories and the Plus tab.
struct NatifPictogram: View {
    let systemImage: String
    var tint: Color? = nil
    @Environment(\.natif) private var natif
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .font(.system(size: side * 0.6))
            .foregroundStyle(tint ?? natif.accent)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.27, style: .continuous).fill(natif.accentSoft))
            .accessibilityHidden(true)
    }
}

// MARK: - Empty states

struct NatifEmptyState: View {
    struct Action {
        let title: String
        let handler: () -> Void
    }

    let systemImage: String
    let title: String
    let message: String
    var primary: Action? = nil
    var secondary: Action? = nil
    /// On a grouped background `surface` blends in: use the cell colour for the fills instead.
    var onGroupedBackground = true
    @Environment(\.natif) private var natif

    private var fill: Color {
        onGroupedBackground ? natif.cell : natif.surface
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(natif.text2)
                .frame(width: 84, height: 84)
                .background(Circle().fill(fill))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(natif.text)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(natif.text2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 290)

            if primary != nil || secondary != nil {
                VStack(spacing: 10) {
                    if let primary {
                        Button(action: primary.handler) {
                            Text(primary.title)
                                .font(.headline)
                                .frame(minWidth: 200, minHeight: 48)
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(natif.accentFill))
                    }
                    if let secondary {
                        Button(action: secondary.handler) {
                            Text(secondary.title)
                                .font(.headline)
                                .frame(minWidth: 200, minHeight: 44)
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(natif.accent)
                        .background(Capsule().fill(fill))
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - List backgrounds

extension View {
    /// Grouped list on the theme's grouped background (needed for OLED black).
    func natifGroupedListBackground() -> some View {
        modifier(NatifListBackground(grouped: true))
    }

    func natifListBackground(grouped: Bool) -> some View {
        modifier(NatifListBackground(grouped: grouped))
    }

    /// Plain list on the theme's main background.
    func natifPlainListBackground() -> some View {
        modifier(NatifListBackground(grouped: false))
    }

    /// Cell background inside a grouped list.
    func natifCellBackground() -> some View {
        modifier(NatifCellBackground())
    }
}

private struct NatifListBackground: ViewModifier {
    let grouped: Bool
    @Environment(\.natif) private var natif

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background((grouped ? natif.bgGrouped : natif.bg).ignoresSafeArea())
            .toggleStyle(NatifSwitchToggleStyle())
    }
}

/// Switches use the filled shade of the colour, like segmented controls and buttons. With the text
/// shade, "Noir" gave white switches with a white knob in the dark themes.
struct NatifSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        NatifSwitch(configuration: configuration)
    }
}

private struct NatifSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.natif) private var natif

    var body: some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(natif.switchFill)
    }
}

private struct NatifCellBackground: ViewModifier {
    @Environment(\.natif) private var natif

    func body(content: Content) -> some View {
        content.listRowBackground(natif.cell)
    }
}

// MARK: - Navigation

extension View {
    /// System navigation subtitle (iOS 26+), e.g. the parent category under a sub-forum title.
    @ViewBuilder
    func hfrNavigationSubtitle(_ subtitle: String?) -> some View {
        if #available(iOS 26.0, *), let subtitle, !subtitle.isEmpty {
            self.navigationSubtitle(Text(subtitle))
        } else {
            self
        }
    }
}

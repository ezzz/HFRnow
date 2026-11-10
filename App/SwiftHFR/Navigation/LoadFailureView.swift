import SwiftUI

/// A failed load: full-screen when nothing is on screen yet, a compact banner when old content stays.
struct LoadFailureView: View {
    let error: ListLoadError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.symbol)
        } description: {
            Text(error.detail)
        } actions: {
            Button("Réessayer") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Banner above kept content.
struct LoadFailureBanner: View {
    let error: ListLoadError
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.symbol).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(error.title).scaledFont(.subheadline).bold()
                Text(error.detail).scaledFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Réessayer") { Task { await retry() } }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .onAppear { AccessibilityNotification.Announcement("\(error.title). \(error.detail)").post() }
    }
}

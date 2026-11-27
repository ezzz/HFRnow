import SwiftUI

/// What a screen shows while it has no content yet (#693): its failure first (a retry keeps it until a load succeeds, as
/// `ContentLoader` keeps the error), else a spinner while a load runs, else nothing.
enum ScreenLoadState: Equatable {
    case failed(ListLoadError)
    case loading
    case idle

    /// `isLoading` is explicit at every call site: a screen that waits for its first content whatever its loader says (the profile,
    /// the reader) passes true; one omitted by mistake would spin forever.
    init(error: ListLoadError?, isLoading: Bool) {
        if let error {
            self = .failed(error)
        } else {
            self = isLoading ? .loading : .idle
        }
    }
}

/// The one loading / failure view of a screen without content, built on `LoadFailureView` (#693).
struct ScreenStateView: View {
    let state: ScreenLoadState
    /// The spinner's label; none by default.
    var loadingLabel: LocalizedStringKey?
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .failed(let error):
            LoadFailureView(error: error, retry: retry)
        case .loading:
            // Centred in all the space it is given (an overlay, or the profile's body).
            spinner.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var spinner: some View {
        if let loadingLabel { ProgressView(loadingLabel) } else { ProgressView() }
    }
}

/// The one empty state of a screen (#693): what is missing, why, and a refresh; or, when refreshing cannot help, one other action
/// (Favoris without an account: "Ajouter un pseudo", #824).
struct EmptyStateView: View {
    let title: String
    let symbol: String
    var message: String?
    var action: (title: String, run: () -> Void)?
    let refresh: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let action {
                Button(action.title, action: action.run).buttonStyle(.borderedProminent)
            } else {
                Button("Actualiser") { Task { await refresh() } }
            }
        }
    }
}

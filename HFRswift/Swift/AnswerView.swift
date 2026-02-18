import SwiftUI

struct AnswerView: View {
    let topicURL: URL?
    private let replyPostingService: any ReplyPostingService
    private let onPostSuccess: ((ReplyPostingResult) -> Void)?

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool
    @FocusState.Binding var isComposerFocused: Bool

    @State private var message: String
    @State private var isPosting: Bool = false

    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastIsSuccess: Bool = true

    init(
        topicURL: URL?,
        replyPostingService: any ReplyPostingService = ForumReplyPostingService(),
        onPostSuccess: ((ReplyPostingResult) -> Void)? = nil,
        composerDraftText: Binding<String>,
        isComposerPresented: Binding<Bool>,
        isComposerFocused: FocusState<Bool>.Binding
    ) {
        self.topicURL = topicURL
        self.replyPostingService = replyPostingService
        self.onPostSuccess = onPostSuccess
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._isComposerFocused = isComposerFocused
        self._message = State(initialValue: composerDraftText.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $message)
                .focused($isComposerFocused)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button {
                    Task { await postMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.2) : Color.accentColor)
                        .foregroundColor(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .white)
                        .clipShape(Capsule())
                        .accessibilityLabel("Send")
                }
                .disabled(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding()
            }
        }
        .navigationTitle("Reply")
        .toolbarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showToast {
                ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
        .onAppear {
            message = composerDraftText
            DispatchQueue.main.async {
                isComposerFocused = true
            }
        }
        .onChange(of: message) { newValue in
            composerDraftText = newValue
        }
    }

    private func postMessage() async {
        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        guard let topicURL else {
            await presentToast(success: false, text: "URL manquante")
            return
        }

        do {
            let result = try await replyPostingService.postReply(message: message, topicURL: topicURL)
            await MainActor.run {
                onPostSuccess?(result)
            }
            await presentToast(success: true, text: "Hooray")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                message = ""
                composerDraftText = ""
                isComposerPresented = false
                isComposerFocused = false
            }
        } catch let error as ReplyPostingError {
            await presentToast(success: false, text: error.localizedDescription)
        } catch {
            await presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
    }

    @MainActor private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation {
            showToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

private struct AnswerViewPreviewWrapper: View {
    @State private var draft: String = ""
    @State private var presented: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            AnswerView(
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1#t100")!,
                composerDraftText: $draft,
                isComposerPresented: $presented,
                isComposerFocused: $focused
            )
        }
    }
}

#Preview {
    AnswerViewPreviewWrapper()
}

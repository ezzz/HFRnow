// AnswerView.swift
// SwiftUI view to compose and post a reply via HTTP POST
// Created by Assistant

import SwiftUI

struct AnswerView: View {
    // Pass the full answer endpoint URL from MessagesView
    let topicURL: URL?

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool
    @FocusState.Binding var isComposerFocused: Bool

    // Message content typed by the user
    @State private var message: String

    // Posting state
    @State private var isPosting: Bool = false

    // Toast presentation
    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastIsSuccess: Bool = true

    init(topicURL: URL?, composerDraftText: Binding<String>, isComposerPresented: Binding<Bool>, isComposerFocused: FocusState<Bool>.Binding) {
        self.topicURL = topicURL
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._isComposerFocused = isComposerFocused
        self._message = State(initialValue: composerDraftText.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $message)
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
        .onChange(of: message) { newValue in
            composerDraftText = newValue
        }
    }

    // MARK: - Networking
    private func postMessage() async {
        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        guard let topicURL = topicURL else {
            await presentToast(success: false, text: "URL manquante")
            return
        }

        // Prepare body similar to Objective-C version: key `content_form` with CRLFs
        var bodyString = message
        bodyString = bodyString.replacingOccurrences(of: "\n", with: "\r\n")

        // Build URLRequest
        var request = URLRequest(url: topicURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // URL-encode the form field
        let formBody = urlEncodedForm(["content_form": bodyString])
        request.httpBody = formBody.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            if 200..<300 ~= http.statusCode {
                // Basic success heuristic; you can parse HTML if needed later.
                await presentToast(success: true, text: "Hooray")
                // Optionally clear message on success
                message = ""
                composerDraftText = ""
            } else {
                // Try to extract server message for debugging
                let serverText = String(data: data, encoding: .utf8) ?? ""
                await presentToast(success: false, text: "Ooops")
                print("POST failed: status=\(http.statusCode) body=\(serverText)")
            }
        } catch {
            await presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
    }

    private func urlEncodedForm(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    @MainActor private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation {
            showToast = true
        }
        // Auto-dismiss after delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Toast UI
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

// MARK: - Preview
private struct AnswerViewPreviewWrapper: View {
    @State private var draft: String = ""
    @State private var presented: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            AnswerView(topicURL: URL(string: "https://example.com/post")!,
                       composerDraftText: $draft,
                       isComposerPresented: $presented,
                       isComposerFocused: $focused)
        }
    }
}

#Preview {
    AnswerViewPreviewWrapper()
}

import LocalAuthentication
import SwiftUI
import UIKit

/// `LAContext` with the `deviceOwnerAuthentication` policy: Face ID or Touch ID, then the device code. No PIN of our own.
struct LocalAuthenticationAuthenticator: DeviceOwnerAuthenticating {
    func availability() -> AppLockAvailability {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .available }
        if let error, error.domain == LAError.errorDomain, error.code == LAError.Code.passcodeNotSet.rawValue {
            return .passcodeNotSet
        }
        return .unavailable
    }

    func authenticate(reason: String) async -> AppLockOutcome {
        // A fresh context each time: a context that already succeeded would not ask again.
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .passcodeNotSet: return .passcodeNotSet
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

// New in SwiftHFR: none @ 87fe0d1c (legacy has no app lock; GAP-312). Differences: the whole feature.
/// What every scene shows while the app is locked, or not active with the lock on (the app switcher snapshot).
/// It appears without animation: it must be in place before the system takes the snapshot, so Reduce Motion has nothing
/// to reduce.
struct AppLockCover: View {
    let lock: AppLockModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if lock.isLocked {
                Text("HFR est verrouillé")
                    .font(.headline)
                Button("Déverrouiller") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(lock.isAuthenticating)
                if let message = lock.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// Covers this scene, sheets and alerts included, with `AppLockCover` while `lock.isCovered`, from a window of its own
    /// above the scene's windows; the content stays mounted underneath (no navigation, draft or scroll state is lost) and
    /// is hidden from VoiceOver meanwhile.
    func appLockCover(_ lock: AppLockModel) -> some View {
        accessibilityHidden(lock.isCovered)
            .background(AppLockWindowInstaller(lock: lock, isCovered: lock.isCovered))
    }
}

/// Puts one cover window in the scene of the view it is attached to, and shows or hides it.
private struct AppLockWindowInstaller: UIViewRepresentable {
    let lock: AppLockModel
    let isCovered: Bool

    func makeUIView(context: Context) -> AppLockAnchorView {
        AppLockAnchorView(lock: lock)
    }

    func updateUIView(_ view: AppLockAnchorView, context: Context) {
        view.setCovered(isCovered)
    }
}

/// An invisible view that finds its window scene and owns the scene's cover window.
private final class AppLockAnchorView: UIView {
    private let lock: AppLockModel
    private var cover: UIWindow?
    private var isCovered = false

    init(lock: AppLockModel) {
        self.lock = lock
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if cover == nil, let scene = window?.windowScene {
            let cover = UIWindow(windowScene: scene)
            // Above sheets and alerts of the scene's own windows.
            cover.windowLevel = .alert + 1
            let host = UIHostingController(rootView: AppLockCover(lock: lock))
            host.view.accessibilityViewIsModal = true
            cover.rootViewController = host
            self.cover = cover
        }
        apply()
    }

    func setCovered(_ covered: Bool) {
        isCovered = covered
        apply()
    }

    private func apply() {
        cover?.isHidden = !isCovered
    }
}

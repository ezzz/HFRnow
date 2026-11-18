import Foundation
import UIKit

/// Where the main actor last was, readable from a watchdog thread: a main-thread hang never reaches the next step, and
/// `.timeLimit` cannot end it (it cancels, and a hung main thread never checks), so the watchdog names the step and ends the run.
/// Every step goes to stderr as `[<tag>] <step>`: read the step a hang stopped after there (the xcodebuild log, or the test's
/// standard error in the result bundle), on the `[<tag>] HANG` line. Shared by the hosted freeze tests (#979, #681).
final class HostedHangWatchdog: @unchecked Sendable {
    private let tag: String
    private let lock = NSLock()
    private var step = "start"
    private var beat = Date()
    private var stopped = false

    init(tag: String) { self.tag = tag }

    func mark(_ name: String) {
        lock.withLock {
            step = name
            beat = Date()
        }
        FileHandle.standardError.write(Data("[\(tag)] \(name)\n".utf8))
    }

    func heartbeat() { lock.withLock { beat = Date() } }

    /// Ends the watch with the test: a watchdog that outlives it would end the host in the middle of another test.
    func stop() { lock.withLock { stopped = true } }

    /// Watches the main actor for `limit` seconds of silence. The limit is far above a slow first hosting on a loaded runner
    /// (the steps beat every 50 ms) and under the test's 60 s `.timeLimit`. The end is a crash, not `exit`: an exit made the run
    /// relaunch and report its remaining tests as passed, while a crash is reported against this test with its message.
    func watch(limit: TimeInterval) {
        Thread.detachNewThread { [self] in
            while true {
                Thread.sleep(forTimeInterval: 1)
                let (done, step, silence) = lock.withLock { (stopped, step, Date().timeIntervalSince(beat)) }
                if done { return }
                if silence > limit {
                    let message = "[\(tag)] HANG: main actor silent \(Int(silence)) s after '\(step)'"
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    fatalError(message)
                }
            }
        }
    }
}

/// Accessibility helpers of the hosted tests that activate the app's real controls, as a UI test or VoiceOver would.
@MainActor
enum HostedAccessibility {
    /// Every accessibility element and view under `root`.
    static func elements(under root: NSObject) -> [NSObject] {
        var found: [NSObject] = []
        var stack: [NSObject] = [root]
        while let node = stack.popLast(), found.count < 5_000 {
            found.append(node)
            if let children = node.accessibilityElements as? [NSObject] {
                stack.append(contentsOf: children)
            } else {
                let count = node.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    stack.append(contentsOf: (0..<count).compactMap { node.accessibilityElement(at: $0) as? NSObject })
                }
            }
            if let view = node as? UIView { stack.append(contentsOf: view.subviews) }
        }
        return found
    }

    /// The tests that use the accessibility tree now. It is process-wide: a test that turned it off while another still
    /// looked up elements would fail that one when suites run in parallel, so it goes off only when the last user leaves.
    private static var automation = AutomationUsers()

    /// Turns SwiftUI's accessibility tree on for the caller; pair it with `endAutomation()`.
    static func beginAutomation() {
        if automation.enter() { setAutomation(true) }
    }

    /// The caller is done with the accessibility tree; it goes off with the last caller.
    static func endAutomation() {
        if automation.leave() { setAutomation(false) }
    }

    /// Turns SwiftUI's accessibility tree on or off: it is built only for an assistive technology, as UI tests turn it on.
    private static func setAutomation(_ isOn: Bool) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Void).self)(isOn ? 1 : 0)
    }
}

/// Counts the users of a shared switch: on with the first, off with the last.
struct AutomationUsers {
    private(set) var active = 0

    /// A user arrives; true when the switch must turn on.
    mutating func enter() -> Bool {
        active += 1
        return active == 1
    }

    /// A user leaves; true when the switch must turn off. A leave without an enter changes nothing.
    mutating func leave() -> Bool {
        guard active > 0 else { return false }
        active -= 1
        return active == 0
    }
}

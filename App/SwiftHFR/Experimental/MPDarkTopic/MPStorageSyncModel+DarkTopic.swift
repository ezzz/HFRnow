import HFRModels

// EXPERIMENTAL(mpDarkTopic, #858): adds legacy's flag write to the flags LOT-130 only read.
// Port of HFRswift/Swift/MessagesView.swift (updateMPStorageFlagIfNeeded, :3582-3606) and Classes/MPStorage.m
// (updateMPFlagAsynchronous:, :403-417) @ 87fe0d1c. Differences: legacy read and wrote the forum at every page load; the flag
// moves in the device copy and goes with one sync when the conversation is left.
extension MPStorageSyncModel {
    /// Moves `thread`'s flag to `reached` in the device copy (forward only, `MPStorageDocument.moveMPFlag`), nothing sent. Only
    /// for a group conversation (legacy, `MessagesView.swift:3586`), while `on` and the option is on. A copy that cannot take it
    /// loses the flag, never the app's own position (`MPReadingPositions`).
    func moveFlag(of thread: PrivateMessageThread, to reached: MPReachedMessage) async {
        guard thread.isGroup, let topic = thread.summary.topicID?.topic else { return }
        let flag = reached.flag(topic: topic, rowLink: thread.summary.path)
        if await editLocally(.mpFlags, { document, stamp in try document.moveMPFlag(flag, stamp: stamp) }) { flagsMoved = true }
    }

    /// Sends the flags `moveFlag(of:to:)` moved since the last call, in one sync; nothing when none moved. What stays unsent (a
    /// failure, the app closed first) goes with the next sync, which writes every local edit.
    func sendMovedFlags() async {
        guard flagsMoved, isOn else { return }
        flagsMoved = false
        await resync()
    }
}

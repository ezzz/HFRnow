extension AccountsModel {
    /// Reads the store again once the restore in progress (if any) has ended: accounts written meanwhile by another writer
    /// (the legacy import, LOT-158) are then listed. `retryRestore()` alone would only wait for that restore, which may
    /// have read the store before the write.
    func readStoreAgain() async {
        await restore()
        await retryRestore()
    }
}

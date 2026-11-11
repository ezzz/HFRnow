import HFRStorage

extension AccountsModel {
    /// Deletes the Keychain item itself when it holds no account any more, so a wipe of the last account leaves no
    /// credential item on the device (LOT-157). Does nothing while an account is stored.
    func removeStoreItemIfEmpty() throws(AccountActionError) {
        do {
            guard try store.load().accounts.isEmpty else { return }
            try store.removeAll()
        } catch {
            throw (error as? CredentialStoreError).map(AccountActionError.store) ?? .storeFailed
        }
    }
}

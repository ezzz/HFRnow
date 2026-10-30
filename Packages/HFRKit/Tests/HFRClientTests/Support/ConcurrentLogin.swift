/// What a login adopted by another task leaves in a scripted session: its identity and the token read with its cookies.
struct ConcurrentLogin: Sendable {
    /// The `md_user` value after the login; another value than the session's is an account switch.
    let identity: String?
    /// The fresher token.
    let hashCheck: String
}

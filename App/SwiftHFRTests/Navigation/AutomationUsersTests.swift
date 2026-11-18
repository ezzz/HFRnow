import Testing

/// The shared accessibility switch of the hosted tests goes off only with its last user (#1083 review: parallel suites).
struct AutomationUsersTests {
    @Test("On with the first user, off with the last")
    func onWithTheFirstOffWithTheLast() {
        var users = AutomationUsers()
        let switches = [users.enter(), users.enter(), users.leave(), users.leave()]
        #expect(switches == [true, false, false, true])
        #expect(users.count == 0)
    }

    @Test("A leave without an enter changes nothing")
    func aStrayLeaveChangesNothing() {
        var users = AutomationUsers()
        let stray = users.leave()
        #expect(!stray)
        #expect(users.count == 0)
        let first = users.enter()
        #expect(first)
    }
}

import Foundation

extension HFREndpoint {
    /// Login POST to `/login_validation.php?config=hfr.inc` (`LoginService.swift:51-68`, captures `W01`, `W01b`, `W03`).
    ///
    /// Fields `pseudo, password, action=send, login=Se connecter` (the legacy fields, HFR-PROTOCOL §5), in the
    /// order of the captured requests (`request_fields` of `W01`, `W01b`, `W03`): legacy built them from a
    /// dictionary, whose order is undefined (`LoginService.swift:62-68, 143-149`).
    /// Values are sent as given: trimming the pseudo and refusing empty credentials belong to the
    /// caller. The answer is HTTP 200 whether the login succeeded or not; send it through a session whose jar may take
    /// the new cookies (LOT-043 uses a fresh one).
    public static func login(pseudo: String, password: String) throws -> HTTPRequest {
        try .post(
            url(path: "/login_validation.php", query: [("config", config)]),
            form: FormBody([
                ("pseudo", pseudo),
                ("password", password),
                ("action", "send"),
                ("login", "Se connecter")
            ])
        )
    }
}

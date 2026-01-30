//
//  LoginService.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//

import Foundation

struct LoginResult {
    let displayPseudo: String
    let pseudoKey: String
    let cookies: [HTTPCookie]
    let avatarData: Data?
    let hash: String
}

enum LoginError: LocalizedError {
    case invalidCredentials
    case invalidResponse
    case missingHash
    case missingPseudoCookie
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Pseudo ou mot de passe incorrect."
        case .invalidResponse:
            return "Réponse serveur invalide."
        case .missingHash:
            return "Impossible de récupérer le hash du compte."
        case .missingPseudoCookie:
            return "Cookie d'identification introuvable."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

final class LoginService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(pseudo: String, password: String) async throws -> LoginResult {
        clearCookies()

        let baseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr")!
        let loginURL = baseURL.appendingPathComponent("login_validation.php")
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "config", value: "hfr.inc")]
        guard let requestURL = components?.url else {
            throw LoginError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "pseudo": pseudo,
            "password": password,
            "action": "send",
            "login": "Se connecter"
        ])
        .data(using: .utf8)

        let (loginData, _) = try await session.data(for: request)
        let loginHTML = decodeHTML(loginData)
        guard loginHTML.contains("login_redirection.php") else {
            throw LoginError.invalidCredentials
        }

        let profileURL = baseURL.appendingPathComponent("user/editprofil.php")
        var profileComponents = URLComponents(url: profileURL, resolvingAgainstBaseURL: false)
        profileComponents?.queryItems = [
            URLQueryItem(name: "config", value: "hfr.inc"),
            URLQueryItem(name: "page", value: "5")
        ]
        guard let profileRequestURL = profileComponents?.url else {
            throw LoginError.invalidResponse
        }

        let (profileData, _) = try await session.data(from: profileRequestURL)
        let profileHTML = decodeHTML(profileData)

        guard let hash = firstMatch(in: profileHTML, pattern: "name=\\\"hash_check\\\"[^>]*value=\\\"([^\\\"]+)\\\"") else {
            throw LoginError.missingHash
        }

        let avatarURLString = firstMatch(
            in: profileHTML,
            pattern: "profilCase3[\\s\\S]*?<img[^>]*src=\\\"([^\\\"]+)\\\"",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        var avatarData: Data?
        if let avatarURLString, let avatarURL = URL(string: avatarURLString, relativeTo: baseURL) {
            avatarData = try? await session.data(from: avatarURL).0
        }

        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            cookie.domain.contains("hardware.fr")
        }
        guard let pseudoKey = cookies.first(where: { $0.name == "md_user" && $0.value != "deleted" })?.value else {
            throw LoginError.missingPseudoCookie
        }

        return LoginResult(
            displayPseudo: pseudo,
            pseudoKey: pseudoKey,
            cookies: cookies,
            avatarData: avatarData,
            hash: hash
        )
    }

    private func clearCookies() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }

    private func decodeHTML(_ data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(escapeForm(key))=\(escapeForm(value))"
            }
            .joined(separator: "&")
    }

    private func escapeForm(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    private func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let matchRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[matchRange])
    }
}

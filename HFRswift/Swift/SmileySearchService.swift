import Foundation

// MARK: - Search Protocol

protocol SmileySearching: Sendable {
    func search(query: String) async throws -> [ReplySmiley]
}

// MARK: - HFR Implementation

/// Appelle l'API HFR de recherche de smileys par mot-clé.
/// URL : https://forum.hardware.fr/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+mot1+mot2
/// Réponse : HTML contenant des balises <img src="…" alt="code_smiley">
struct HFRSmileySearchService: SmileySearching {
    private static let baseURL = "https://forum.hardware.fr"

    func search(query: String) async throws -> [ReplySmiley] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        // Chaque mot est préfixé par "+" (recherche full-text HFR)
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let formattedQuery = words.map { "+\($0)" }.joined(separator: " ")

        var components = URLComponents(string: "\(Self.baseURL)/message-smi-mp-aj.php")!
        components.queryItems = [
            URLQueryItem(name: "config", value: "hfr.inc"),
            URLQueryItem(name: "findsmilies", value: formattedQuery)
        ]
        guard let url = components.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return []
        }

        // Pages HFR en ISO-8859-1 ; les URL d'images passent en UTF-8 aussi
        let html = String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .utf8)
                ?? ""
        return parseSmileys(from: html)
    }

    private func parseSmileys(from html: String) -> [ReplySmiley] {
        // Extrait chaque balise <img …> puis en lit src et alt indépendamment de leur ordre
        guard
            let imgRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive),
            let srcRegex = try? NSRegularExpression(pattern: #"\bsrc="([^"]+)""#, options: .caseInsensitive),
            let altRegex = try? NSRegularExpression(pattern: #"\balt="([^"]*)""#, options: .caseInsensitive)
        else { return [] }

        var results: [ReplySmiley] = []
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)

        for imgMatch in imgRegex.matches(in: html, range: fullRange) {
            let imgStr = nsHTML.substring(with: imgMatch.range) as NSString
            let imgRange = NSRange(location: 0, length: imgStr.length)
            guard
                let srcMatch = srcRegex.firstMatch(in: imgStr as String, range: imgRange),
                let altMatch = altRegex.firstMatch(in: imgStr as String, range: imgRange),
                srcMatch.numberOfRanges >= 2, altMatch.numberOfRanges >= 2,
                srcMatch.range(at: 1).location != NSNotFound,
                altMatch.range(at: 1).location != NSNotFound
            else { continue }

            let src = imgStr.substring(with: srcMatch.range(at: 1))
            let alt = imgStr.substring(with: altMatch.range(at: 1))
            guard !alt.isEmpty, let imageURL = URL(string: src) else { continue }
            results.append(ReplySmiley(code: alt, imageSource: .remote(imageURL)))
        }
        return results
    }
}

// MARK: - Search History

struct SmileySearchHistoryEntry: Codable, Identifiable {
    var id: String { text }
    let text: String
    var count: Int
    var lastDate: Date
}

/// Persistance des recherches de smileys réussies.
/// - Enregistre chaque recherche (≥ 3 chars) qui retourne au moins un résultat.
/// - Expose deux vues triées : récentes (par date) et fréquentes (par compteur).
enum SmileySearchHistoryStore {
    private static let key = "smileySearchHistory_v1"
    private static let maxEntries = 50

    static func load() -> [SmileySearchHistoryEntry] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let entries = try? JSONDecoder().decode([SmileySearchHistoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    /// Enregistre ou incrémente une recherche.  Ignorée si trop courte ou sans résultat.
    static func record(query: String, resultCount: Int) {
        guard query.count >= 3, resultCount > 0 else { return }
        var entries = load()
        if let idx = entries.firstIndex(where: { $0.text.caseInsensitiveCompare(query) == .orderedSame }) {
            entries[idx].count += 1
            entries[idx].lastDate = Date()
        } else {
            entries.append(SmileySearchHistoryEntry(text: query, count: 1, lastDate: Date()))
        }
        if entries.count > maxEntries {
            entries.sort { $0.lastDate > $1.lastDate }
            entries = Array(entries.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Dernières recherches (triées par date desc), filtrées par le texte en cours.
    static func recentSuggestions(matching text: String, limit: Int = 5) -> [SmileySearchHistoryEntry] {
        filtered(matching: text)
            .sorted { $0.lastDate > $1.lastDate }
            .prefix(limit)
            .map { $0 }
    }

    /// Recherches les plus fréquentes (triées par compteur desc), filtrées par le texte en cours.
    static func topSuggestions(matching text: String, limit: Int = 10) -> [SmileySearchHistoryEntry] {
        filtered(matching: text)
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    private static func filtered(matching text: String) -> [SmileySearchHistoryEntry] {
        let entries = load()
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(text) }
    }
}

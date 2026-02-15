//
//  AQPlusView.swift
//  HFRswift
//
//  SwiftUI migration of Plus > Alertes Qualitay list
//

import SwiftUI
import Foundation
import Combine

struct AQItem: Identifiable, Hashable {
    let topicTitle: String
    let aqTitle: String
    let comment: String
    let initiator: String
    let relativeDate: String
    let link: String
    let isNew: Bool

    var id: String { "\(link)|\(aqTitle)|\(relativeDate)" }
}

private struct AQParserContext {
    let lastCheckDate: Date
    let shouldFilterCategory25: Bool
}

private final class AQRSSParserDelegate: NSObject, XMLParserDelegate {
    private struct WorkingItem {
        var title = ""
        var link = ""
        var description = ""
        var relativeDate = ""
        var isNew = false
        var topicTitle = "(sans titre)"
        var number = "0"
        var initiator = "(sans auteur)"
        var comment = ""
    }

    private let context: AQParserContext
    private var currentText = ""
    private var workingItem: WorkingItem?

    private(set) var items: [AQItem] = []

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E, d MMM yy HH:mm:ss Z"
        return formatter
    }()

    init(context: AQParserContext) {
        self.context = context
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == "item" {
            workingItem = WorkingItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var item = workingItem else { return }
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            item.title = value
        case "link":
            item.link = value
        case "description":
            item.description = value
            parseDescription(into: &item)
        case "pubDate":
            parsePublicationDate(value, into: &item)
        case "item":
            if shouldKeep(item: item) {
                items.append(
                    AQItem(
                        topicTitle: item.topicTitle,
                        aqTitle: item.title,
                        comment: item.comment,
                        initiator: item.initiator,
                        relativeDate: item.relativeDate,
                        link: item.link,
                        isNew: item.isNew
                    )
                )
            }
            workingItem = nil
        default:
            break
        }

        if elementName != "item" {
            workingItem = item
        }
        currentText = ""
    }

    private func shouldKeep(item: WorkingItem) -> Bool {
        guard !item.link.isEmpty else { return false }
        if context.shouldFilterCategory25 && item.link.contains("&cat=25&post") {
            return false
        }
        return true
    }

    private func parseDescription(into item: inout WorkingItem) {
        if item.description.contains("Pour ne rien rater du meilleur d'HFR, en toutes circonstances") {
            return
        }

        if let topic = Self.firstCapture(pattern: #"detect[ée]e[^<]*<b>([^<]+)"#, in: item.description), !topic.isEmpty {
            item.topicTitle = topic
        }
        if let number = Self.firstCapture(pattern: #"signal[ée]e[^<]*<b>([^<]+)"#, in: item.description), !number.isEmpty {
            item.number = number
        }
        if let initiator = Self.firstCapture(pattern: #">([^<]+)\s+\(initiateur\)"#, in: item.description), !initiator.isEmpty {
            item.initiator = initiator.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let comment = Self.firstCapture(pattern: #"\(initiateur\)</b>\s*:\s*([^<]+)"#, in: item.description), !comment.isEmpty {
            item.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func parsePublicationDate(_ value: String, into item: inout WorkingItem) {
        let now = Date()
        let aqDate = Self.sourceDateFormatter.date(from: value) ?? now
        item.isNew = aqDate >= context.lastCheckDate
        item.relativeDate = Self.relativeDateLabel(since: aqDate, now: now)
    }

    private static func relativeDateLabel(since date: Date, now: Date) -> String {
        let interval = max(0, Int(now.timeIntervalSince(date)))
        let numberHours = interval / 3600
        let numberDays = interval / (24 * 3600)
        let numberMonths = numberDays / 31
        let numberYears = numberDays / 365

        if numberHours <= 1 {
            return "il y a 1 h"
        }
        if numberHours <= 23 {
            return "il y a \(numberHours) h"
        }
        if numberDays <= 30 {
            return "il y a \(numberDays) j"
        }
        if numberMonths <= 12 {
            return "il y a \(numberMonths) mois"
        }
        if numberYears <= 1 {
            return "il y a 1 an"
        }
        return "il y a \(numberYears) ans"
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let captureRange = match.range(at: 1)
        guard let swiftRange = Range(captureRange, in: text) else { return nil }
        return String(text[swiftRange])
    }
}

@MainActor
final class AQPlusViewModel: ObservableObject {
    @Published var items: [AQItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession
    private var task: URLSessionDataTask?
    private var requestID = 0

    init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        task?.cancel()
    }

    func refresh() {
        requestID += 1
        let currentRequestID = requestID
        task?.cancel()

        guard let url = URL(string: "https://aq.super-h.fr/rss.php") else {
            errorMessage = "URL AQ invalide"
            return
        }

        isLoading = true
        errorMessage = nil

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        task = session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            Task { @MainActor in
                guard currentRequestID == self.requestID else { return }
                self.isLoading = false

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data else {
                    self.errorMessage = "Données AQ introuvables"
                    return
                }

                let context = AQParserContext(
                    lastCheckDate: self.lastCheckDate(),
                    shouldFilterCategory25: self.shouldFilterCategory25()
                )
                let parserDelegate = AQRSSParserDelegate(context: context)
                let parser = XMLParser(data: data)
                parser.delegate = parserDelegate
                guard parser.parse() else {
                    self.errorMessage = parser.parserError?.localizedDescription ?? "Parsing AQ impossible"
                    return
                }

                self.items = parserDelegate.items
                self.errorMessage = nil
                UserDefaults.standard.set(Date(), forKey: "last_check_aq")
            }
        }
        task?.resume()
    }

    private func lastCheckDate() -> Date {
        if let date = UserDefaults.standard.object(forKey: "last_check_aq") as? Date {
            return date
        }
        var comps = DateComponents()
        comps.year = 2010
        comps.month = 1
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    private func shouldFilterCategory25() -> Bool {
        let manager = MultisManager.sharedManager() as? MultisManager
        guard let pseudo = manager?.getCurrentPseudo()?.lowercased(), !pseudo.isEmpty else {
            return true
        }
        return pseudo == "applereview"
    }
}

struct AQPlusView: View {
    @StateObject private var viewModel: AQPlusViewModel
    @State private var hasLoaded = false

    @MainActor
    init(viewModel: AQPlusViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AQPlusViewModel())
    }

    private func normalizedForumTopicURLString(from rawLink: String) -> String {
        guard let url = URL(string: rawLink) else { return rawLink }
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        guard (scheme == "http" || scheme == "https"), host == "forum.hardware.fr" else {
            return rawLink
        }

        var relativeURL = url.path
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery, !query.isEmpty {
            relativeURL += "?\(query)"
        }
        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment, !fragment.isEmpty {
            relativeURL += "#\(fragment)"
        }
        return relativeURL.isEmpty ? "/" : relativeURL
    }

    private func topic(for item: AQItem) -> Topic {
        let topic = Topic()
        topic._aTitle = item.topicTitle
        let normalizedURL = normalizedForumTopicURLString(from: item.link)
        topic.aURL = normalizedURL
        topic.aURLOfLastPage = normalizedURL
        topic.curTopicPage = 1
        topic.maxTopicPage = 1
        return topic
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Chargement...")
                    Spacer()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundStyle(.red)
            }

            if !viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                Text("Aucune AQ")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.items) { item in
                NavigationLink {
                    MessagesView(
                        topic: topic(for: item),
                        curPage: 1,
                        maxPage: 1,
                        separatorNewMessages: true
                    )
                    .toolbar(.hidden, for: .tabBar)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.topicTitle)
                            .font(.headline)
                            .fontWeight(item.isNew ? .bold : .regular)
                        Text(item.aqTitle)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if !item.comment.isEmpty {
                            Text(item.comment)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text("par \(item.initiator) \(item.relativeDate)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Alertes Qualitay")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button("Actualiser", systemImage: "arrow.clockwise") {
                        viewModel.refresh()
                    }
                }
            }
        }
        .onAppear {
            if !hasLoaded {
                viewModel.refresh()
                hasLoaded = true
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }
}

#Preview("AQ Plus") {
    NavigationStack {
        AQPlusView()
    }
}

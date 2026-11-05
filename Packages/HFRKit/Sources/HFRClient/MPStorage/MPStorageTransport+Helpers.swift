import Foundation
import HFRModels
import HFRNetwork

extension MPStorageTransport {
    /// One GET through the session; nothing has been written, so every failure is a plain `network` one.
    static func get(_ request: HTTPRequest, through session: any PostingSession) async throws(MPStorageTransportError)
        -> HTTPResponse {
        if Task.isCancelled { throw .network(.cancelled) }
        do {
            return try await session.send(request)
        } catch {
            throw .network(error)
        }
    }

    /// Runs an endpoint builder, whose refusals are `NetworkError.invalidRequest`.
    static func endpoint(_ build: () throws -> HTTPRequest) throws(MPStorageTransportError) -> HTTPRequest {
        do {
            return try build()
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "endpoint"))
        }
    }

    /// The first message's edit link: the composer path with this thread and this message, in a private category
    /// (`R60a`'s toolbar: `/message.php?config=hfr.inc&cat=prive&post=<post>&numreponse=<n>&…`, HFR-PROTOCOL §6c LOT-031).
    static func isEditLink(_ url: URL, post: Int, numreponse: Int) -> Bool {
        guard
            PostingFlow.isForumPage(url),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.path == "/message.php"
        else { return false }
        let items = components.queryItems ?? []
        func value(_ name: String) -> [String?] { items.filter { $0.name == name }.map(\.value) }
        return value("cat") == [CategoryID.privateMessages.queryValue]
            && value("post") == [String(post)]
            && value("numreponse") == [String(numreponse)]
    }

    /// An edit form of this thread's first message, whose subject is the storage subject (`R60b`): `post`,
    /// `numreponse` and `sujet` as expected, in a private category.
    static func isStorageForm(_ form: PostingForm, at location: MPStorageLocation) -> Bool {
        let fields = form.form
        return form.shape == .edit
            && form.isPrivateThread
            && fields.field(named: "post")?.value == String(location.post)
            && fields.field(named: "numreponse")?.value == String(location.numreponse)
            && fields.field(named: "sujet")?.value == MPStorageDocument.subject
    }

    /// The document text to post, through LOT-062's write guards.
    static func encode(_ document: MPStorageDocument) throws(MPStorageTransportError) -> String {
        do {
            return try MPStorageCodec.encodeForWriting(document)
        } catch {
            throw documentError(error)
        }
    }

    static func documentError(_ error: any Error) -> MPStorageTransportError {
        (error as? MPStorageError).map { .document($0) } ?? .invalidDocument
    }

    /// Legacy's new document (`MPStorage.m:740`): one `0.1` entry with the three empty sections, every level stamped.
    static func emptyDocument(stamp: MPStorageStamp) -> MPStorageDocument {
        func section<Item>() -> MPStorageSection<Item> {
            MPStorageSection(sourceName: stamp.sourceName, lastUpdate: stamp.date)
        }
        let entry = MPStorageEntry(
            blocklist: section(), mpFlags: section(), bookmarks: section(), sourceName: stamp.sourceName, lastUpdate: stamp.date
        )
        return MPStorageDocument(data: [entry], sourceName: stamp.sourceName, lastUpdate: stamp.date)
    }
}

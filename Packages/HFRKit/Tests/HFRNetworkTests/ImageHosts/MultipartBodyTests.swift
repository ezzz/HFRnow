import Foundation
import Testing
@testable import HFRNetwork

struct MultipartBodyTests {
    /// Legacy `makeMultipartBody` (`ReplyService.swift:2045-2060` @ 2440d79) written out byte for byte, as the oracle.
    @Test func matchesTheLegacyUploadLayout() {
        let jpeg = Data([0xFF, 0xD8, 0x00, 0x0D, 0x0A, 0xFF, 0xD9])
        let body = MultipartBody(boundary: "Boundary-TEST", parts: [
            .text(name: "imageCaption", value: "Some Caption"),
            .file(name: "source", filename: "snapshot_7.jpg", contentType: "image/jpeg", data: jpeg)
        ])
        var expected = Data()
        expected.append(Data("--Boundary-TEST\r\nContent-Disposition: form-data; name=\"imageCaption\"\r\n\r\nSome Caption\r\n".utf8))
        expected.append(Data("--Boundary-TEST\r\nContent-Disposition: form-data; name=\"source\"; filename=\"snapshot_7.jpg\"\r\n".utf8))
        expected.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        expected.append(jpeg)
        expected.append(Data("\r\n--Boundary-TEST--\r\n".utf8))
        #expect(body.data == expected)
        #expect(body.contentType == "multipart/form-data; boundary=Boundary-TEST")
    }

    @Test func quotesAndLineBreaksInNamesCannotEscapeTheHeader() throws {
        let body = MultipartBody(boundary: "B", parts: [
            .file(name: "a\"b", filename: "x\".jpg\r\nX-Evil: 1", contentType: "image/jpeg\r\nX-Evil: 2", data: Data())
        ])
        let text = try #require(String(bytes: body.data, encoding: .utf8))
        #expect(text.contains("name=\"a%22b\""))
        #expect(text.contains("filename=\"x%22.jpg%0D%0AX-Evil: 1\""))
        // No header line of its own: the injected text stays inside an existing line.
        #expect(!text.contains("\r\nX-Evil"))
        #expect(text.contains("Content-Type: image/jpegX-Evil: 2\r\n"))
    }

    @Test func defaultBoundaryIsRandomPerBody() {
        #expect(MultipartBody(parts: []).boundary != MultipartBody(parts: []).boundary)
    }
}

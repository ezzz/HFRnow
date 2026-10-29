import Foundation
import Testing
@testable import HFRNetwork

struct RehostConfigurationTests {
    private func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test func buildsTheLegacyUploadURL() throws {
        let configuration = try RehostConfiguration(baseURL: url("https://img.example"), apiKey: "FAKEKEY")
        #expect(try configuration.uploadURL().absoluteString == "https://img.example/api/1/upload/?key=FAKEKEY")
        let withPath = try RehostConfiguration(baseURL: url("https://img.example/sub/"), apiKey: "FAKEKEY")
        #expect(try withPath.uploadURL().absoluteString == "https://img.example/sub/api/1/upload/?key=FAKEKEY")
    }

    @Test func encodesTheKeyAndTrimsIt() throws {
        let configuration = try RehostConfiguration(baseURL: url("https://img.example"), apiKey: " a&b=c+d \n")
        #expect(try configuration.uploadURL().query == "key=a%26b%3Dc%2Bd")
    }

    @Test func aMissingKeyMeansTheFeatureIsOff() throws {
        for key in ["", "   ", "\n"] {
            #expect(throws: RehostError.notConfigured) { try RehostConfiguration(baseURL: url("https://img.example"), apiKey: key) }
        }
    }

    @Test func theKeyNeverTravelsInClearOffLoopback() throws {
        for text in ["http://img.example", "ftp://img.example", "https:///x", "file:///x", "http://127.0.0.1.evil.example"] {
            #expect(throws: RehostError.invalidBaseURL) { try RehostConfiguration(baseURL: url(text), apiKey: "FAKEKEY") }
        }
        _ = try RehostConfiguration(baseURL: url("http://127.0.0.1:8080"), apiKey: "FAKEKEY")
        _ = try RehostConfiguration(baseURL: url("http://localhost"), apiKey: "FAKEKEY")
    }

    @Test func refusesCredentialsQueryAndFragmentInTheBaseURL() throws {
        for text in ["https://user:pw@img.example", "https://user@img.example", "https://img.example?token=1", "https://img.example/#x"] {
            #expect(throws: RehostError.invalidBaseURL) { try RehostConfiguration(baseURL: url(text), apiKey: "FAKEKEY") }
        }
    }

    @Test func descriptionsDoNotShowTheKey() throws {
        let configuration = try RehostConfiguration(baseURL: url("https://img.example"), apiKey: "FAKEKEY")
        #expect(!"\(configuration)".contains("FAKEKEY"))
        #expect(!String(reflecting: configuration).contains("FAKEKEY"))
        #expect(!String(describing: RehostError.http(statusCode: 400, message: nil)).contains("FAKEKEY"))
    }
}

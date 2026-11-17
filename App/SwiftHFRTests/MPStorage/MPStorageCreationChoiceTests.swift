import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The creation question as a choice (#1014): « Oui » preselected, a confirmation before a « Non », and nothing created without « Oui ».
@MainActor
struct MPStorageCreationChoiceTests {
    private typealias Base = MPStorageSyncModelTests

    @Test func ouiIsPreselected() {
        let choice = MPStorageCreationChoice()
        #expect(choice.answer == .oui)
        #expect(!choice.asksRefusalConfirmation)
        #expect(MPStorageCreationChoice.Answer.allCases.map(\.label) == ["Oui", "Non"])
    }

    @Test func ouiDecidesToCreateWithoutAConfirmation() {
        let choice = MPStorageCreationChoice()
        #expect(choice.validate() == .create)
        #expect(!choice.asksRefusalConfirmation)
    }

    /// Deselecting « Oui » decides nothing: the popup asks first.
    @Test func nonAsksForAConfirmationAndDecidesNothing() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        #expect(choice.validate() == nil)
        #expect(choice.asksRefusalConfirmation)
    }

    @Test func confirmingTheRefusalDeclines() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        _ = choice.validate()
        #expect(choice.confirmRefusal() == .decline)
        #expect(!choice.asksRefusalConfirmation)
    }

    @Test func goingBackKeepsTheQuestionAndTheSelection() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        _ = choice.validate()
        choice.goBack()
        #expect(!choice.asksRefusalConfirmation)
        #expect(choice.answer == .non)
        choice.answer = .oui
        #expect(choice.validate() == .create)
    }

    /// No write without « Oui »: neither the question left open, nor « Non », nor going back creates the storage message.
    @Test func theStorageMessageIsNeverCreatedWithoutOui() async throws {
        let fixture = try await Base.make(thread: nil, state: .off)
        await fixture.model.setEnabled(true)
        #expect(fixture.model.asksCreation)
        #expect(await fixture.remote.calls == [.find]) // asked, nothing written
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        #expect(choice.validate() == nil)
        choice.goBack()
        #expect(await fixture.remote.calls == [.find])
        _ = choice.validate()
        let decision = choice.confirmRefusal()
        await fixture.model.answerCreation(decision == .create)
        #expect(fixture.model.record?.state == .declined)
        #expect(await fixture.remote.calls == [.find])
    }

    @Test func ouiCreatesTheStorageMessage() async throws {
        let fixture = try await Base.make(thread: nil, state: .off)
        await fixture.model.setEnabled(true)
        let decision = try #require(MPStorageCreationChoice().validate())
        await fixture.model.answerCreation(decision == .create)
        #expect(fixture.model.isOn)
        #expect(await fixture.remote.calls == [.find, .create])
    }
}

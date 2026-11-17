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

    /// Deselecting « Oui » raises the popup at once and decides nothing.
    @Test func deselectingOuiAsksForAConfirmationAndDecidesNothing() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        #expect(choice.asksRefusalConfirmation)
        #expect(choice.validate() == nil)
        #expect(choice.asksRefusalConfirmation)
    }

    @Test func confirmingTheRefusalDeclines() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        #expect(choice.confirmRefusal() == .decline)
        #expect(!choice.asksRefusalConfirmation)
    }

    /// « Revenir » puts « Oui » back, and a new deselection asks again.
    @Test func goingBackRestoresOuiAndADeselectionAsksAgain() {
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        choice.goBack()
        #expect(!choice.asksRefusalConfirmation)
        #expect(choice.answer == .oui)
        #expect(choice.validate() == .create)
        choice.answer = .non
        #expect(choice.asksRefusalConfirmation)
    }

    /// No write without « Oui »: neither the question left open, nor « Non », nor going back creates the storage message.
    @Test func theStorageMessageIsNeverCreatedWithoutOui() async throws {
        let fixture = try await Base.make(thread: nil, state: .off)
        await fixture.model.setEnabled(true)
        #expect(fixture.model.asksCreation)
        #expect(await fixture.remote.calls == [.find]) // asked, nothing written
        let choice = MPStorageCreationChoice()
        choice.answer = .non
        #expect(choice.asksRefusalConfirmation)
        choice.goBack()
        #expect(await fixture.remote.calls == [.find])
        choice.answer = .non
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

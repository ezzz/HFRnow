import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// « AQ » of the message menu (LOT-134) over the real `AQClient` and the captured AQ answers (`T50`/`T51` live; `T52`, `T55`,
/// `T56` from the local instance, LOT-055). No AQ answer is written by hand: a refusal that is not captured is a transport failure.
@MainActor
struct QualityAlertActionModelTests {
    typealias Support = QualityAlertAQTestSupport

    @Test func aMessageNoAQHoldsAsksForTheNoticeThenTheTitleAndCreates() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt")
        await rig.model.start(Support.context())
        // The check ran; nothing was created and the notice comes first.
        #expect(rig.model.prompt == .notice(Support.draft()))
        #expect(await rig.transport.posts == 0)
        rig.model.answerNotice(true, for: Support.draft())
        #expect(rig.model.prompt == .title(Support.draft()))
        #expect(rig.model.isNoticeAccepted)
        await rig.model.create(Support.draft(), title: "  Titre  ")
        #expect(rig.model.prompt == nil)
        #expect(await rig.transport.posts == 1)
        let body = try #require(await rig.transport.lastPostBody)
        #expect(body.hasPrefix("alerte_qualitay_id=-1&nom=Titre&topic_id=700001"))
        #expect(rig.messages.last == QualityAlertMessages.created)
    }

    @Test func decliningTheNoticeCreatesNothingAndKeepsAsking() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt")
        await rig.model.start(Support.context())
        rig.model.answerNotice(false, for: Support.draft())
        #expect(rig.model.prompt == nil && !rig.model.isNoticeAccepted)
        #expect(await rig.transport.posts == 0)
        await rig.model.start(Support.context())
        #expect(rig.model.prompt == .notice(Support.draft()))
    }

    @Test func noPathCreatesBeforeTheNoticeWasAccepted() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt")
        await rig.model.create(Support.draft(), title: "Titre")
        #expect(rig.model.prompt == .notice(Support.draft()))
        #expect(await rig.transport.posts == 0)
    }

    @Test func anAcceptedNoticeIsNotAskedAgain() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt", accepted: true)
        await rig.model.start(Support.context())
        #expect(rig.model.prompt == .title(Support.draft()))
    }

    @Test func aBlankTitleCreatesNothing() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt", accepted: true)
        await rig.model.create(Support.draft(), title: " \n ")
        #expect(await rig.transport.posts == 0)
    }

    @Test func aMessageHeldByAnotherMembersAQOffersToJoinIt() async throws {
        let rig = try Support.rig(alerts: "T56-aq-alerts-after-add-local.xml", create: "T55-aq-add-existing-ok-local.txt", accepted: true)
        // `T56`: AQ 13636 by user3 holds 700102 and 700101; the reporter is user4.
        await rig.model.start(Support.context(numreponse: 700_101))
        guard case .addition(let draft)? = rig.model.prompt else {
            Issue.record("no addition prompt: \(String(describing: rig.model.prompt))")
            return
        }
        #expect(draft.existing?.id == 13_636)
        await rig.model.add(draft)
        let body = try #require(await rig.transport.lastPostBody)
        #expect(body.hasPrefix("alerte_qualitay_id=13636&pseudo=user4&post_id=700101"))
        #expect(rig.messages.last == QualityAlertMessages.added)
    }

    @Test func aMessageTheMemberAlreadyReportedIsRefusedBeforeAnyQuestion() async throws {
        let rig = try Support.rig(
            alerts: "T56-aq-alerts-after-add-local.xml", create: "T55-aq-add-existing-ok-local.txt", accepted: true, pseudo: "USER3"
        )
        await rig.model.start(Support.context(numreponse: 700_101))
        #expect(rig.model.prompt == nil)
        #expect(rig.messages == [QualityAlertMessages.ownReport])
        #expect(await rig.transport.posts == 0)
    }

    @Test func anUnreadableCheckSaysSoAndAsksNothing() async throws {
        let rig = try Support.rig(alerts: nil, create: "T53-aq-create-ok-local.txt", accepted: true)
        await rig.model.start(Support.context())
        #expect(rig.model.prompt == nil)
        #expect(rig.messages == [QualityAlertMessages.impossible])
    }

    @Test func anUnconfirmedCreateReadsTheTopicBeforeSayingAnything() async throws {
        // The POST gets no usable answer (no refusal is captured), the list then shows the member's report: it was recorded (`T54`).
        // The account pseudo has capitals, the service stores it lower-cased (`pseudoInitiateur="user3"`).
        let rig = try Support.rig(alerts: "T54-aq-alerts-after-create-local.xml", create: nil, accepted: true, pseudo: "USER3")
        await rig.model.create(Support.draft(numreponse: 700_101), title: "Titre")
        #expect(await rig.transport.posts == 1)
        #expect(await rig.transport.gets == 1)
        #expect(rig.messages == [QualityAlertMessages.created])
    }

    @Test func anUnconfirmedCreateTheListDoesNotShowIsNotRecordedAndNotRetriedByItself() async throws {
        let rig = try Support.rig(
            alerts: "T52-aq-alerts-empty-local.xml", create: nil, accepted: true
        )
        await rig.model.create(Support.draft(), title: "Titre")
        #expect(await rig.transport.posts == 1)
        #expect(rig.messages == [QualityAlertMessages.notRecorded])
    }

    @Test func aSecondPickWaitsWhileTheFirstRuns() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt", accepted: true)
        await rig.model.start(Support.context())
        // A question is on screen: another pick is ignored.
        let before = await rig.transport.gets
        await rig.model.start(Support.context())
        #expect(await rig.transport.gets == before)
    }

    @Test func theEntryIsOfferedOnlyInAPublicTopicWithAPermalinkAndAnAccount() throws {
        let rig = try Support.rig(alerts: nil, create: nil)
        #expect(rig.model.canReport(Support.context()))
        #expect(!rig.model.canReport(Support.context(topic: nil)))
        #expect(!rig.model.canReport(Support.context(permalink: nil)))
        #expect(!rig.model.canReport(Support.context(topic: TopicID(category: .privateMessages, topic: 700_001))))
        #expect(!(try Support.rig(alerts: nil, create: nil, pseudo: "")).model.canReport(Support.context()))
    }

    @Test func anUnconfirmedAdditionIsRecordedOnlyWhenTheMessageNumberAppearsOnceMore() async throws {
        // Before: AQ 13636 holds 700101 (`T54`); after: it holds 700102 and 700101 (`T56`).
        let before = try #require(try await Support.alerts("T54-aq-alerts-after-create-local.xml").first)
        var draft = Support.draft(numreponse: 700_101)
        draft.existing = before
        let recorded = try Support.rig(alerts: "T56-aq-alerts-after-add-local.xml", create: nil, accepted: true, pseudo: "user4")
        await recorded.model.add(draft)
        #expect(await recorded.transport.posts == 1)
        // 700101 occurs once in both lists: not recorded, whatever else changed.
        #expect(recorded.messages == [QualityAlertMessages.additionNotRecorded])
        var added = Support.draft(numreponse: 700_102)
        added.existing = before
        let rig = try Support.rig(alerts: "T56-aq-alerts-after-add-local.xml", create: nil, accepted: true, pseudo: "user4")
        await rig.model.add(added)
        #expect(rig.messages == [QualityAlertMessages.added])
        let refused = try Support.rig(alerts: "T54-aq-alerts-after-create-local.xml", create: nil, accepted: true, pseudo: "user4")
        await refused.model.add(added)
        #expect(refused.messages == [QualityAlertMessages.additionNotRecorded])
        #expect(!QualityAlertMessages.additionNotRecorded.contains("Réessayez"))
        #expect(!QualityAlertMessages.notRecorded.contains("Réessayez"))
    }

    @Test func aSecondPickWhileTheCheckIsStillRunningDoesNothing() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: nil, accepted: true)
        await rig.transport.host.holdGets()
        let first = Task { @MainActor in await rig.model.start(Support.context()) }
        while await rig.transport.gets == 0 { await Task.yield() }
        #expect(rig.model.isWorking)
        await rig.model.start(Support.context())
        #expect(await rig.transport.gets == 1)
        await rig.transport.host.release()
        await first.value
        #expect(rig.model.prompt == .title(Support.draft()))
        #expect(await rig.transport.gets == 1)
    }

    @Test func aDoubleTapOnCreateSendsOneReport() async throws {
        let rig = try Support.rig(alerts: "T52-aq-alerts-empty-local.xml", create: "T53-aq-create-ok-local.txt", accepted: true)
        async let first: Void = rig.model.create(Support.draft(), title: "Titre")
        async let second: Void = rig.model.create(Support.draft(), title: "Titre")
        _ = await (first, second)
        // Each report e-mails the AQ operator, and three in a minute get the address banned (HFR-PROTOCOL §8).
        #expect(await rig.transport.posts == 1)
    }

    @Test func anUnconfirmedCreateWhoseListCannotBeReadSaysItIsUnverified() async throws {
        let rig = try Support.rig(alerts: nil, create: nil, accepted: true)
        await rig.model.create(Support.draft(), title: "Titre")
        #expect(await rig.transport.posts == 1)
        #expect(rig.messages == [QualityAlertMessages.unverified])
    }
}

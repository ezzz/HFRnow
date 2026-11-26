import Foundation
import HFRClient
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

/// The « Aucun post n'a été trouvé » line outlives the run on the model's shared timer, and VoiceOver hears it (#1152).
@MainActor @Suite(.timeLimit(.minutes(5)))
struct FilteredPostsStatusTests {
    private struct PassNormalizer: MessageContentNormalizing {
        func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
            MessageContent(html: contentHTML)
        }
    }

    private final class Spoken { var texts: [String] = [] }

    private struct Run {
        let model: FilteredPostsModel
        let sleeper: ManualSleeper
        let spoken: Spoken
    }

    private func emptyRun(voiceOver: Bool) async -> Run {
        let source = FakeFilteredSource { _, _, _ in filteredBatch(start: 3, end: 5, posts: 0) }
        let model = FilteredPostsModel(
            services: FilteredPostsServices(source: source, criteria: { FilteredPostsCriteria() }, normalizer: PassNormalizer())
        )
        let sleeper = ManualSleeper()
        let spoken = Spoken()
        model.statusTimer.sleep = sleeper.sleep
        model.statusTimer.isVoiceOverRunning = { voiceOver }
        model.announce = { spoken.texts.append($0) }
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await model.settle()
        return Run(model: model, sleeper: sleeper, spoken: spoken)
    }

    @Test func underVoiceOverTheStatusStaysUntilOK() async {
        let run = await emptyRun(voiceOver: true)
        let (model, sleeper) = (run.model, run.sleeper)
        for _ in 0..<50 { await Task.yield() }
        #expect(sleeper.asked.isEmpty)
        #expect(model.statusMessage == "Aucun post n'a été trouvé")
        model.dismissStatus()
        #expect(model.statusMessage == nil)
    }

    @Test func withoutVoiceOverTheStatusGoesAfterTheSharedDelay() async {
        let run = await emptyRun(voiceOver: false)
        let (model, sleeper) = (run.model, run.sleeper)
        await sleeper.waitUntilAsked(1)
        #expect(sleeper.asked == [ConfirmationAutoDismiss.delay])
        #expect(model.statusMessage != nil)
        await sleeper.finish(0)
        #expect(model.statusMessage == nil)
    }

    @Test func theStatusIsAnnouncedOnce() async {
        let run = await emptyRun(voiceOver: true)
        let (model, spoken) = (run.model, run.spoken)
        #expect(spoken.texts == ["Aucun post n'a été trouvé"])
        model.dismissStatus()
        #expect(spoken.texts.count == 1)
    }

    @Test func anOldWaitCannotClearTheStatusOfANewRun() async {
        let run = await emptyRun(voiceOver: false)
        let (model, sleeper) = (run.model, run.sleeper)
        await sleeper.waitUntilAsked(1)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        #expect(model.statusMessage == nil)
        await model.settle()
        await sleeper.waitUntilAsked(2)
        await sleeper.finish(0)
        #expect(model.statusMessage == "Aucun post n'a été trouvé")
    }
}

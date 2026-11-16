import Foundation
import HFRClient

extension ReplyComposerModel {
    /// Reads the new-topic form's sub-category select; the sheet runs it beside `start()` so the editor never waits for the
    /// network (legacy loaded it when the sheet opened, `AnswerView.swift:625-640` @ 2440d79). A failure leaves the picker
    /// empty and the topic sendable: the engine then sends the form's own choice.
    func loadSubcategories() async {
        guard case .newTopic(let topic) = target, !picker.isLoading else { return }
        picker.beginLoading()
        do throws(PostingError) {
            picker.apply(try await services.poster.newTopicOptions(formURL: topic.formURL))
        } catch {
            picker.fail(ComposerMessages.subcategoriesUnavailable(error))
        }
    }

    /// Reads the sub-category list again: from the new-topic form, or from the edit form when an edit's list went stale.
    func retrySubcategories() async {
        guard case .edit(let edit) = target else { return await loadSubcategories() }
        guard !picker.isLoading else { return }
        picker.beginLoading()
        do throws(PostingError) {
            let fresh = try await services.poster.editPrefill(edit)
            if let options = fresh.subcategories { picker.apply(options) } else { picker.reset() }
            picker.endLoading()
        } catch {
            picker.fail(ComposerMessages.editUnavailable(error))
        }
    }
}

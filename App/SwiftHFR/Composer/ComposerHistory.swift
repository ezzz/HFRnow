/// The texts the composer's undo and redo go back to (#653): every change of the text is one step, as legacy records each
/// change of `message` (`AnswerView.swift:624-635` @ 87fe0d1c), at most `limit` of them.
///
/// Whole texts, not diffs, as legacy: a step costs the size of the text, so 200 steps of a long reply stay a few megabytes.
struct ComposerHistory: Equatable {
    /// How many steps undo keeps (legacy `undoHistory.count > 200`).
    static let limit = 200

    private var undoStack: [String] = []
    private var redoStack: [String] = []

    /// How many steps undo can go back.
    var undoCount: Int { undoStack.count }
    /// Undo has a step.
    var canUndo: Bool { !undoStack.isEmpty }
    /// Redo has a step.
    var canRedo: Bool { !redoStack.isEmpty }

    /// The text was `previous` before a change by the user: one step back, and nothing left to redo.
    mutating func record(_ previous: String) {
        undoStack.append(previous)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
    }

    /// The text before `current`, which redo then gives back; nil with nothing to undo.
    mutating func undo(from current: String) -> String? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// The text undo replaced with `current`; nil with nothing to redo.
    mutating func redo(from current: String) -> String? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Forgets every step (the text the composer opened with is no step).
    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

extension ReplyComposerModel {
    /// "Annuler" acts: a step to go back to, and the editor accepts typing.
    var canUndo: Bool { canEdit && history.canUndo }
    /// "Rétablir" acts: an undone step to replay, and the editor accepts typing.
    var canRedo: Bool { canEdit && history.canRedo }
    /// "Vider le texte" acts: some text, and the editor accepts typing (legacy `message.isEmpty || isPosting`).
    var canClear: Bool { canEdit && !text.isEmpty }

    /// Goes back to the text before the last change; saved like typing.
    func undo() {
        guard canEdit else { return }
        var steps = history
        guard let previous = steps.undo(from: text) else { return }
        update(text: previous, history: steps)
    }

    /// Replays the last undone change; saved like typing.
    func redo() {
        guard canEdit else { return }
        var steps = history
        guard let next = steps.redo(from: text) else { return }
        update(text: next, history: steps)
    }

    /// "Vider le texte": empties the text without asking, as legacy (`clearComposer`, `AnswerView.swift:1345-1350` @ 87fe0d1c);
    /// one step, so "Annuler" brings it back.
    func clearText() {
        update(text: "")
    }
}

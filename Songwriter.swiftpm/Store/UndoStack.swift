import Foundation

/// Snapshot based undo / redo.
struct UndoStack<State> {
    private(set) var undoStates: [State] = []
    private(set) var redoStates: [State] = []
    let limit: Int

    init(limit: Int = 100) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    /// Call with the state *before* a change.
    mutating func record(_ state: State) {
        undoStates.append(state)
        if undoStates.count > limit { undoStates.removeFirst(undoStates.count - limit) }
        redoStates.removeAll()
    }

    mutating func undo(current: State) -> State? {
        guard let previous = undoStates.popLast() else { return nil }
        redoStates.append(current)
        return previous
    }

    mutating func redo(current: State) -> State? {
        guard let next = redoStates.popLast() else { return nil }
        undoStates.append(current)
        return next
    }

    mutating func clear() {
        undoStates.removeAll()
        redoStates.removeAll()
    }
}

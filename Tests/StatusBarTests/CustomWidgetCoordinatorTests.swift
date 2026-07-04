@testable import StatusBar
import Testing

// MARK: - CustomWidgetCoordinatorValidateTests

struct CustomWidgetCoordinatorValidateTests {
    @Test("A well-formed entry is valid")
    func wellFormedEntryIsValid() {
        let config = CustomWidgetConfig(id: "k8s-context", script: "kubectl config current-context")
        let result = CustomWidgetCoordinator.validate([config])

        #expect(result.valid == [config])
        #expect(result.errors.isEmpty)
    }

    @Test("Empty id is an error")
    func emptyIDIsError() {
        let config = CustomWidgetConfig(id: "", script: "echo hi")
        let result = CustomWidgetCoordinator.validate([config])

        #expect(result.valid.isEmpty)
        #expect(result.errors == ["customWidgets entry #1: missing id"])
    }

    @Test("id with spaces or symbols is an error")
    func invalidIDCharactersAreError() {
        let config = CustomWidgetConfig(id: "my widget!", script: "echo hi")
        let result = CustomWidgetCoordinator.validate([config])

        #expect(result.valid.isEmpty)
        #expect(result.errors == ["customWidgets 'my widget!': invalid id (use letters, digits, - or _)"])
    }

    @Test("Whitespace-only script is an error")
    func whitespaceOnlyScriptIsError() {
        let config = CustomWidgetConfig(id: "my-widget", script: "   ")
        let result = CustomWidgetCoordinator.validate([config])

        #expect(result.valid.isEmpty)
        #expect(result.errors == ["customWidgets 'my-widget': missing script"])
    }

    @Test("Duplicate id keeps the first and flags the rest")
    func duplicateIDKeepsFirst() {
        let first = CustomWidgetConfig(id: "dup", script: "echo first")
        let second = CustomWidgetConfig(id: "dup", script: "echo second")
        let result = CustomWidgetCoordinator.validate([first, second])

        #expect(result.valid == [first])
        #expect(result.errors == ["customWidgets 'dup': duplicate id"])
    }
}

// MARK: - CustomWidgetCoordinatorDiffTests

struct CustomWidgetCoordinatorDiffTests {
    @Test("Only additions produce added entries")
    func onlyAdditions() {
        let config = CustomWidgetConfig(id: "new", script: "echo hi")
        let diff = CustomWidgetCoordinator.diff(current: [:], desired: [config])

        #expect(diff.added == [config])
        #expect(diff.removedIDs.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("Only removals produce removedIDs")
    func onlyRemovals() {
        let config = CustomWidgetConfig(id: "gone", script: "echo hi")
        let diff = CustomWidgetCoordinator.diff(current: ["gone": config], desired: [])

        #expect(diff.added.isEmpty)
        #expect(diff.removedIDs == ["gone"])
        #expect(diff.changed.isEmpty)
    }

    @Test("A script change is reported as changed")
    func scriptChangeIsChanged() {
        let old = CustomWidgetConfig(id: "x", script: "echo old")
        let new = CustomWidgetConfig(id: "x", script: "echo new")
        let diff = CustomWidgetCoordinator.diff(current: ["x": old], desired: [new])

        #expect(diff.added.isEmpty)
        #expect(diff.removedIDs.isEmpty)
        #expect(diff.changed == [new])
    }

    @Test("An identical config is a no-op")
    func identicalConfigIsNoOp() {
        let config = CustomWidgetConfig(id: "x", script: "echo hi")
        let diff = CustomWidgetCoordinator.diff(current: ["x": config], desired: [config])

        #expect(diff.added.isEmpty)
        #expect(diff.removedIDs.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test("A mix of add, remove, and change is reported correctly")
    func mixedDiff() {
        let unchanged = CustomWidgetConfig(id: "unchanged", script: "echo unchanged")
        let oldChanged = CustomWidgetConfig(id: "changed", script: "echo old")
        let newChanged = CustomWidgetConfig(id: "changed", script: "echo new")
        let removed = CustomWidgetConfig(id: "removed", script: "echo removed")
        let added = CustomWidgetConfig(id: "added", script: "echo added")

        let diff = CustomWidgetCoordinator.diff(
            current: ["unchanged": unchanged, "changed": oldChanged, "removed": removed],
            desired: [unchanged, newChanged, added]
        )

        #expect(diff.added == [added])
        #expect(diff.removedIDs == ["removed"])
        #expect(diff.changed == [newChanged])
    }
}

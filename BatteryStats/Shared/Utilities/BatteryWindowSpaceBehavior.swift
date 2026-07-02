import AppKit

enum BatteryWindowSpaceBehavior {
    static let activeSpacePresentation: NSWindow.CollectionBehavior = [
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .moveToActiveSpace
    ]

    static let menuBarPanelPresentation: NSWindow.CollectionBehavior = activeSpacePresentation.union([
        .transient,
        .ignoresCycle
    ])

    @MainActor
    static func applyActiveSpacePresentation(to window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.remove(.canJoinAllSpaces)
        behavior.formUnion(activeSpacePresentation)
        window.collectionBehavior = behavior
    }
}

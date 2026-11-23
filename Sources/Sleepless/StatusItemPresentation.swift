import AppKit
import SleeplessCore

@MainActor
enum StatusItemPresentation {
    static func apply(to button: NSButton, state: SleepState, isBusy: Bool) {
        button.imagePosition = .noImage
        button.image = nil
        button.title = state.menuBarTitle
        button.toolTip = "Sleepless — \(state.summary)\(isBusy ? " (checking or changing…)" : "")\nLeft-click to \(state == .unknown ? "retry reading" : "toggle"); right-click for options."
        button.setAccessibilityLabel(state.accessibilityLabel)
    }
}

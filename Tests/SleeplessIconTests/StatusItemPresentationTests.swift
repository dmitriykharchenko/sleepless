import AppKit
import SleeplessCore
import Testing
@testable import Sleepless

@MainActor
struct StatusItemPresentationTests {
    @Test(arguments: [SleepState.normal, .disabled, .unknown], [false, true])
    func nativeButtonUsesOnlyObservedText(_ state: SleepState, _ isBusy: Bool) {
        let button = NSButton(frame: .zero)
        let nativeFont = button.font
        button.image = NSImage(size: NSSize(width: 18, height: 18))
        StatusItemPresentation.apply(to: button, state: state, isBusy: isBusy)
        let expected = state == .normal ? "SOMNIA" : state == .disabled ? "INSOMNIA" : "?"
        #expect(button.title == expected)
        #expect(button.image == nil)
        #expect(button.imagePosition == .noImage)
        #expect(button.font == nativeFont)
        #expect(button.accessibilityLabel() == "Sleepless: \(state.summary)")
        #expect(button.toolTip?.contains(expected) == true)
        #expect(button.toolTip?.contains("checking or changing…") == isBusy)
        #expect(button.toolTip?.contains(state == .unknown ? "retry reading" : "toggle") == true)
        #expect(button.toolTip?.contains("right-click for options") == true)
        #expect(button.toolTip?.localizedCaseInsensitiveContains("cup") == false)
    }

    @Test func controllerUpdatesPresentVerifiedTransitionsRefreshAndRetry() async {
        let service = PresentationPowerSettings(reads: [
            .failure(.unreadableState), .success(.normal),
            .success(.normal), .success(.disabled),
            .success(.disabled), .success(.normal),
            .success(.disabled), .failure(.readFailed(1)), .success(.normal)
        ])
        let controller = SleepController(service: service)
        let button = NSButton(frame: .zero)
        var titles: [String] = []
        var busyTitles: [String] = []
        let update = {
            StatusItemPresentation.apply(to: button, state: controller.state, isBusy: controller.isBusy)
            titles.append(button.title)
            if controller.isBusy { busyTitles.append(button.title) }
            #expect(button.image == nil)
            #expect(button.accessibilityLabel() == controller.state.accessibilityLabel)
        }
        controller.onChange = update
        update()
        #expect(button.title == "?")
        await controller.start()
        #expect(button.title == "?")
        await controller.toggle()
        #expect(button.title == "SOMNIA")
        #expect(await service.recordedTargets().isEmpty)
        await controller.toggle()
        #expect(button.title == "INSOMNIA")
        await controller.toggle()
        #expect(button.title == "SOMNIA")
        await controller.refresh()
        #expect(button.title == "INSOMNIA")
        await controller.refresh()
        #expect(button.title == "?")
        await controller.toggle()
        #expect(button.title == "SOMNIA")
        #expect(await service.recordedTargets() == [true, false])
        #expect(titles == ["?", "?", "?", "?", "SOMNIA", "SOMNIA", "INSOMNIA",
                           "INSOMNIA", "SOMNIA", "SOMNIA", "INSOMNIA", "INSOMNIA", "?", "?", "SOMNIA"])
        #expect(busyTitles == ["?", "?", "SOMNIA", "INSOMNIA", "SOMNIA", "INSOMNIA", "?"])
        #expect(button.toolTip?.contains("checking or changing…") == false)
    }

    @Test(arguments: [SleepControlError.authorizationCancelled, .authorizationFailed(1)],
          [SleepState.normal, .disabled, .unknown])
    func rejectedUpdatesShowReadbackNotRequestedState(_ error: SleepControlError, _ observed: SleepState) async {
        let service = PresentationPowerSettings(
            reads: [.success(.normal), .success(.normal), .success(observed)], writeError: error
        )
        let controller = SleepController(service: service)
        let button = NSButton(frame: .zero)
        controller.onChange = {
            StatusItemPresentation.apply(to: button, state: controller.state, isBusy: controller.isBusy)
        }
        await controller.start()
        await controller.toggle()
        #expect(button.title == (observed == .normal ? "SOMNIA" : observed == .disabled ? "INSOMNIA" : "?"))
        #expect(button.image == nil)
        #expect(button.accessibilityLabel() == observed.accessibilityLabel)
        #expect(controller.lastError == error)
        #expect(!controller.appEnabledNoSleep)
        #expect(await service.recordedTargets() == [true])
    }

    @Test(arguments: [SleepState.normal, .unknown])
    func successfulWriteWithoutVerifiedTargetDoesNotDisplaySuccess(_ observed: SleepState) async {
        let service = PresentationPowerSettings(reads: [
            .success(.normal), .success(.normal), .success(observed)
        ])
        let controller = SleepController(service: service)
        let button = NSButton(frame: .zero)
        controller.onChange = {
            StatusItemPresentation.apply(to: button, state: controller.state, isBusy: controller.isBusy)
        }
        await controller.start()
        await controller.toggle()
        #expect(button.title == (observed == .normal ? "SOMNIA" : "?"))
        #expect(controller.lastError == (observed == .normal ? .verificationFailed : .unreadableState))
        #expect(button.toolTip?.contains("checking or changing…") == false)
    }
}

private actor PresentationPowerSettings: PowerSettingsServing {
    private var reads: [Result<SleepState, SleepControlError>]
    private let writeError: SleepControlError?
    private var targets: [Bool] = []

    init(reads: [Result<SleepState, SleepControlError>], writeError: SleepControlError? = nil) {
        self.reads = reads
        self.writeError = writeError
    }

    func readState() throws -> SleepState {
        try reads.removeFirst().get()
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        targets.append(disabled)
        if let writeError { throw writeError }
    }

    func recordedTargets() -> [Bool] { targets }
}

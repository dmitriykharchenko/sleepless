import Testing
import SleeplessCore

@MainActor
struct SleepControllerTests {
    @Test(arguments: [SleepState.normal, .disabled])
    func launchPreservesInitialStateWithoutWriting(_ initial: SleepState) async {
        let fake = FakePowerSettings(reads: [.success(initial)])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.start()
        #expect(controller.initialState == initial)
        #expect(controller.state == initial)
        #expect(controller.restorationPolicy == .none)
        #expect(!controller.appEnabledNoSleep)
        #expect(await fake.recordedTargets().isEmpty)
        #expect(await fake.numberOfReads() == 1)
    }

    @Test func failedLaunchRemainsUnknownAndAnUnknownClickOnlyRefreshes() async {
        let fake = FakePowerSettings(reads: [.failure(.unreadableState), .success(.normal)])
        let controller = SleepController(service: fake)
        await controller.start()
        #expect(controller.state == .unknown)
        #expect(controller.initialState == .unknown)
        #expect(controller.lastError == .unreadableState)
        await controller.toggle()
        #expect(controller.state == .normal)
        #expect(controller.initialState == .unknown)
        #expect(await fake.recordedTargets().isEmpty)
    }

    @Test func bothTransitionsUsePreflightAndReadback() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled),
            .success(.disabled), .success(.normal)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .disabled)
        #expect(controller.restorationPolicy == .offerRestoration)
        #expect(controller.lastError == nil)
        await controller.toggle()
        #expect(controller.state == .normal)
        #expect(controller.restorationPolicy == .none)
        #expect(controller.initialState == .normal)
        #expect(controller.lastError == nil)
        #expect(await fake.recordedTargets() == [true, false])
        #expect(await fake.numberOfReads() == 5)
    }

    @Test func toggleUsesFreshExternalStateNotStaleIcon() async {
        let fake = FakePowerSettings(reads: [.success(.normal), .success(.disabled), .success(.normal)])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await fake.recordedTargets() == [false])
        #expect(controller.state == .normal)
    }

    @Test(arguments: [SleepControlError.authorizationCancelled, .authorizationFailed(1)])
    func rejectedChangeReadsActualStateAndDoesNotClaimOwnership(_ failure: SleepControlError) async {
        let fake = FakePowerSettings(
            reads: [.success(.normal), .success(.normal), .success(.normal)],
            writes: [.failure(failure)]
        )
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .normal)
        #expect(controller.lastError == failure)
        #expect(!controller.appEnabledNoSleep)
        #expect(await fake.numberOfReads() == 3)
    }

    @Test func cancellationStillReflectsCoincidentExternalChange() async {
        let fake = FakePowerSettings(
            reads: [.success(.normal), .success(.normal), .success(.disabled)],
            writes: [.failure(.authorizationCancelled)]
        )
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .disabled)
        #expect(controller.lastError == .authorizationCancelled)
        #expect(controller.restorationPolicy == .none)
    }

    @Test func successfulCommandWithoutActualChangeIsFailure() async {
        let fake = FakePowerSettings(reads: [.success(.normal), .success(.normal), .success(.normal)])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .normal)
        #expect(controller.lastError == .verificationFailed)
        #expect(controller.restorationPolicy == .none)
    }

    @Test func unreadablePreflightNeverWrites() async {
        let fake = FakePowerSettings(reads: [.success(.normal), .failure(.readFailed(1))])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .unknown)
        #expect(controller.lastError == .readFailed(1))
        #expect(await fake.recordedTargets().isEmpty)
    }

    @Test func unknownServiceValueIsNeverTreatedAsNormal() async {
        let fake = FakePowerSettings(reads: [.success(.unknown)])
        let controller = SleepController(service: fake)
        await controller.start()
        #expect(controller.state == .unknown)
        #expect(controller.lastError == .unreadableState)
    }

    @Test func unreadableReadbackDoesNotAssumeSuccessAndRetainsQuitWarning() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .failure(.unreadableState), .success(.disabled)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(controller.state == .unknown)
        #expect(controller.lastError == .unreadableState)
        #expect(controller.restorationPolicy == .stateUnknown)
        let restored = await controller.restoreNormalSleep()
        #expect(!restored)
        #expect(await fake.recordedTargets() == [true])
        await controller.refresh()
        #expect(controller.state == .disabled)
        #expect(controller.restorationPolicy == .offerRestoration)
    }

    @Test func pollingTracksExternalChangesWithoutTakingOwnership() async {
        let fake = FakePowerSettings(reads: [.success(.normal), .success(.disabled), .success(.normal)])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.refresh()
        #expect(controller.state == .disabled)
        #expect(controller.restorationPolicy == .none)
        await controller.refresh()
        #expect(controller.state == .normal)
        #expect(await fake.recordedTargets().isEmpty)
    }

    @Test func observingExternalNormalStateRelinquishesOwnership() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled),
            .success(.normal), .success(.disabled)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        await controller.refresh()
        await controller.refresh()
        #expect(controller.state == .disabled)
        #expect(!controller.appEnabledNoSleep)
        #expect(controller.restorationPolicy == .none)
        #expect(await fake.recordedTargets() == [true])
    }

    @Test func repeatedClicksPollingAndRestoreCannotOverlapAWrite() async {
        let fake = FakePowerSettings(
            reads: [.success(.normal), .success(.normal), .success(.disabled)], holdWrites: true
        )
        let controller = SleepController(service: fake)
        await controller.start()
        let firstClick = Task { await controller.toggle() }
        await fake.waitForWrite()
        #expect(controller.isBusy)
        #expect(controller.state == .normal)
        await controller.toggle()
        await controller.refresh()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(await fake.recordedTargets() == [true])
        #expect(await fake.numberOfReads() == 2)
        await fake.releaseWrite()
        await firstClick.value
        #expect(controller.state == .disabled)
        #expect(!controller.isBusy)
        #expect(await fake.numberOfReads() == 3)
    }

    @Test func preexistingNoSleepCannotBeRestoredByQuit() async {
        let fake = FakePowerSettings(reads: [.success(.disabled)])
        let controller = SleepController(service: fake)
        await controller.start()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(controller.restorationPolicy == .none)
        #expect(await fake.recordedTargets().isEmpty)
        #expect(await fake.numberOfReads() == 1)
    }

    @Test func explicitQuitRestorationRequiresVerifiedNormalState() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled),
            .success(.disabled), .success(.normal)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep())
        #expect(controller.state == .normal)
        #expect(controller.restorationPolicy == .none)
        #expect(await fake.recordedTargets() == [true, false])
    }

    @Test func restorationSkipsWriteIfExternalNormalStateIsNowObserved() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled), .success(.normal)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep())
        #expect(controller.restorationPolicy == .none)
        #expect(await fake.recordedTargets() == [true])
    }

    @Test(arguments: [SleepControlError.authorizationCancelled, .authorizationFailed(1)])
    func failedQuitRestorationDoesNotApproveQuit(_ failure: SleepControlError) async {
        let fake = FakePowerSettings(
            reads: [
                .success(.normal), .success(.normal), .success(.disabled),
                .success(.disabled), .success(.disabled)
            ],
            writes: [.success(()), .failure(failure)]
        )
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(controller.lastError == failure)
        #expect(controller.state == .disabled)
        #expect(controller.restorationPolicy == .offerRestoration)
    }

    @Test func unreadableQuitPreflightDoesNotWrite() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled), .failure(.unreadableState)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(controller.restorationPolicy == .stateUnknown)
        #expect(await fake.recordedTargets() == [true])
    }

    @Test func quitRestorationRejectsSuccessfulCommandWithUnchangedReadback() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled),
            .success(.disabled), .success(.disabled)
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(controller.lastError == .verificationFailed)
        #expect(controller.restorationPolicy == .offerRestoration)
        #expect(await fake.recordedTargets() == [true, false])
    }

    @Test func quitRestorationDoesNotGuessAfterFailedReadback() async {
        let fake = FakePowerSettings(reads: [
            .success(.normal), .success(.normal), .success(.disabled),
            .success(.disabled), .failure(.readFailed(1))
        ])
        let controller = SleepController(service: fake)
        await controller.start()
        await controller.toggle()
        #expect(await controller.restoreNormalSleep() == false)
        #expect(controller.state == .unknown)
        #expect(controller.restorationPolicy == .stateUnknown)
        #expect(controller.lastError == .readFailed(1))
    }
}
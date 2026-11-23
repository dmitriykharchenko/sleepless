import Testing
import SleeplessCore

struct PowerSettingsTests {
    @Test func parsesActualSleepDisabledValues() throws {
        #expect(try SystemPowerSettings.parseState("System-wide power settings:\n SleepDisabled\t1\nCurrently in use:\n sleep 0") == .disabled)
        #expect(try SystemPowerSettings.parseState("System-wide power settings:\r\n\tSleepDisabled   0\r\n") == .normal)
    }

    @Test(arguments: [
        "", "sleep 0", "disablesleep 1", "SleepDisabled", "SleepDisabled yes",
        "SleepDisabled 2", "SleepDisabled 1 extra", "SleepDisabled 0\nSleepDisabled 1",
        "SleepDisabled 1\nSleepDisabled 1", "NotSleepDisabled 1"
    ])
    func rejectsMissingMalformedOrAmbiguousState(_ output: String) {
        #expect(throws: SleepControlError.unreadableState) {
            try SystemPowerSettings.parseState(output)
        }
    }

    @Test func menuBarTitlesAndAccessibilityLabelsMatchObservedState() {
        #expect(SleepState.disabled.menuBarTitle == "INSOMNIA")
        #expect(SleepState.disabled.accessibilityLabel == "Sleepless: System sleep is disabled — INSOMNIA")

        #expect(SleepState.normal.menuBarTitle == "SOMNIA")
        #expect(SleepState.normal.accessibilityLabel == "Sleepless: Normal sleep is allowed — SOMNIA")

        #expect(SleepState.unknown.menuBarTitle == "?")
        #expect(SleepState.unknown.accessibilityLabel == "Sleepless: Sleep setting is unknown — ?")
    }

    @Test func readUsesOnlyTheUnprivilegedRunner() async throws {
        let reader = StubProcessRunner([.success(ProcessResult(status: 0, output: "SleepDisabled 1"))])
        let privilege = StubProcessRunner()
        let service = SystemPowerSettings(processRunner: reader, privilegeRunner: privilege)
        #expect(try await service.readState() == .disabled)
        #expect(await reader.recordedRequests() == [ProcessRequest(executable: "/usr/bin/pmset", arguments: ["-g"])])
        #expect(await privilege.recordedRequests().isEmpty)
    }

    @Test func privilegedRunnerReceivesOnlyTwoFixedScripts() async throws {
        let reader = StubProcessRunner()
        let privilege = StubProcessRunner([
            .success(ProcessResult(status: 0, output: "")),
            .success(ProcessResult(status: 0, output: ""))
        ])
        let service = SystemPowerSettings(processRunner: reader, privilegeRunner: privilege)
        try await service.setSleepDisabled(true)
        try await service.setSleepDisabled(false)
        #expect(await privilege.recordedRequests() == [
            ProcessRequest(executable: "/usr/bin/osascript", arguments: [
                "-e", "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges"
            ]),
            ProcessRequest(executable: "/usr/bin/osascript", arguments: [
                "-e", "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"
            ])
        ])
        #expect(await reader.recordedRequests().isEmpty)
    }

    @Test func cancellationIsNotReportedAsSuccess() async {
        let privilege = StubProcessRunner([.success(ProcessResult(
            status: 1, output: "execution error: User canceled. (-128)"
        ))])
        let service = SystemPowerSettings(processRunner: StubProcessRunner(), privilegeRunner: privilege)
        await #expect(throws: SleepControlError.authorizationCancelled) {
            try await service.setSleepDisabled(true)
        }
    }

    @Test func authorizationFailureIsNotCancellation() async {
        let privilege = StubProcessRunner([.success(ProcessResult(status: 1, output: "Not authorized. (-60005)"))])
        let service = SystemPowerSettings(processRunner: StubProcessRunner(), privilegeRunner: privilege)
        await #expect(throws: SleepControlError.authorizationFailed(1)) {
            try await service.setSleepDisabled(false)
        }
    }

    @Test func failingReadDoesNotParseEvenPlausibleOutput() async {
        let reader = StubProcessRunner([.success(ProcessResult(status: 3, output: "SleepDisabled 0"))])
        let service = SystemPowerSettings(processRunner: reader, privilegeRunner: StubProcessRunner())
        await #expect(throws: SleepControlError.readFailed(3)) { try await service.readState() }
    }

    @Test func processLaunchFailurePropagates() async {
        let reader = StubProcessRunner([.failure(.executionFailed("Fake launch failure"))])
        let service = SystemPowerSettings(processRunner: reader, privilegeRunner: StubProcessRunner())
        await #expect(throws: SleepControlError.executionFailed("Fake launch failure")) {
            try await service.readState()
        }
    }
}
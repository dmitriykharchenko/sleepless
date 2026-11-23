import SleeplessCore

actor StubProcessRunner: ProcessRunning {
    private var replies: [Result<ProcessResult, SleepControlError>]
    private var requests: [ProcessRequest] = []

    init(_ replies: [Result<ProcessResult, SleepControlError>] = []) {
        self.replies = replies
    }

    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        requests.append(request)
        guard !replies.isEmpty else {
            throw SleepControlError.executionFailed("Unexpected process request in fake")
        }
        return try replies.removeFirst().get()
    }

    func recordedRequests() -> [ProcessRequest] { requests }
}

actor FakePowerSettings: PowerSettingsServing {
    private var reads: [Result<SleepState, SleepControlError>]
    private var writeResults: [Result<Void, SleepControlError>]
    private var targets: [Bool] = []
    private var readCount = 0
    private let holdWrites: Bool
    private var writeContinuation: CheckedContinuation<Void, Never>?
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        reads: [Result<SleepState, SleepControlError>],
        writes: [Result<Void, SleepControlError>] = [],
        holdWrites: Bool = false
    ) {
        self.reads = reads
        self.writeResults = writes
        self.holdWrites = holdWrites
    }

    func readState() async throws -> SleepState {
        readCount += 1
        guard !reads.isEmpty else {
            throw SleepControlError.executionFailed("Unexpected state read in fake")
        }
        return try reads.removeFirst().get()
    }

    func setSleepDisabled(_ disabled: Bool) async throws {
        targets.append(disabled)
        let waiters = writeWaiters
        writeWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if holdWrites {
            await withCheckedContinuation { writeContinuation = $0 }
        }
        if !writeResults.isEmpty { try writeResults.removeFirst().get() }
    }

    func waitForWrite() async {
        if !targets.isEmpty { return }
        await withCheckedContinuation { writeWaiters.append($0) }
    }

    func releaseWrite() {
        writeContinuation?.resume()
        writeContinuation = nil
    }

    func recordedTargets() -> [Bool] { targets }
    func numberOfReads() -> Int { readCount }
}
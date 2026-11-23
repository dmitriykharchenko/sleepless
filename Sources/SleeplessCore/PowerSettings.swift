import Foundation

public enum SleepState: Equatable, Sendable {
    case normal
    case disabled
    case unknown

    public var menuBarTitle: String {
        switch self {
        case .normal: "SOMNIA"
        case .disabled: "INSOMNIA"
        case .unknown: "?"
        }
    }

    public var summary: String {
        switch self {
        case .normal: "Normal sleep is allowed — SOMNIA"
        case .disabled: "System sleep is disabled — INSOMNIA"
        case .unknown: "Sleep setting is unknown — ?"
        }
    }

    public var accessibilityLabel: String { "Sleepless: \(summary)" }
}

public enum SleepControlError: Error, Equatable, LocalizedError, Sendable {
    case authorizationCancelled
    case authorizationFailed(Int32)
    case readFailed(Int32)
    case unreadableState
    case verificationFailed
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationCancelled:
            "Administrator approval was cancelled. No successful change was assumed."
        case .authorizationFailed(let status):
            "The administrator-approved command failed (exit status \(status)). No successful change was assumed."
        case .readFailed(let status):
            "The current sleep setting could not be read (exit status \(status))."
        case .unreadableState:
            "macOS did not report one valid SleepDisabled value. The sleep setting is unknown."
        case .verificationFailed:
            "macOS did not report the requested setting after the change. The indicator shows the observed setting."
        case .executionFailed(let description):
            "The macOS power command could not run: \(description)"
        }
    }
}

public protocol PowerSettingsServing: Sendable {
    func readState() async throws -> SleepState
    func setSleepDisabled(_ disabled: Bool) async throws
}

public struct ProcessRequest: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

/// Blocking process work stays off the main actor. A shared pipe drains both
/// output streams while the child runs, avoiding a full-stderr-pipe deadlock.
public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: request.executable)
                process.arguments = request.arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: ProcessResult(
                        status: process.terminationStatus,
                        output: String(decoding: data, as: UTF8.self)
                    ))
                } catch {
                    continuation.resume(throwing: SleepControlError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}

public struct SystemPowerSettings: PowerSettingsServing {
    private let processRunner: any ProcessRunning
    private let privilegeRunner: any ProcessRunning

    public init(
        processRunner: any ProcessRunning = FoundationProcessRunner(),
        privilegeRunner: any ProcessRunning = FoundationProcessRunner()
    ) {
        self.processRunner = processRunner
        self.privilegeRunner = privilegeRunner
    }

    public func readState() async throws -> SleepState {
        let result = try await processRunner.run(ProcessRequest(
            executable: "/usr/bin/pmset", arguments: ["-g"]
        ))
        guard result.status == 0 else { throw SleepControlError.readFailed(result.status) }
        return try Self.parseState(result.output)
    }

    public func setSleepDisabled(_ disabled: Bool) async throws {
        // Deliberately fixed scripts: no user input, shell interpolation, passwords,
        // or arbitrary command strings.
        let script = disabled
            ? "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges"
            : "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"
        let result = try await privilegeRunner.run(ProcessRequest(
            executable: "/usr/bin/osascript", arguments: ["-e", script]
        ))
        guard result.status == 0 else {
            if result.output.contains("(-128)") {
                throw SleepControlError.authorizationCancelled
            }
            throw SleepControlError.authorizationFailed(result.status)
        }
    }

    public static func parseState(_ output: String) throws -> SleepState {
        let entries = output.split(whereSeparator: \.isNewline).map {
            $0.split(whereSeparator: \.isWhitespace)
        }.filter { $0.first == "SleepDisabled" }
        guard entries.count == 1, let entry = entries.first, entry.count == 2 else {
            throw SleepControlError.unreadableState
        }
        switch entry[1] {
        case "0": return .normal
        case "1": return .disabled
        default: throw SleepControlError.unreadableState
        }
    }
}
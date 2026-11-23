import Foundation

public enum RestorationPolicy: Equatable, Sendable {
    case none
    case offerRestoration
    case stateUnknown
}

/// Main-actor isolation plus a gate acquired before any await serializes reads,
/// writes, and readback. Repeated clicks and polling never queue extra toggles.
@MainActor
public final class SleepController {
    public private(set) var state: SleepState = .unknown
    public private(set) var initialState: SleepState?
    public private(set) var isBusy = false
    public private(set) var appEnabledNoSleep = false
    public private(set) var lastError: SleepControlError?
    public var onChange: (() -> Void)?

    private let service: any PowerSettingsServing
    private var didStart = false

    public init(service: any PowerSettingsServing) {
        self.service = service
    }

    public var restorationPolicy: RestorationPolicy {
        guard appEnabledNoSleep else { return .none }
        switch state {
        case .disabled: return .offerRestoration
        case .unknown: return .stateUnknown
        case .normal: return .none
        }
    }

    public func start() async {
        guard !didStart, !isBusy else { return }
        didStart = true
        beginOperation()
        defer { endOperation() }
        lastError = await observe()
        initialState = state
    }

    public func refresh() async {
        guard didStart else { await start(); return }
        guard !isBusy else { return }
        beginOperation()
        defer { endOperation() }
        lastError = await observe()
    }

    public func toggle() async {
        guard didStart else { await start(); return }
        guard !isBusy else { return }
        // An unknown-state click only refreshes; it never guesses a write target.
        guard state != .unknown else { await refresh(); return }
        beginOperation()
        defer { endOperation() }
        lastError = await observe()
        guard lastError == nil else { return }
        _ = await change(to: state == .normal ? .disabled : .normal)
    }

    /// Called only after explicit user approval in the quit dialog. A fresh
    /// observation prevents a stale icon from causing an unnecessary write.
    public func restoreNormalSleep() async -> Bool {
        guard !isBusy, restorationPolicy == .offerRestoration else { return false }
        beginOperation()
        defer { endOperation() }
        lastError = await observe()
        guard lastError == nil else { return false }
        if state == .normal { return true }
        return await change(to: .normal)
    }

    private func beginOperation() {
        isBusy = true
        lastError = nil
        onChange?()
    }

    private func endOperation() {
        isBusy = false
        onChange?()
    }

    private func observe() async -> SleepControlError? {
        do {
            let observed = try await service.readState()
            guard observed != .unknown else { throw SleepControlError.unreadableState }
            state = observed
            // Once normal sleep is observed, a later external enable is not ours.
            if observed == .normal { appEnabledNoSleep = false }
            return nil
        } catch {
            state = .unknown
            return Self.controlError(error)
        }
    }

    private func change(to requested: SleepState) async -> Bool {
        var writeError: SleepControlError?
        do {
            try await service.setSleepDisabled(requested == .disabled)
            if requested == .disabled { appEnabledNoSleep = true }
        } catch {
            writeError = Self.controlError(error)
        }

        // Even cancelled/failed commands may coincide with an external change.
        // Never derive the displayed setting from a process exit code alone.
        let readError = await observe()
        lastError = writeError ?? readError
        if lastError == nil, state != requested { lastError = .verificationFailed }
        return lastError == nil && state == requested
    }

    private static func controlError(_ error: any Error) -> SleepControlError {
        (error as? SleepControlError) ?? .executionFailed(error.localizedDescription)
    }
}
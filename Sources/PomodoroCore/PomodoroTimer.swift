import Foundation

/// Active Pomodoro phase.
public enum PomodoroPhase: String, Codable, Sendable, Equatable {
    case work
    case breakTime

    public var displayName: String {
        switch self {
        case .work:
            return "Work"
        case .breakTime:
            return "Break"
        }
    }

    public var next: PomodoroPhase {
        switch self {
        case .work:
            return .breakTime
        case .breakTime:
            return .work
        }
    }
}

/// Lifecycle state of the Pomodoro timer.
public enum PomodoroStatus: String, Sendable, Equatable {
    case idle
    case running
    case paused
    case ringing
}

/// Pure Foundation state machine for the Pomodoro countdown, phase switching,
/// duration adjustments, and alarm acknowledgment.
public final class PomodoroTimer {
    public static let defaultWorkMinutes = 25
    public static let defaultBreakMinutes = 5
    public static let minMinutes = 1
    public static let maxMinutes = 180

    public private(set) var phase: PomodoroPhase = .work
    public private(set) var status: PomodoroStatus = .idle
    public private(set) var workMinutes: Int
    public private(set) var breakMinutes: Int
    public private(set) var remainingSeconds: Int
    public private(set) var completedWorkSessions: Int = 0

    private var targetEndDate: Date?
    private let now: () -> Date

    public init(
        workMinutes: Int = PomodoroTimer.defaultWorkMinutes,
        breakMinutes: Int = PomodoroTimer.defaultBreakMinutes,
        now: @escaping () -> Date = Date.init
    ) {
        self.workMinutes = Self.clampMinutes(workMinutes)
        self.breakMinutes = Self.clampMinutes(breakMinutes)
        self.now = now
        self.remainingSeconds = self.workMinutes * 60
    }

    public var configuredMinutesForCurrentPhase: Int {
        configuredMinutes(for: phase)
    }

    public func configuredMinutes(for targetPhase: PomodoroPhase) -> Int {
        switch targetPhase {
        case .work:
            return workMinutes
        case .breakTime:
            return breakMinutes
        }
    }

    /// Formats `remainingSeconds` as `MM:SS` (or `HH:MM:SS` if >= 60 minutes? No, `MM:SS` like `90:00` is clearer for Pomodoro, or `HH:MM:SS` if >= 100m; `MM:SS` is standard for Pomodoro timers even up to 180:00).
    public var formattedRemainingTime: String {
        Self.formatSeconds(remainingSeconds)
    }

    public static func formatSeconds(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Starts or resumes the countdown. Ignored while ringing (must acknowledge first).
    public func start() {
        switch status {
        case .idle:
            remainingSeconds = configuredMinutes(for: phase) * 60
            targetEndDate = now().addingTimeInterval(TimeInterval(remainingSeconds))
            status = .running
        case .paused:
            targetEndDate = now().addingTimeInterval(TimeInterval(max(1, remainingSeconds)))
            status = .running
        case .running, .ringing:
            break
        }
    }

    /// Pauses a running countdown, preserving remaining seconds.
    public func pause() {
        guard status == .running else { return }
        syncRemainingFromClock()
        targetEndDate = nil
        if remainingSeconds > 0 {
            status = .paused
        } else {
            finishCurrentPhase()
        }
    }

    /// Toggles between running and paused/idle. Ignored while ringing.
    public func toggleStartPause() {
        switch status {
        case .idle, .paused:
            start()
        case .running:
            pause()
        case .ringing:
            break
        }
    }

    /// Resets the current phase back to idle with its full configured duration.
    public func reset() {
        targetEndDate = nil
        status = .idle
        remainingSeconds = configuredMinutes(for: phase) * 60
    }

    /// Switches to `newPhase` (or toggles between Work and Break) in idle state.
    public func switchPhase(to newPhase: PomodoroPhase? = nil) {
        phase = newPhase ?? phase.next
        targetEndDate = nil
        status = .idle
        remainingSeconds = configuredMinutes(for: phase) * 60
    }

    /// Acknowledges a ringing alarm, stops ringing, and advances to the next phase.
    /// Returns `true` if an active alarm was acknowledged.
    @discardableResult
    public func acknowledge(autoStartNext: Bool = false) -> Bool {
        guard status == .ringing else { return false }
        phase = phase.next
        targetEndDate = nil
        status = .idle
        remainingSeconds = configuredMinutes(for: phase) * 60
        if autoStartNext {
            start()
        }
        return true
    }

    /// Adjusts minutes for either Work or Break.
    /// - If `targetPhase` is currently running or paused, adjusts the active countdown immediately.
    /// - Otherwise, updates the configured phase duration (and updates `remainingSeconds` if idle on that phase).
    public func adjustMinutes(_ delta: Int, for targetPhase: PomodoroPhase) {
        guard delta != 0 else { return }

        if targetPhase == phase && (status == .running || status == .paused) {
            let deltaSeconds = delta * 60
            let updatedSeconds: Int
            if deltaSeconds < 0 {
                // Keep at least 60s when subtracting minutes from an active timer, unless already <= 60s.
                updatedSeconds = remainingSeconds > 60 ? max(60, remainingSeconds + deltaSeconds) : remainingSeconds
            } else {
                updatedSeconds = min(Self.maxMinutes * 60, remainingSeconds + deltaSeconds)
            }
            let appliedDelta = updatedSeconds - remainingSeconds
            remainingSeconds = updatedSeconds
            if status == .running, let endDate = targetEndDate {
                targetEndDate = endDate.addingTimeInterval(TimeInterval(appliedDelta))
            }
            return
        }

        // Update configured duration for idle or inactive phase (ignore while ringing).
        guard status != .ringing else { return }

        switch targetPhase {
        case .work:
            workMinutes = Self.clampMinutes(workMinutes + delta)
        case .breakTime:
            breakMinutes = Self.clampMinutes(breakMinutes + delta)
        }

        if status == .idle && targetPhase == phase {
            remainingSeconds = configuredMinutes(for: phase) * 60
        }
    }

    /// Resets Work and Break durations back to 25 and 5 minutes.
    /// If idle, also updates `remainingSeconds`.
    public func resetDurationsToDefault() {
        workMinutes = Self.defaultWorkMinutes
        breakMinutes = Self.defaultBreakMinutes
        if status == .idle {
            remainingSeconds = configuredMinutes(for: phase) * 60
        }
    }

    /// Advances timer state using current time.
    /// Returns `true` only on the transition into `.ringing`.
    @discardableResult
    public func tick() -> Bool {
        guard status == .running else { return false }
        syncRemainingFromClock()
        if remainingSeconds <= 0 {
            finishCurrentPhase()
            return true
        }
        return false
    }

    private func syncRemainingFromClock() {
        guard let endDate = targetEndDate else { return }
        let secondsLeft = Int(ceil(endDate.timeIntervalSince(now())))
        remainingSeconds = max(0, secondsLeft)
    }

    private func finishCurrentPhase() {
        targetEndDate = nil
        remainingSeconds = 0
        status = .ringing
        if phase == .work {
            completedWorkSessions += 1
        }
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(maxMinutes, max(minMinutes, value))
    }
}

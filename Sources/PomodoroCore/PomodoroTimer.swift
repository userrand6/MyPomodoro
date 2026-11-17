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

/// Single day entry in the GitHub-style activity heatmap.
public struct HeatmapDay: Equatable, Sendable {
    public let dateKey: String
    public let date: Date
    public let minutes: Int

    public init(dateKey: String, date: Date, minutes: Int) {
        self.dateKey = dateKey
        self.date = date
        self.minutes = minutes
    }
}

/// Pure Foundation state machine for the Pomodoro countdown, phase/cycle tracking,
/// duration adjustments, daily worked minutes tracking, and alarm acknowledgment.
public final class PomodoroTimer {
    public static let defaultWorkMinutes = 25
    public static let defaultBreakMinutes = 5
    public static let defaultTargetCycles = 4
    public static let minMinutes = 1
    public static let maxMinutes = 180
    public static let minCycles = 1
    public static let maxCycles = 20
    public static let maxHistoryDays = 365
    public static let dailyResetHour = 4

    public private(set) var phase: PomodoroPhase = .work
    public private(set) var status: PomodoroStatus = .idle
    public private(set) var workMinutes: Int
    public private(set) var breakMinutes: Int
    public private(set) var targetCycles: Int
    public private(set) var completedCyclesInSet: Int = 0
    public private(set) var remainingSeconds: Int
    public private(set) var completedWorkSessions: Int = 0
    public private(set) var dailyWorkedSeconds: [String: TimeInterval]
    public private(set) var workedDateKey: String

    private var targetEndDate: Date?
    private var lastWorkAccountedDate: Date?
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        workMinutes: Int = PomodoroTimer.defaultWorkMinutes,
        breakMinutes: Int = PomodoroTimer.defaultBreakMinutes,
        targetCycles: Int = PomodoroTimer.defaultTargetCycles,
        workedSecondsToday: TimeInterval = 0,
        workedDateKey: String? = nil,
        dailyWorkedSeconds: [String: TimeInterval] = [:],
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.workMinutes = Self.clampMinutes(workMinutes)
        self.breakMinutes = Self.clampMinutes(breakMinutes)
        self.targetCycles = Self.clampCycles(targetCycles)
        self.calendar = calendar
        self.now = now

        let currentDate = now()
        let today = Self.pomodoroDayKey(for: currentDate, calendar: calendar)
        var history: [String: TimeInterval] = [:]
        for (key, seconds) in dailyWorkedSeconds where seconds > 0 {
            history[key] = seconds
        }
        if let legacyKey = workedDateKey, workedSecondsToday > 0, history[legacyKey] == nil {
            history[legacyKey] = workedSecondsToday
        } else if workedDateKey == nil && workedSecondsToday > 0 && history[today] == nil {
            history[today] = workedSecondsToday
        }

        self.workedDateKey = today
        self.dailyWorkedSeconds = history
        self.remainingSeconds = self.workMinutes * 60
        pruneOldHistory(referenceDate: currentDate)
    }

    /// Seconds worked on the current local calendar day.
    public var workedSecondsToday: TimeInterval {
        dailyWorkedSeconds[workedDateKey] ?? 0
    }

    /// 1-based index of the current cycle within `targetCycles` (e.g., 1...4).
    public var currentCycleNumber: Int {
        min(targetCycles, completedCyclesInSet + 1)
    }

    /// Whole minutes worked on the current local calendar day.
    public var workedMinutesToday: Int {
        Int(workedSecondsToday) / 60
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

    /// Formats `remainingSeconds` as `MM:SS`.
    public var formattedRemainingTime: String {
        Self.formatSeconds(remainingSeconds)
    }

    public static func formatSeconds(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Logical Pomodoro day shifted by `dailyResetHour` (4:00 AM).
    public static func pomodoroLogicalDate(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: -dailyResetHour, to: date) ?? date
    }

    /// Date key (`yyyy-MM-dd`) anchored to the 4:00 AM daily reset boundary.
    public static func pomodoroDayKey(for date: Date, calendar: Calendar = .current) -> String {
        dateKey(for: pomodoroLogicalDate(for: date, calendar: calendar), calendar: calendar)
    }

    /// Starts or resumes the countdown. Ignored while ringing (must acknowledge first).
    public func start() {
        syncDailyDateIfNeeded()
        switch status {
        case .idle, .paused:
            let duration = max(1, remainingSeconds)
            remainingSeconds = duration
            let currentNow = now()
            targetEndDate = currentNow.addingTimeInterval(TimeInterval(duration))
            lastWorkAccountedDate = phase == .work ? currentNow : nil
            status = .running
        case .running, .ringing:
            break
        }
    }

    /// Pauses a running countdown, preserving remaining seconds and worked time so far.
    public func pause() {
        guard status == .running else { return }
        accountForElapsedWorkIfRunning()
        syncRemainingFromClock()
        targetEndDate = nil
        lastWorkAccountedDate = nil
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
        accountForElapsedWorkIfRunning()
        targetEndDate = nil
        lastWorkAccountedDate = nil
        status = .idle
        remainingSeconds = configuredMinutes(for: phase) * 60
    }

    /// Resets both the active timer and the current cycle progress back to Cycle 1.
    public func resetCycleProgress() {
        reset()
        completedCyclesInSet = 0
    }

    /// Skips the current Work or Break cycle and advances to the next phase/cycle in idle state.
    /// Does not modify persistent Work/Break settings.
    public func skipCurrentPhase() {
        accountForElapsedWorkIfRunning()
        advanceToNextPhase()
    }

    /// Acknowledges a ringing alarm, stops ringing, and advances to the next phase/cycle.
    /// Returns `true` if an active alarm was acknowledged.
    @discardableResult
    public func acknowledge(autoStartNext: Bool = false) -> Bool {
        guard status == .ringing else { return false }
        advanceToNextPhase()
        if autoStartNext {
            start()
        }
        return true
    }

    /// Temporarily extends only the current cycle's remaining time by `minutes` (+1 or +5)
    /// without altering the persistent Work/Break settings.
    /// When called at the end of a cycle (`.ringing`), it keeps the same phase,
    /// clears the ringing state, and resumes running for the added minutes.
    public func extendCurrentCycle(byMinutes minutes: Int) {
        guard minutes > 0 else { return }
        if status == .ringing {
            if phase == .work {
                completedWorkSessions = max(0, completedWorkSessions - 1)
            }
            let addedSeconds = min(Self.maxMinutes * 60, minutes * 60)
            remainingSeconds = addedSeconds
            let currentNow = now()
            targetEndDate = currentNow.addingTimeInterval(TimeInterval(addedSeconds))
            lastWorkAccountedDate = phase == .work ? currentNow : nil
            status = .running
            return
        }

        let updatedSeconds = min(Self.maxMinutes * 60, remainingSeconds + minutes * 60)
        let appliedDelta = updatedSeconds - remainingSeconds
        remainingSeconds = updatedSeconds
        if status == .running, let endDate = targetEndDate {
            targetEndDate = endDate.addingTimeInterval(TimeInterval(appliedDelta))
        }
    }

    private func advanceToNextPhase() {
        let finishedPhase = phase
        phase = finishedPhase.next
        if finishedPhase == .breakTime {
            completedCyclesInSet += 1
            if completedCyclesInSet >= targetCycles {
                completedCyclesInSet = 0
            }
        }
        targetEndDate = nil
        lastWorkAccountedDate = nil
        status = .idle
        remainingSeconds = configuredMinutes(for: phase) * 60
    }

    public func setWorkMinutes(_ minutes: Int) {
        workMinutes = Self.clampMinutes(minutes)
        if status == .idle && phase == .work {
            remainingSeconds = workMinutes * 60
        }
    }

    public func setBreakMinutes(_ minutes: Int) {
        breakMinutes = Self.clampMinutes(minutes)
        if status == .idle && phase == .breakTime {
            remainingSeconds = breakMinutes * 60
        }
    }

    public func setTargetCycles(_ cycles: Int) {
        targetCycles = Self.clampCycles(cycles)
        if completedCyclesInSet >= targetCycles {
            completedCyclesInSet = 0
        }
    }

    /// Resets Work, Break, and Cycle count back to defaults (25 / 5 / 4).
    public func resetDurationsToDefault() {
        workMinutes = Self.defaultWorkMinutes
        breakMinutes = Self.defaultBreakMinutes
        targetCycles = Self.defaultTargetCycles
        if completedCyclesInSet >= targetCycles {
            completedCyclesInSet = 0
        }
        if status == .idle {
            remainingSeconds = configuredMinutes(for: phase) * 60
        }
    }

    /// Resets today's worked counter to zero.
    public func resetWorkedToday() {
        workedDateKey = Self.pomodoroDayKey(for: now(), calendar: calendar)
        dailyWorkedSeconds.removeValue(forKey: workedDateKey)
        if status == .running && phase == .work {
            lastWorkAccountedDate = now()
        }
    }

    /// Whole minutes worked on a specific `yyyy-MM-dd` date key.
    public func workedMinutes(on dateKey: String) -> Int {
        Int(dailyWorkedSeconds[dateKey] ?? 0) / 60
    }

    /// Returns a Sunday-to-Saturday GitHub-style grid for the last `weeks` weeks.
    /// Future days in the final week column are `nil`.
    public func heatmapGrid(weeks: Int = 19) -> [[HeatmapDay?]] {
        let clampedWeeks = max(1, weeks)
        let currentDate = now()
        let logicalToday = Self.pomodoroLogicalDate(for: currentDate, calendar: calendar)
        let todayStart = calendar.startOfDay(for: logicalToday)
        let weekday = calendar.component(.weekday, from: todayStart)
        let daysSinceSunday = weekday - 1

        guard
            let currentWeekSunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: todayStart),
            let firstWeekSunday = calendar.date(byAdding: .day, value: -(clampedWeeks - 1) * 7, to: currentWeekSunday)
        else {
            return []
        }

        var grid: [[HeatmapDay?]] = []
        grid.reserveCapacity(clampedWeeks)

        for weekOffset in 0..<clampedWeeks {
            var column: [HeatmapDay?] = []
            column.reserveCapacity(7)
            for dayOffset in 0..<7 {
                guard let cellDate = calendar.date(byAdding: .day, value: weekOffset * 7 + dayOffset, to: firstWeekSunday) else {
                    column.append(nil)
                    continue
                }
                if cellDate > todayStart {
                    column.append(nil)
                } else {
                    let key = Self.dateKey(for: cellDate, calendar: calendar)
                    column.append(HeatmapDay(dateKey: key, date: cellDate, minutes: workedMinutes(on: key)))
                }
            }
            grid.append(column)
        }

        return grid
    }

    /// Checks for the 4:00 AM daily rollover (or whenever active next) and resets
    /// daily worked minutes and cycle progress.
    @discardableResult
    public func syncDailyDateIfNeeded() -> Bool {
        let currentDate = now()
        let today = Self.pomodoroDayKey(for: currentDate, calendar: calendar)
        guard today != workedDateKey else { return false }
        workedDateKey = today
        completedCyclesInSet = 0
        if status == .idle {
            phase = .work
            remainingSeconds = workMinutes * 60
        }
        pruneOldHistory(referenceDate: Self.pomodoroLogicalDate(for: currentDate, calendar: calendar))
        return true
    }

    /// Advances timer state using current time.
    /// Returns `true` only on the transition into `.ringing`.
    @discardableResult
    public func tick() -> Bool {
        syncDailyDateIfNeeded()
        guard status == .running else { return false }
        accountForElapsedWorkIfRunning()
        syncRemainingFromClock()
        if remainingSeconds <= 0 {
            finishCurrentPhase()
            return true
        }
        return false
    }

    private func accountForElapsedWorkIfRunning() {
        guard status == .running, phase == .work else { return }
        let currentNow = now()
        guard let lastDate = lastWorkAccountedDate else {
            lastWorkAccountedDate = currentNow
            return
        }
        let elapsed = max(0, currentNow.timeIntervalSince(lastDate))
        let maxAccountable: TimeInterval
        if let endDate = targetEndDate {
            maxAccountable = max(0, endDate.timeIntervalSince(lastDate))
        } else {
            maxAccountable = elapsed
        }
        let accountable = min(elapsed, maxAccountable)
        if accountable > 0 {
            dailyWorkedSeconds[workedDateKey, default: 0] += accountable
        }
        lastWorkAccountedDate = currentNow
    }

    private func pruneOldHistory(referenceDate: Date) {
        guard let cutoffDate = calendar.date(byAdding: .day, value: -Self.maxHistoryDays, to: calendar.startOfDay(for: referenceDate)) else {
            return
        }
        let cutoffKey = Self.dateKey(for: cutoffDate, calendar: calendar)
        dailyWorkedSeconds = dailyWorkedSeconds.filter { $0.key >= cutoffKey && $0.value > 0 }
    }

    private func syncRemainingFromClock() {
        guard let endDate = targetEndDate else { return }
        let secondsLeft = Int(ceil(endDate.timeIntervalSince(now())))
        remainingSeconds = max(0, secondsLeft)
    }

    private func finishCurrentPhase() {
        targetEndDate = nil
        lastWorkAccountedDate = nil
        remainingSeconds = 0
        status = .ringing
        if phase == .work {
            completedWorkSessions += 1
        }
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(maxMinutes, max(minMinutes, value))
    }

    private static func clampCycles(_ value: Int) -> Int {
        min(maxCycles, max(minCycles, value))
    }
}

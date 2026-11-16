import Foundation
import Testing
@testable import PomodoroCore

struct PomodoroTimerTests {
    @Test
    func initialDefaults() {
        let timer = PomodoroTimer()
        #expect(timer.phase == .work)
        #expect(timer.status == .idle)
        #expect(timer.workMinutes == 25)
        #expect(timer.breakMinutes == 5)
        #expect(timer.targetCycles == 4)
        #expect(timer.currentCycleNumber == 1)
        #expect(timer.remainingSeconds == 25 * 60)
        #expect(timer.formattedRemainingTime == "25:00")
        #expect(timer.completedWorkSessions == 0)
        #expect(timer.workedMinutesToday == 0)
    }

    @Test
    func countdownTransitionsToRingingAndIncrementsSessions() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 1, breakMinutes: 5, now: { currentDate })

        timer.start()
        #expect(timer.status == .running)
        #expect(timer.remainingSeconds == 60)

        currentDate = currentDate.addingTimeInterval(25)
        #expect(!timer.tick())
        #expect(timer.status == .running)
        #expect(timer.remainingSeconds == 35)
        #expect(timer.formattedRemainingTime == "00:35")

        currentDate = currentDate.addingTimeInterval(35)
        #expect(timer.tick())
        #expect(timer.status == .ringing)
        #expect(timer.remainingSeconds == 0)
        #expect(timer.completedWorkSessions == 1)
        #expect(timer.workedMinutesToday == 1)

        // Subsequent ticks while ringing do not re-trigger transition.
        #expect(!timer.tick())
        #expect(timer.status == .ringing)
    }

    @Test
    func startIsIgnoredUntilAcknowledged() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 1, breakMinutes: 2, now: { currentDate })

        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.status == .ringing)

        timer.start()
        #expect(timer.status == .ringing)

        #expect(timer.acknowledge())
        #expect(timer.status == .idle)
        #expect(timer.phase == .breakTime)
        #expect(timer.remainingSeconds == 120)
    }

    @Test
    func acknowledgeAndAutoStartNext() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 1, breakMinutes: 3, now: { currentDate })

        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        timer.tick()

        #expect(timer.acknowledge(autoStartNext: true))
        #expect(timer.phase == .breakTime)
        #expect(timer.status == .running)
        #expect(timer.remainingSeconds == 180)
    }

    @Test
    func cycleCountProgressesAndWrapsAfterTargetCycles() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 1, breakMinutes: 1, targetCycles: 2, now: { currentDate })

        #expect(timer.currentCycleNumber == 1)

        // Cycle 1: Work -> Break
        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.acknowledge())
        #expect(timer.phase == .breakTime)
        #expect(timer.currentCycleNumber == 1)

        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.acknowledge())
        #expect(timer.phase == .work)
        #expect(timer.currentCycleNumber == 2)

        // Cycle 2: Work -> Break -> wraps back to Cycle 1
        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.acknowledge())
        #expect(timer.phase == .breakTime)
        #expect(timer.currentCycleNumber == 2)

        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.acknowledge())
        #expect(timer.phase == .work)
        #expect(timer.currentCycleNumber == 1)
    }

    @Test
    func workedMinutesTodayCountsWorkOnlyCapsSleepAndResetsOnNewDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var currentDate = Date(timeIntervalSince1970: 1_700_000_000)

        let timer = PomodoroTimer(
            workMinutes: 2,
            breakMinutes: 5,
            calendar: calendar,
            now: { currentDate }
        )

        // Work 90s then pause -> 1 whole minute worked.
        timer.start()
        currentDate = currentDate.addingTimeInterval(90)
        timer.pause()
        #expect(timer.workedMinutesToday == 1)

        // Resume and sleep way past end time -> capped at remaining 30s (total 120s = 2 min).
        timer.start()
        currentDate = currentDate.addingTimeInterval(3_600)
        #expect(timer.tick())
        #expect(timer.workedMinutesToday == 2)

        // Break time does NOT add to workedMinutesToday.
        #expect(timer.acknowledge(autoStartNext: true))
        #expect(timer.phase == .breakTime)
        currentDate = currentDate.addingTimeInterval(300)
        #expect(timer.tick())
        #expect(timer.workedMinutesToday == 2)

        // Next day rollover resets worked minutes to 0.
        currentDate = currentDate.addingTimeInterval(86_400)
        #expect(timer.syncDailyDateIfNeeded())
        #expect(timer.workedMinutesToday == 0)
    }

    @Test
    func persistedDailyWorkedRestoresSameDayAndResetsDifferentDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let todayKey = PomodoroTimer.dateKey(for: currentDate, calendar: calendar)

        let sameDay = PomodoroTimer(
            workedSecondsToday: 1_500,
            workedDateKey: todayKey,
            calendar: calendar,
            now: { currentDate }
        )
        #expect(sameDay.workedMinutesToday == 25)

        let staleDay = PomodoroTimer(
            workedSecondsToday: 1_500,
            workedDateKey: "1999-01-01",
            calendar: calendar,
            now: { currentDate }
        )
        #expect(staleDay.workedMinutesToday == 0)
        #expect(staleDay.workedDateKey == todayKey)
    }

    @Test
    func heatmapGridAlignsWeeksAndTracksMultiDayHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-11-16 is a Monday (weekday == 2 -> Sunday row 0, Monday row 1, Tue..Sat nil)
        let components = DateComponents(year: 2026, month: 11, day: 16, hour: 12)
        let monday = calendar.date(from: components)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: monday)!
        let todayKey = PomodoroTimer.dateKey(for: monday, calendar: calendar)
        let yesterdayKey = PomodoroTimer.dateKey(for: yesterday, calendar: calendar)

        let timer = PomodoroTimer(
            dailyWorkedSeconds: [
                yesterdayKey: 45 * 60,
                todayKey: 90 * 60,
                "2020-01-01": 60 * 60 // should be pruned (> 365 days old)
            ],
            calendar: calendar,
            now: { monday }
        )

        #expect(timer.dailyWorkedSeconds["2020-01-01"] == nil)
        #expect(timer.workedMinutes(on: yesterdayKey) == 45)
        #expect(timer.workedMinutes(on: todayKey) == 90)

        let grid = timer.heatmapGrid(weeks: 4)
        #expect(grid.count == 4)
        #expect(grid.allSatisfy { $0.count == 7 })
        #expect(grid[3][0]?.minutes == 45)
        #expect(grid[3][1]?.minutes == 90)
        #expect(grid[3][2] == nil)
    }

    @Test
    func settingsUpdateCycleLengthsAndCount() {
        let timer = PomodoroTimer()
        timer.setWorkMinutes(45)
        timer.setBreakMinutes(10)
        timer.setTargetCycles(6)

        #expect(timer.workMinutes == 45)
        #expect(timer.breakMinutes == 10)
        #expect(timer.targetCycles == 6)
        #expect(timer.remainingSeconds == 45 * 60)

        timer.resetDurationsToDefault()
        #expect(timer.workMinutes == 25)
        #expect(timer.breakMinutes == 5)
        #expect(timer.targetCycles == 4)
        #expect(timer.remainingSeconds == 25 * 60)
    }

    @Test
    func extendCurrentCyclePlusOneAndPlusFiveDoesNotChangeSettings() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 25, breakMinutes: 5, now: { currentDate })

        // Extend while idle, then start — extended duration is used without modifying workMinutes.
        timer.extendCurrentCycle(byMinutes: 1)
        #expect(timer.workMinutes == 25)
        #expect(timer.remainingSeconds == 26 * 60)

        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        timer.tick()
        #expect(timer.remainingSeconds == 25 * 60)

        // Extend while running by +5 min.
        timer.extendCurrentCycle(byMinutes: 5)
        #expect(timer.workMinutes == 25)
        #expect(timer.remainingSeconds == 30 * 60)

        // Reset restores configured 25 min duration.
        timer.reset()
        #expect(timer.remainingSeconds == 25 * 60)
    }

    @Test
    func extendWhileRingingResumesSamePhaseAndDoesNotDoubleCountSession() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 1, breakMinutes: 1, now: { currentDate })

        // Finish Work -> ringing
        timer.start()
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.status == .ringing)
        #expect(timer.phase == .work)
        #expect(timer.completedWorkSessions == 1)

        // Extend Work by +5 min while ringing -> resumes running Work, no double session count.
        timer.extendCurrentCycle(byMinutes: 5)
        #expect(timer.status == .running)
        #expect(timer.phase == .work)
        #expect(timer.remainingSeconds == 300)
        #expect(timer.completedWorkSessions == 0)

        currentDate = currentDate.addingTimeInterval(300)
        #expect(timer.tick())
        #expect(timer.status == .ringing)
        #expect(timer.completedWorkSessions == 1)
        #expect(timer.workedMinutesToday == 6)

        // Acknowledge -> Break, finish Break -> ringing, extend Break by +1 min -> resumes Break.
        #expect(timer.acknowledge(autoStartNext: true))
        #expect(timer.phase == .breakTime)
        currentDate = currentDate.addingTimeInterval(60)
        #expect(timer.tick())
        #expect(timer.status == .ringing)

        timer.extendCurrentCycle(byMinutes: 1)
        #expect(timer.status == .running)
        #expect(timer.phase == .breakTime)
        #expect(timer.remainingSeconds == 60)
    }

    @Test
    func skipWorkAndSkipBreakAdvanceCycleAndPreserveWorkedMinutes() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 10, breakMinutes: 5, targetCycles: 2, now: { currentDate })

        timer.start()
        currentDate = currentDate.addingTimeInterval(120)
        timer.skipCurrentPhase()

        #expect(timer.phase == .breakTime)
        #expect(timer.status == .idle)
        #expect(timer.currentCycleNumber == 1)
        #expect(timer.workedMinutesToday == 2)
        #expect(timer.remainingSeconds == 5 * 60)

        timer.skipCurrentPhase()
        #expect(timer.phase == .work)
        #expect(timer.currentCycleNumber == 2)
        #expect(timer.remainingSeconds == 10 * 60)

        // Skip Work -> Break, then Skip Break -> wraps back to Cycle 1.
        timer.skipCurrentPhase()
        timer.skipCurrentPhase()
        #expect(timer.phase == .work)
        #expect(timer.currentCycleNumber == 1)
    }

    @Test
    func pauseAndResumePreservesRemainingTime() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 2, breakMinutes: 5, now: { currentDate })

        timer.start()
        currentDate = currentDate.addingTimeInterval(40)
        timer.pause()
        #expect(timer.status == .paused)
        #expect(timer.remainingSeconds == 80)

        // Time passes while paused.
        currentDate = currentDate.addingTimeInterval(500)
        timer.tick()
        #expect(timer.remainingSeconds == 80)

        timer.start()
        #expect(timer.status == .running)
        currentDate = currentDate.addingTimeInterval(80)
        #expect(timer.tick())
        #expect(timer.status == .ringing)
    }
}

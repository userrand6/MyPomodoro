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
        #expect(timer.remainingSeconds == 25 * 60)
        #expect(timer.formattedRemainingTime == "25:00")
        #expect(timer.completedWorkSessions == 0)
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
    func plusOneAndPlusTwoMinuteButtonsWhenIdle() {
        let timer = PomodoroTimer(workMinutes: 25, breakMinutes: 5)

        timer.adjustMinutes(1, for: .work)
        #expect(timer.workMinutes == 26)
        #expect(timer.remainingSeconds == 26 * 60)

        timer.adjustMinutes(2, for: .work)
        #expect(timer.workMinutes == 28)
        #expect(timer.remainingSeconds == 28 * 60)

        // Adjusting break while idle on work updates break duration without overwriting work countdown.
        timer.adjustMinutes(1, for: .breakTime)
        timer.adjustMinutes(2, for: .breakTime)
        #expect(timer.breakMinutes == 8)
        #expect(timer.remainingSeconds == 28 * 60)

        timer.switchPhase(to: .breakTime)
        #expect(timer.remainingSeconds == 8 * 60)
    }

    @Test
    func plusOneAndPlusTwoMinuteButtonsWhileRunning() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let timer = PomodoroTimer(workMinutes: 2, breakMinutes: 5, now: { currentDate })

        timer.start()
        currentDate = currentDate.addingTimeInterval(30)
        timer.tick()
        #expect(timer.remainingSeconds == 90)

        // Extend active work timer by +1 min and +2 min.
        timer.adjustMinutes(1, for: .work)
        #expect(timer.remainingSeconds == 150)
        #expect(timer.workMinutes == 2)

        timer.adjustMinutes(2, for: .work)
        #expect(timer.remainingSeconds == 270)

        // Adjust upcoming break while work is running.
        timer.adjustMinutes(2, for: .breakTime)
        #expect(timer.breakMinutes == 7)
        #expect(timer.remainingSeconds == 270)

        // Adjusted end time is respected on subsequent tick.
        currentDate = currentDate.addingTimeInterval(270)
        #expect(timer.tick())
        #expect(timer.status == .ringing)
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

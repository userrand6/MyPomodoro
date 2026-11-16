import AppKit
import PomodoroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let workMinutes = "MyPomodoro.workMinutes"
        static let breakMinutes = "MyPomodoro.breakMinutes"
        static let targetCycles = "MyPomodoro.targetCycles"
        static let soundName = "MyPomodoro.soundName"
        static let isMuted = "MyPomodoro.isMuted"
        static let autoStartNext = "MyPomodoro.autoStartNext"
        static let showHeatmap = "MyPomodoro.showHeatmap"
        static let workedDateKey = "MyPomodoro.workedDateKey"
        static let workedSecondsToday = "MyPomodoro.workedSecondsToday"
        static let dailyWorkedSeconds = "MyPomodoro.dailyWorkedSeconds"
    }

    private let defaults = UserDefaults.standard
    private let alarmPlayer = AlarmPlayer()
    private let popover = NSPopover()
    private let popoverViewController = PopoverViewController()

    private var timer: PomodoroTimer!
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var lastDisplayedSecond: Int = -1
    private var lastSavedWorkedMinute: Int = -1
    private var lastSymbolName: String?
    private var lastToolTip: String?
    private var lastStatusLength: CGFloat = -1
    private var launchAtLoginEnabled = false
    private var ringPulseOn = false

    private var selectedSound: String {
        get {
            let stored = defaults.string(forKey: DefaultsKey.soundName)
            if let stored, AlarmPlayer.availableSounds.contains(stored) {
                return stored
            }
            return AlarmPlayer.availableSounds[0]
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.soundName)
        }
    }

    private var isMuted: Bool {
        get { defaults.bool(forKey: DefaultsKey.isMuted) }
        set { defaults.set(newValue, forKey: DefaultsKey.isMuted) }
    }

    private var autoStartNext: Bool {
        get { defaults.bool(forKey: DefaultsKey.autoStartNext) }
        set { defaults.set(newValue, forKey: DefaultsKey.autoStartNext) }
    }

    private var showHeatmap: Bool {
        get { defaults.bool(forKey: DefaultsKey.showHeatmap) }
        set { defaults.set(newValue, forKey: DefaultsKey.showHeatmap) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let savedWork = defaults.object(forKey: DefaultsKey.workMinutes) as? Int ?? PomodoroTimer.defaultWorkMinutes
        let savedBreak = defaults.object(forKey: DefaultsKey.breakMinutes) as? Int ?? PomodoroTimer.defaultBreakMinutes
        let savedCycles = defaults.object(forKey: DefaultsKey.targetCycles) as? Int ?? PomodoroTimer.defaultTargetCycles
        let savedWorkedDate = defaults.string(forKey: DefaultsKey.workedDateKey)
        let savedWorkedSeconds = defaults.double(forKey: DefaultsKey.workedSecondsToday)
        let savedHistory = defaults.dictionary(forKey: DefaultsKey.dailyWorkedSeconds) as? [String: Double] ?? [:]

        timer = PomodoroTimer(
            workMinutes: savedWork,
            breakMinutes: savedBreak,
            targetCycles: savedCycles,
            workedSecondsToday: savedWorkedSeconds,
            workedDateKey: savedWorkedDate,
            dailyWorkedSeconds: savedHistory
        )
        lastSavedWorkedMinute = timer.workedMinutesToday
        saveDailyWorked()
        launchAtLoginEnabled = LaunchAtLogin.isEnabled

        setupStatusItem()
        setupPopover()
        setupCallbacks()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        alarmPlayer.stop()
        if timer.status == .running {
            timer.pause()
        }
        saveDailyWorked()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func setupPopover() {
        popover.contentViewController = popoverViewController
        popover.behavior = .transient
        popover.animates = true
    }

    private func setupCallbacks() {
        alarmPlayer.onPulse = { [weak self] in
            guard let self else { return }
            self.ringPulseOn.toggle()
            self.updateStatusButton()
        }

        alarmPlayer.onTimeout = { [weak self] in
            guard let self else { return }
            self.ringPulseOn = true
            self.updateStatusButton()
        }

        popoverViewController.onStartPause = { [weak self] in
            guard let self else { return }
            self.timer.toggleStartPause()
            self.saveDailyWorked()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onReset = { [weak self] in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.timer.reset()
            self.saveDailyWorked()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onAcknowledge = { [weak self] autoStartNext in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.ringPulseOn = false
            self.timer.acknowledge(autoStartNext: autoStartNext)
            self.saveDailyWorked()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onSkipPhase = { [weak self] in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.ringPulseOn = false
            self.timer.skipCurrentPhase()
            self.saveDailyWorked()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onExtendCurrentCycle = { [weak self] minutes in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.ringPulseOn = false
            self.timer.extendCurrentCycle(byMinutes: minutes)
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onSetWorkMinutes = { [weak self] minutes in
            guard let self else { return }
            self.timer.setWorkMinutes(minutes)
            self.saveSettings()
            self.refreshUI()
        }

        popoverViewController.onSetBreakMinutes = { [weak self] minutes in
            guard let self else { return }
            self.timer.setBreakMinutes(minutes)
            self.saveSettings()
            self.refreshUI()
        }

        popoverViewController.onSetTargetCycles = { [weak self] cycles in
            guard let self else { return }
            self.timer.setTargetCycles(cycles)
            self.saveSettings()
            self.refreshUI()
        }

        popoverViewController.onResetDefaults = { [weak self] in
            guard let self else { return }
            self.timer.resetDurationsToDefault()
            self.saveSettings()
            self.refreshUI()
        }

        popoverViewController.onResetWorkedToday = { [weak self] in
            guard let self else { return }
            self.timer.resetWorkedToday()
            self.lastSavedWorkedMinute = self.timer.workedMinutesToday
            self.saveDailyWorked()
            self.refreshUI()
        }

        popoverViewController.onResetCycleProgress = { [weak self] in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.timer.resetCycleProgress()
            self.saveDailyWorked()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onSelectSound = { [weak self] soundName in
            guard let self else { return }
            self.selectedSound = soundName
            if !self.isMuted {
                if self.alarmPlayer.isRinging {
                    self.alarmPlayer.start(soundName: soundName)
                } else {
                    self.alarmPlayer.playOnce(soundName: soundName)
                }
            }
            self.refreshUI()
        }

        popoverViewController.onToggleMute = { [weak self] in
            guard let self else { return }
            self.isMuted.toggle()
            if self.isMuted {
                self.alarmPlayer.stop()
            } else if self.timer.status == .ringing {
                self.alarmPlayer.start(soundName: self.selectedSound)
            }
            self.refreshUI()
        }

        popoverViewController.onToggleLaunchAtLogin = { [weak self] in
            guard let self else { return }
            let desired = !self.launchAtLoginEnabled
            _ = LaunchAtLogin.setEnabled(desired)
            self.launchAtLoginEnabled = LaunchAtLogin.isEnabled
            self.refreshUI()
        }

        popoverViewController.onToggleAutoStartNext = { [weak self] in
            guard let self else { return }
            self.autoStartNext.toggle()
            self.refreshUI()
        }

        popoverViewController.onToggleShowHeatmap = { [weak self] in
            guard let self else { return }
            self.showHeatmap.toggle()
            self.refreshUI()
        }

        popoverViewController.onPreferredSizeChanged = { [weak self] size in
            guard let self else { return }
            if self.popover.isShown {
                self.popover.contentSize = size
            }
        }

        popoverViewController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func saveSettings() {
        defaults.set(timer.workMinutes, forKey: DefaultsKey.workMinutes)
        defaults.set(timer.breakMinutes, forKey: DefaultsKey.breakMinutes)
        defaults.set(timer.targetCycles, forKey: DefaultsKey.targetCycles)
    }

    private func saveDailyWorked() {
        defaults.set(timer.workedDateKey, forKey: DefaultsKey.workedDateKey)
        defaults.set(timer.workedSecondsToday, forKey: DefaultsKey.workedSecondsToday)
        defaults.set(timer.dailyWorkedSeconds, forKey: DefaultsKey.dailyWorkedSeconds)
    }

    private func syncTickTimer() {
        if timer.status == .running {
            guard tickTimer == nil else { return }
            lastDisplayedSecond = timer.remainingSeconds
            let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleTick()
                }
            }
            newTimer.tolerance = 0.05
            RunLoop.main.add(newTimer, forMode: .common)
            tickTimer = newTimer
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func handleTick() {
        let justFinished = timer.tick()

        let currentWorkedMinute = timer.workedMinutesToday
        if currentWorkedMinute != lastSavedWorkedMinute {
            lastSavedWorkedMinute = currentWorkedMinute
            saveDailyWorked()
        }

        if justFinished {
            saveDailyWorked()
            syncTickTimer()
            ringPulseOn = true
            if !isMuted {
                alarmPlayer.start(soundName: selectedSound)
            }
            openPopover()
            return
        }

        if timer.remainingSeconds != lastDisplayedSecond {
            lastDisplayedSecond = timer.remainingSeconds
            updateStatusButton()
            if popover.isShown {
                popoverViewController.updateCountdownOnly(timer: timer)
            }
        }
    }

    private func refreshUI() {
        updateStatusButton()
        updatePopoverView()
    }

    private func updatePopoverView() {
        popoverViewController.update(
            timer: timer,
            selectedSound: selectedSound,
            isMuted: isMuted,
            launchAtLogin: launchAtLoginEnabled,
            autoStartNext: autoStartNext,
            showHeatmap: showHeatmap
        )
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let title: String
        let tintColor: NSColor?
        let toolTipText: String
        let cycleInfo = "Cycle \(timer.currentCycleNumber)/\(timer.targetCycles)"
        let workedInfo = "Today: \(timer.workedMinutesToday) min"
        let muteSuffix = isMuted ? " [Muted]" : ""

        switch timer.status {
        case .idle:
            symbolName = "timer"
            title = ""
            tintColor = nil
            toolTipText = "MyPomodoro — Idle (\(timer.phase.displayName) \(timer.formattedRemainingTime), \(cycleInfo), \(workedInfo))\(muteSuffix)"
        case .running:
            symbolName = timer.phase == .work ? "timer" : "cup.and.saucer.fill"
            title = " \(timer.formattedRemainingTime)"
            tintColor = nil
            toolTipText = "MyPomodoro — \(timer.phase.displayName) running (\(cycleInfo), \(workedInfo))\(muteSuffix)"
        case .paused:
            symbolName = "pause.circle"
            title = " \(timer.formattedRemainingTime)"
            tintColor = .systemOrange
            toolTipText = "MyPomodoro — \(timer.phase.displayName) paused (\(timer.formattedRemainingTime) left, \(cycleInfo), \(workedInfo))\(muteSuffix)"
        case .ringing:
            symbolName = ringPulseOn ? "bell.badge.fill" : "bell.fill"
            title = " 00:00"
            tintColor = .systemRed
            toolTipText = "MyPomodoro — \(timer.phase.displayName) finished! Click to acknowledge.\(muteSuffix)"
        }

        if lastSymbolName != symbolName {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MyPomodoro")
            image?.isTemplate = true
            button.image = image
            lastSymbolName = symbolName
        }

        let desiredLength: CGFloat = title.isEmpty ? NSStatusItem.squareLength : (title.count >= 7 ? 84 : 74)
        if lastStatusLength != desiredLength {
            statusItem.length = desiredLength
            lastStatusLength = desiredLength
        }

        if lastToolTip != toolTipText {
            button.toolTip = toolTipText
            lastToolTip = toolTipText
        }

        if button.contentTintColor != tintColor {
            button.contentTintColor = tintColor
        }
        if button.title != title {
            button.title = title
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        if timer.syncDailyDateIfNeeded() {
            lastSavedWorkedMinute = timer.workedMinutesToday
            saveDailyWorked()
        }
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        popoverViewController.showTimerPage()
        refreshUI()
        let size = popoverViewController.preferredContentSize
        if size.width > 0 && size.height > 0 {
            popover.contentSize = size
        }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            openPopover()
        }
    }
}

import AppKit
import PomodoroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let workMinutes = "MyPomodoro.workMinutes"
        static let breakMinutes = "MyPomodoro.breakMinutes"
        static let soundName = "MyPomodoro.soundName"
    }

    private let defaults = UserDefaults.standard
    private let alarmPlayer = AlarmPlayer()
    private let popover = NSPopover()
    private let popoverViewController = PopoverViewController()

    private var timer: PomodoroTimer!
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var lastDisplayedSecond: Int = -1
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let savedWork = defaults.object(forKey: DefaultsKey.workMinutes) as? Int ?? PomodoroTimer.defaultWorkMinutes
        let savedBreak = defaults.object(forKey: DefaultsKey.breakMinutes) as? Int ?? PomodoroTimer.defaultBreakMinutes
        timer = PomodoroTimer(workMinutes: savedWork, breakMinutes: savedBreak)

        setupStatusItem()
        setupPopover()
        setupCallbacks()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        alarmPlayer.stop()
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

        popoverViewController.onStartPause = { [weak self] in
            guard let self else { return }
            self.timer.toggleStartPause()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onReset = { [weak self] in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.timer.reset()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onAcknowledge = { [weak self] autoStartNext in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.ringPulseOn = false
            self.timer.acknowledge(autoStartNext: autoStartNext)
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onSwitchPhase = { [weak self] in
            guard let self else { return }
            self.alarmPlayer.stop()
            self.timer.switchPhase()
            self.syncTickTimer()
            self.refreshUI()
        }

        popoverViewController.onAdjustMinutes = { [weak self] delta, targetPhase in
            guard let self else { return }
            self.timer.adjustMinutes(delta, for: targetPhase)
            self.saveDurations()
            self.refreshUI()
        }

        popoverViewController.onResetDefaults = { [weak self] in
            guard let self else { return }
            self.timer.resetDurationsToDefault()
            self.saveDurations()
            self.refreshUI()
        }

        popoverViewController.onSelectSound = { [weak self] soundName in
            guard let self else { return }
            self.selectedSound = soundName
            if !self.alarmPlayer.isRinging {
                self.alarmPlayer.playOnce(soundName: soundName)
            } else {
                self.alarmPlayer.start(soundName: soundName)
            }
            self.refreshUI()
        }

        popoverViewController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func saveDurations() {
        defaults.set(timer.workMinutes, forKey: DefaultsKey.workMinutes)
        defaults.set(timer.breakMinutes, forKey: DefaultsKey.breakMinutes)
    }

    private func syncTickTimer() {
        if timer.status == .running {
            guard tickTimer == nil else { return }
            lastDisplayedSecond = timer.remainingSeconds
            let newTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleTick()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            tickTimer = newTimer
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func handleTick() {
        let justFinished = timer.tick()
        if justFinished {
            syncTickTimer()
            ringPulseOn = true
            alarmPlayer.start(soundName: selectedSound)
            refreshUI()
            return
        }

        if timer.remainingSeconds != lastDisplayedSecond {
            lastDisplayedSecond = timer.remainingSeconds
            refreshUI()
        }
    }

    private func refreshUI() {
        updateStatusButton()
        popoverViewController.update(timer: timer, selectedSound: selectedSound)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let title: String
        let tintColor: NSColor?

        switch timer.status {
        case .idle:
            symbolName = "timer"
            title = ""
            tintColor = nil
            button.toolTip = "MyPomodoro — Idle (\(timer.phase.displayName) \(timer.formattedRemainingTime))"
        case .running:
            symbolName = timer.phase == .work ? "timer" : "cup.and.saucer.fill"
            title = " \(timer.formattedRemainingTime)"
            tintColor = nil
            button.toolTip = "MyPomodoro — \(timer.phase.displayName) running (\(timer.formattedRemainingTime) left)"
        case .paused:
            symbolName = "pause.circle"
            title = " \(timer.formattedRemainingTime)"
            tintColor = .systemOrange
            button.toolTip = "MyPomodoro — \(timer.phase.displayName) paused (\(timer.formattedRemainingTime) left)"
        case .ringing:
            symbolName = ringPulseOn ? "bell.badge.fill" : "bell.fill"
            title = " 00:00"
            tintColor = .systemRed
            button.toolTip = "MyPomodoro — \(timer.phase.displayName) finished! Click to acknowledge."
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MyPomodoro")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tintColor
        button.title = title
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshUI()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

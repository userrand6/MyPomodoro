import AppKit
import PomodoroCore

@MainActor
final class PopoverViewController: NSViewController {
    var onStartPause: (() -> Void)?
    var onReset: (() -> Void)?
    var onAcknowledge: ((_ autoStartNext: Bool) -> Void)?
    var onSkipPhase: (() -> Void)?
    var onExtendCurrentCycle: ((_ minutes: Int) -> Void)?
    var onSetWorkMinutes: ((_ minutes: Int) -> Void)?
    var onSetBreakMinutes: ((_ minutes: Int) -> Void)?
    var onSetTargetCycles: ((_ cycles: Int) -> Void)?
    var onResetDefaults: (() -> Void)?
    var onResetWorkedToday: (() -> Void)?
    var onResetCycleProgress: (() -> Void)?
    var onSelectSound: ((_ soundName: String) -> Void)?
    var onToggleMute: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onToggleAutoStartNext: (() -> Void)?
    var onToggleShowHeatmap: (() -> Void)?
    var onPreferredSizeChanged: ((_ size: NSSize) -> Void)?
    var onQuit: (() -> Void)?

    // Containers
    private let timerContainer = NSStackView()
    private let settingsContainer = NSStackView()
    private var showingSettings = false

    // Timer view elements
    private let phaseLabel = NSTextField(labelWithString: "WORK • Cycle 1/4")
    private let workedTodayLabel = NSTextField(labelWithString: "Today: 0 min")
    private let countdownLabel = NSTextField(labelWithString: "25:00")
    private let statusLabel = NSTextField(labelWithString: "Ready")

    private let normalControlsStack = NSStackView()
    private let startPauseButton = NSButton(title: "Start", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)

    private let ringingControlsStack = NSStackView()
    private let acknowledgeButton = NSButton(title: "Acknowledge", target: nil, action: nil)
    private let acknowledgeAndStartButton = NSButton(title: "Acknowledge & Start Break", target: nil, action: nil)

    private let extend1Button = NSButton(title: "+1 min", target: nil, action: nil)
    private let extend5Button = NSButton(title: "+5 min", target: nil, action: nil)

    private let heatmapSection = NSStackView()
    private let heatmapView = HeatmapView()

    private let skipPhaseButton = NSButton(title: "Skip Work", target: nil, action: nil)
    private let muteButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    // Settings view elements
    private let settingsWorkValueLabel = NSTextField(labelWithString: "25 min")
    private let settingsWorkStepper = NSStepper()
    private let settingsBreakValueLabel = NSTextField(labelWithString: "5 min")
    private let settingsBreakStepper = NSStepper()
    private let settingsCyclesValueLabel = NSTextField(labelWithString: "4")
    private let settingsCyclesStepper = NSStepper()
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let settingsMuteCheckbox = NSButton(checkboxWithTitle: "Mute alarm sound", target: nil, action: nil)
    private let settingsLaunchAtLoginCheckbox = NSButton(checkboxWithTitle: "Autostart at login", target: nil, action: nil)
    private let settingsAutoStartNextCheckbox = NSButton(checkboxWithTitle: "Auto-start next after Acknowledge", target: nil, action: nil)
    private let settingsShowHeatmapCheckbox = NSButton(checkboxWithTitle: "Show activity heatmap", target: nil, action: nil)
    private let resetCycleProgressButton = NSButton(title: "Reset Cycle", target: nil, action: nil)
    private let resetWorkedTodayButton = NSButton(title: "Reset Today", target: nil, action: nil)
    private let resetDefaultsButton = NSButton(title: "Defaults", target: nil, action: nil)
    private let settingsQuitButton = NSButton(title: "Quit MyPomodoro", target: nil, action: nil)
    private let doneSettingsButton = NSButton(title: "Done", target: nil, action: nil)
    private var autoStartNextEnabled = false
    private var lastMuteIconState: Bool?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 249))
        self.view = root

        setupTimerContainer()
        setupSettingsContainer()

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 292)
        ])

        applyPageVisibility()
    }

    private func setupTimerContainer() {
        timerContainer.orientation = .vertical
        timerContainer.alignment = .centerX
        timerContainer.spacing = 10
        timerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Header row (Phase + Cycle on left, Today's worked minutes on right)
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        phaseLabel.font = .systemFont(ofSize: 12, weight: .bold)
        workedTodayLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        workedTodayLabel.textColor = .secondaryLabelColor
        workedTodayLabel.alignment = .right
        workedTodayLabel.toolTip = "Minutes worked today"

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        headerRow.addArrangedSubview(phaseLabel)
        headerRow.addArrangedSubview(headerSpacer)
        headerRow.addArrangedSubview(workedTodayLabel)

        timerContainer.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true

        // Countdown display
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        countdownLabel.alignment = .center
        timerContainer.addArrangedSubview(countdownLabel)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        timerContainer.addArrangedSubview(statusLabel)

        // Normal Controls (Start/Pause + Reset)
        normalControlsStack.orientation = .horizontal
        normalControlsStack.spacing = 8
        normalControlsStack.distribution = .fillEqually

        startPauseButton.bezelStyle = .rounded
        startPauseButton.controlSize = .large
        startPauseButton.keyEquivalent = "\r"
        startPauseButton.target = self
        startPauseButton.action = #selector(handleStartPause)

        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .large
        resetButton.target = self
        resetButton.action = #selector(handleReset)

        normalControlsStack.addArrangedSubview(startPauseButton)
        normalControlsStack.addArrangedSubview(resetButton)
        timerContainer.addArrangedSubview(normalControlsStack)
        normalControlsStack.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true

        // Ringing Controls
        ringingControlsStack.orientation = .vertical
        ringingControlsStack.spacing = 6
        ringingControlsStack.alignment = .centerX

        acknowledgeButton.bezelStyle = .rounded
        acknowledgeButton.controlSize = .large
        acknowledgeButton.keyEquivalent = "\r"
        acknowledgeButton.contentTintColor = .systemRed
        acknowledgeButton.target = self
        acknowledgeButton.action = #selector(handleAcknowledge)

        acknowledgeAndStartButton.bezelStyle = .rounded
        acknowledgeAndStartButton.controlSize = .regular
        acknowledgeAndStartButton.target = self
        acknowledgeAndStartButton.action = #selector(handleAcknowledgeAndStart)

        ringingControlsStack.addArrangedSubview(acknowledgeButton)
        ringingControlsStack.addArrangedSubview(acknowledgeAndStartButton)
        acknowledgeButton.widthAnchor.constraint(equalTo: ringingControlsStack.widthAnchor).isActive = true
        acknowledgeAndStartButton.widthAnchor.constraint(equalTo: ringingControlsStack.widthAnchor).isActive = true

        timerContainer.addArrangedSubview(ringingControlsStack)
        ringingControlsStack.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true
        ringingControlsStack.isHidden = true

        // Current cycle extension row (+1 min / +5 min)
        addSeparator(to: timerContainer)

        let extendRow = NSStackView()
        extendRow.orientation = .horizontal
        extendRow.spacing = 6
        extendRow.alignment = .centerY

        let extendLabel = NSTextField(labelWithString: "This cycle")
        extendLabel.font = .systemFont(ofSize: 12, weight: .medium)
        extendLabel.textColor = .secondaryLabelColor

        let extendSpacer = NSView()
        extendSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        extend1Button.bezelStyle = .rounded
        extend1Button.controlSize = .small
        extend1Button.toolTip = "Add 1 minute to the current cycle only"
        extend1Button.target = self
        extend1Button.action = #selector(handleExtend1)

        extend5Button.bezelStyle = .rounded
        extend5Button.controlSize = .small
        extend5Button.toolTip = "Add 5 minutes to the current cycle only"
        extend5Button.target = self
        extend5Button.action = #selector(handleExtend5)

        extendRow.addArrangedSubview(extendLabel)
        extendRow.addArrangedSubview(extendSpacer)
        extendRow.addArrangedSubview(extend1Button)
        extendRow.addArrangedSubview(extend5Button)

        timerContainer.addArrangedSubview(extendRow)
        extendRow.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true

        // Optional GitHub-style activity heatmap
        heatmapSection.orientation = .vertical
        heatmapSection.alignment = .centerX
        heatmapSection.spacing = 8
        addSeparator(to: heatmapSection)
        heatmapSection.addArrangedSubview(heatmapView)
        heatmapView.widthAnchor.constraint(equalTo: heatmapSection.widthAnchor).isActive = true
        timerContainer.addArrangedSubview(heatmapSection)
        heatmapSection.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true
        heatmapSection.isHidden = true

        // Footer bar
        addSeparator(to: timerContainer)

        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.spacing = 6
        footerRow.alignment = .centerY

        skipPhaseButton.bezelStyle = .rounded
        skipPhaseButton.controlSize = .small
        skipPhaseButton.target = self
        skipPhaseButton.action = #selector(handleSkipPhase)

        muteButton.bezelStyle = .rounded
        muteButton.controlSize = .small
        muteButton.imagePosition = .imageOnly
        muteButton.target = self
        muteButton.action = #selector(handleToggleMute)

        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.imagePosition = .imageOnly
        let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        gearImage?.isTemplate = true
        settingsButton.image = gearImage
        settingsButton.toolTip = "Settings"
        settingsButton.target = self
        settingsButton.action = #selector(handleOpenSettings)

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(handleQuit)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        footerRow.addArrangedSubview(skipPhaseButton)
        footerRow.addArrangedSubview(footerSpacer)
        footerRow.addArrangedSubview(muteButton)
        footerRow.addArrangedSubview(settingsButton)
        footerRow.addArrangedSubview(quitButton)

        timerContainer.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: timerContainer.widthAnchor).isActive = true
    }

    private func setupSettingsContainer() {
        settingsContainer.orientation = .vertical
        settingsContainer.alignment = .leading
        settingsContainer.spacing = 10
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false

        // Settings header
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY

        let titleLabel = NSTextField(labelWithString: "Settings")
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)

        doneSettingsButton.bezelStyle = .rounded
        doneSettingsButton.controlSize = .small
        doneSettingsButton.target = self
        doneSettingsButton.action = #selector(handleCloseSettings)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        headerRow.addArrangedSubview(titleLabel)
        headerRow.addArrangedSubview(spacer)
        headerRow.addArrangedSubview(doneSettingsButton)

        settingsContainer.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true
        addSeparator(to: settingsContainer)

        // Work length stepper
        configureStepper(
            settingsWorkStepper,
            min: Double(PomodoroTimer.minMinutes),
            max: Double(PomodoroTimer.maxMinutes),
            action: #selector(handleWorkStepperChanged)
        )
        let workRow = makeStepperRow(
            label: "Work cycle",
            valueLabel: settingsWorkValueLabel,
            stepper: settingsWorkStepper
        )
        settingsContainer.addArrangedSubview(workRow)
        workRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true

        // Break length stepper
        configureStepper(
            settingsBreakStepper,
            min: Double(PomodoroTimer.minMinutes),
            max: Double(PomodoroTimer.maxMinutes),
            action: #selector(handleBreakStepperChanged)
        )
        let breakRow = makeStepperRow(
            label: "Break cycle",
            valueLabel: settingsBreakValueLabel,
            stepper: settingsBreakStepper
        )
        settingsContainer.addArrangedSubview(breakRow)
        breakRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true

        // Number of cycles stepper
        configureStepper(
            settingsCyclesStepper,
            min: Double(PomodoroTimer.minCycles),
            max: Double(PomodoroTimer.maxCycles),
            action: #selector(handleCyclesStepperChanged)
        )
        let cyclesRow = makeStepperRow(
            label: "Cycles",
            valueLabel: settingsCyclesValueLabel,
            stepper: settingsCyclesStepper
        )
        settingsContainer.addArrangedSubview(cyclesRow)
        cyclesRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true

        addSeparator(to: settingsContainer)

        // Sound picker row
        let soundRow = NSStackView()
        soundRow.orientation = .horizontal
        soundRow.alignment = .centerY

        let soundLabel = NSTextField(labelWithString: "Alarm sound")
        soundLabel.font = .systemFont(ofSize: 12)

        soundPopup.controlSize = .small
        soundPopup.font = .systemFont(ofSize: 12)
        soundPopup.addItems(withTitles: AlarmPlayer.availableSounds)
        soundPopup.target = self
        soundPopup.action = #selector(handleSoundChanged)

        let soundSpacer = NSView()
        soundSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        soundRow.addArrangedSubview(soundLabel)
        soundRow.addArrangedSubview(soundSpacer)
        soundRow.addArrangedSubview(soundPopup)

        settingsContainer.addArrangedSubview(soundRow)
        soundRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true

        // Mute, Autostart at login, and Auto-start next checkboxes
        settingsMuteCheckbox.controlSize = .regular
        settingsMuteCheckbox.font = .systemFont(ofSize: 12)
        settingsMuteCheckbox.target = self
        settingsMuteCheckbox.action = #selector(handleToggleMute)
        settingsContainer.addArrangedSubview(settingsMuteCheckbox)

        settingsLaunchAtLoginCheckbox.controlSize = .regular
        settingsLaunchAtLoginCheckbox.font = .systemFont(ofSize: 12)
        settingsLaunchAtLoginCheckbox.target = self
        settingsLaunchAtLoginCheckbox.action = #selector(handleToggleLaunchAtLogin)
        settingsContainer.addArrangedSubview(settingsLaunchAtLoginCheckbox)

        settingsAutoStartNextCheckbox.controlSize = .regular
        settingsAutoStartNextCheckbox.font = .systemFont(ofSize: 12)
        settingsAutoStartNextCheckbox.target = self
        settingsAutoStartNextCheckbox.action = #selector(handleToggleAutoStartNext)
        settingsContainer.addArrangedSubview(settingsAutoStartNextCheckbox)

        settingsShowHeatmapCheckbox.controlSize = .regular
        settingsShowHeatmapCheckbox.font = .systemFont(ofSize: 12)
        settingsShowHeatmapCheckbox.target = self
        settingsShowHeatmapCheckbox.action = #selector(handleToggleShowHeatmap)
        settingsContainer.addArrangedSubview(settingsShowHeatmapCheckbox)

        addSeparator(to: settingsContainer)

        // Reset actions row
        let actionsRow = NSStackView()
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 6
        actionsRow.distribution = .fillEqually

        resetCycleProgressButton.bezelStyle = .rounded
        resetCycleProgressButton.controlSize = .small
        resetCycleProgressButton.toolTip = "Reset progress back to Cycle 1"
        resetCycleProgressButton.target = self
        resetCycleProgressButton.action = #selector(handleResetCycleProgress)

        resetWorkedTodayButton.bezelStyle = .rounded
        resetWorkedTodayButton.controlSize = .small
        resetWorkedTodayButton.toolTip = "Reset today's worked minutes counter"
        resetWorkedTodayButton.target = self
        resetWorkedTodayButton.action = #selector(handleResetWorkedToday)

        resetDefaultsButton.bezelStyle = .rounded
        resetDefaultsButton.controlSize = .small
        resetDefaultsButton.toolTip = "Reset Work/Break/Cycles to 25 / 5 / 4"
        resetDefaultsButton.target = self
        resetDefaultsButton.action = #selector(handleResetDefaults)

        actionsRow.addArrangedSubview(resetCycleProgressButton)
        actionsRow.addArrangedSubview(resetWorkedTodayButton)
        actionsRow.addArrangedSubview(resetDefaultsButton)

        settingsContainer.addArrangedSubview(actionsRow)
        actionsRow.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true

        settingsQuitButton.bezelStyle = .rounded
        settingsQuitButton.controlSize = .small
        settingsQuitButton.target = self
        settingsQuitButton.action = #selector(handleQuit)
        settingsContainer.addArrangedSubview(settingsQuitButton)
        settingsQuitButton.widthAnchor.constraint(equalTo: settingsContainer.widthAnchor).isActive = true
    }

    private func configureStepper(_ stepper: NSStepper, min: Double, max: Double, action: Selector) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = action
    }

    private func makeStepperRow(label: String, valueLabel: NSTextField, stepper: NSStepper) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 12)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(title)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(stepper)
        return row
    }

    func showTimerPage() {
        showingSettings = false
        applyPageVisibility()
    }

    private func applyPageVisibility() {
        guard isViewLoaded else { return }
        let active = showingSettings ? settingsContainer : timerContainer
        let inactive = showingSettings ? timerContainer : settingsContainer

        inactive.removeFromSuperview()
        if active.superview !== view {
            view.addSubview(active)
            NSLayoutConstraint.activate([
                active.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
                active.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
                active.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
                active.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
            ])
        }
        updatePreferredSize()
    }

    private func updatePreferredSize() {
        guard isViewLoaded else { return }
        let active = showingSettings ? settingsContainer : timerContainer
        active.layoutSubtreeIfNeeded()
        let contentHeight = active.fittingSize.height
        let size = NSSize(width: 292, height: ceil(contentHeight + 28))
        if size.height > 28 {
            preferredContentSize = size
            onPreferredSizeChanged?(size)
        }
    }

    func updateCountdownOnly(timer: PomodoroTimer) {
        guard isViewLoaded else { return }
        countdownLabel.stringValue = timer.formattedRemainingTime
        let workedText = "Today: \(timer.workedMinutesToday) min"
        if workedTodayLabel.stringValue != workedText {
            workedTodayLabel.stringValue = workedText
            if !heatmapSection.isHidden {
                heatmapView.update(grid: timer.heatmapGrid(weeks: HeatmapView.weeksCount))
            }
        }
    }

    func update(
        timer: PomodoroTimer,
        selectedSound: String,
        isMuted: Bool,
        launchAtLogin: Bool,
        autoStartNext: Bool,
        showHeatmap: Bool
    ) {
        if !isViewLoaded {
            _ = self.view
        }

        autoStartNextEnabled = autoStartNext

        let cycleText = "Cycle \(timer.currentCycleNumber)/\(timer.targetCycles)"
        countdownLabel.stringValue = timer.formattedRemainingTime
        workedTodayLabel.stringValue = "Today: \(timer.workedMinutesToday) min"

        // Update Settings controls
        settingsWorkValueLabel.stringValue = "\(timer.workMinutes) min"
        settingsWorkStepper.integerValue = timer.workMinutes
        settingsBreakValueLabel.stringValue = "\(timer.breakMinutes) min"
        settingsBreakStepper.integerValue = timer.breakMinutes
        settingsCyclesValueLabel.stringValue = "\(timer.targetCycles)"
        settingsCyclesStepper.integerValue = timer.targetCycles
        settingsMuteCheckbox.state = isMuted ? .on : .off
        settingsLaunchAtLoginCheckbox.state = launchAtLogin ? .on : .off
        settingsAutoStartNextCheckbox.state = autoStartNext ? .on : .off
        settingsShowHeatmapCheckbox.state = showHeatmap ? .on : .off

        let wasHeatmapHidden = heatmapSection.isHidden
        heatmapSection.isHidden = !showHeatmap
        if showHeatmap {
            heatmapView.update(grid: timer.heatmapGrid(weeks: HeatmapView.weeksCount))
        }

        if soundPopup.titleOfSelectedItem != selectedSound {
            soundPopup.selectItem(withTitle: selectedSound)
        }

        if lastMuteIconState != isMuted {
            let speakerName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            let speakerImage = NSImage(systemSymbolName: speakerName, accessibilityDescription: isMuted ? "Unmute" : "Mute")
            speakerImage?.isTemplate = true
            muteButton.image = speakerImage
            muteButton.contentTintColor = isMuted ? .systemRed : nil
            muteButton.toolTip = isMuted ? "Sound muted — click to unmute" : "Mute alarm sound"
            lastMuteIconState = isMuted
        }

        let wasRingingHidden = ringingControlsStack.isHidden

        switch timer.status {
        case .idle:
            phaseLabel.stringValue = "\(timer.phase.displayName.uppercased()) • \(cycleText)"
            phaseLabel.textColor = timer.phase == .work ? .systemGreen : .systemTeal
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = isMuted ? "Ready (Muted)" : "Ready"
            statusLabel.textColor = .secondaryLabelColor
            startPauseButton.title = "Start"
            resetButton.isEnabled = timer.remainingSeconds != timer.configuredMinutesForCurrentPhase * 60
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .running:
            phaseLabel.stringValue = "\(timer.phase.displayName.uppercased()) • \(cycleText)"
            phaseLabel.textColor = timer.phase == .work ? .systemGreen : .systemTeal
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = isMuted ? "Running (Muted)" : "Running"
            statusLabel.textColor = .secondaryLabelColor
            startPauseButton.title = "Pause"
            resetButton.isEnabled = true
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .paused:
            phaseLabel.stringValue = "\(timer.phase.displayName.uppercased()) • \(cycleText)"
            phaseLabel.textColor = .systemOrange
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = "Paused"
            statusLabel.textColor = .systemOrange
            startPauseButton.title = "Resume"
            resetButton.isEnabled = true
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .ringing:
            phaseLabel.stringValue = "\(timer.phase.displayName.uppercased()) DONE • \(cycleText)"
            phaseLabel.textColor = .systemRed
            countdownLabel.textColor = .systemRed
            statusLabel.stringValue = isMuted ? "Time's up (Muted) — acknowledge" : "Time's up — acknowledge to silence"
            statusLabel.textColor = .systemRed
            if autoStartNext {
                acknowledgeButton.title = "Acknowledge & Start \(timer.phase.next.displayName)"
                acknowledgeAndStartButton.title = "Acknowledge Only"
            } else {
                acknowledgeButton.title = "Acknowledge"
                acknowledgeAndStartButton.title = "Acknowledge & Start \(timer.phase.next.displayName)"
            }
            normalControlsStack.isHidden = true
            ringingControlsStack.isHidden = false
        }

        let isRinging = timer.status == .ringing
        skipPhaseButton.title = "Skip \(timer.phase.displayName)"
        skipPhaseButton.toolTip = "Skip current \(timer.phase.displayName) cycle"
        extend1Button.isEnabled = !isRinging
        extend5Button.isEnabled = !isRinging
        resetDefaultsButton.isEnabled = !isRinging
        resetCycleProgressButton.isEnabled = !isRinging
        settingsWorkStepper.isEnabled = !isRinging
        settingsBreakStepper.isEnabled = !isRinging

        if wasRingingHidden != ringingControlsStack.isHidden || wasHeatmapHidden != heatmapSection.isHidden {
            updatePreferredSize()
        }
    }

    private func addSeparator(to stack: NSStackView) {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @objc private func handleStartPause() {
        onStartPause?()
    }

    @objc private func handleReset() {
        onReset?()
    }

    @objc private func handleAcknowledge() {
        onAcknowledge?(autoStartNextEnabled)
    }

    @objc private func handleAcknowledgeAndStart() {
        onAcknowledge?(!autoStartNextEnabled)
    }

    @objc private func handleSkipPhase() {
        onSkipPhase?()
    }

    @objc private func handleExtend1() {
        onExtendCurrentCycle?(1)
    }

    @objc private func handleExtend5() {
        onExtendCurrentCycle?(5)
    }

    @objc private func handleResetDefaults() {
        onResetDefaults?()
    }

    @objc private func handleResetWorkedToday() {
        onResetWorkedToday?()
    }

    @objc private func handleResetCycleProgress() {
        onResetCycleProgress?()
    }

    @objc private func handleWorkStepperChanged() {
        onSetWorkMinutes?(settingsWorkStepper.integerValue)
    }

    @objc private func handleBreakStepperChanged() {
        onSetBreakMinutes?(settingsBreakStepper.integerValue)
    }

    @objc private func handleCyclesStepperChanged() {
        onSetTargetCycles?(settingsCyclesStepper.integerValue)
    }

    @objc private func handleSoundChanged() {
        if let title = soundPopup.titleOfSelectedItem {
            onSelectSound?(title)
        }
    }

    @objc private func handleToggleMute() {
        onToggleMute?()
    }

    @objc private func handleToggleLaunchAtLogin() {
        onToggleLaunchAtLogin?()
    }

    @objc private func handleToggleAutoStartNext() {
        onToggleAutoStartNext?()
    }

    @objc private func handleToggleShowHeatmap() {
        onToggleShowHeatmap?()
    }

    @objc private func handleOpenSettings() {
        showingSettings = true
        applyPageVisibility()
    }

    @objc private func handleCloseSettings() {
        showingSettings = false
        applyPageVisibility()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}

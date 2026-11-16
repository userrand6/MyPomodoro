import AppKit
import PomodoroCore

@MainActor
final class PopoverViewController: NSViewController {
    var onStartPause: (() -> Void)?
    var onReset: (() -> Void)?
    var onAcknowledge: ((_ autoStartNext: Bool) -> Void)?
    var onSwitchPhase: (() -> Void)?
    var onAdjustMinutes: ((_ delta: Int, _ phase: PomodoroPhase) -> Void)?
    var onResetDefaults: (() -> Void)?
    var onSelectSound: ((_ soundName: String) -> Void)?
    var onQuit: (() -> Void)?

    private let phaseLabel = NSTextField(labelWithString: "WORK")
    private let sessionsLabel = NSTextField(labelWithString: "Sessions: 0")
    private let countdownLabel = NSTextField(labelWithString: "25:00")
    private let statusLabel = NSTextField(labelWithString: "Ready")

    private let normalControlsStack = NSStackView()
    private let startPauseButton = NSButton(title: "Start", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)

    private let ringingControlsStack = NSStackView()
    private let acknowledgeButton = NSButton(title: "Acknowledge", target: nil, action: nil)
    private let acknowledgeAndStartButton = NSButton(title: "Acknowledge & Start Break", target: nil, action: nil)

    private let workDurationLabel = NSTextField(labelWithString: "25 min")
    private let breakDurationLabel = NSTextField(labelWithString: "5 min")

    private var workAdjustButtons: [NSButton] = []
    private var breakAdjustButtons: [NSButton] = []

    private let switchPhaseButton = NSButton(title: "Switch to Break", target: nil, action: nil)
    private let resetDefaultsButton = NSButton(title: "25 / 5", target: nil, action: nil)
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 290))
        self.view = root

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            root.widthAnchor.constraint(equalToConstant: 280)
        ])

        // 1. Header row (Phase + Sessions)
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        phaseLabel.font = .systemFont(ofSize: 12, weight: .bold)
        sessionsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sessionsLabel.textColor = .secondaryLabelColor
        sessionsLabel.alignment = .right

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        headerRow.addArrangedSubview(phaseLabel)
        headerRow.addArrangedSubview(headerSpacer)
        headerRow.addArrangedSubview(sessionsLabel)

        mainStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 2. Countdown display
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        countdownLabel.alignment = .center
        mainStack.addArrangedSubview(countdownLabel)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        mainStack.addArrangedSubview(statusLabel)

        // 3a. Normal Controls (Start/Pause + Reset)
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
        mainStack.addArrangedSubview(normalControlsStack)
        normalControlsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 3b. Ringing Controls (Acknowledge + Acknowledge & Start Next)
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

        mainStack.addArrangedSubview(ringingControlsStack)
        ringingControlsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        ringingControlsStack.isHidden = true

        // 4. Duration adjustment section
        mainStack.addArrangedSubview(makeSeparator(widthAnchor: mainStack.widthAnchor))

        let workRow = makeDurationRow(
            title: "Work",
            valueLabel: workDurationLabel,
            phase: .work,
            storeButtonsIn: &workAdjustButtons
        )
        let breakRow = makeDurationRow(
            title: "Break",
            valueLabel: breakDurationLabel,
            phase: .breakTime,
            storeButtonsIn: &breakAdjustButtons
        )

        mainStack.addArrangedSubview(workRow)
        workRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(breakRow)
        breakRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 5. Utility & Footer section
        mainStack.addArrangedSubview(makeSeparator(widthAnchor: mainStack.widthAnchor))

        let switchRow = NSStackView()
        switchRow.orientation = .horizontal
        switchRow.spacing = 6

        switchPhaseButton.bezelStyle = .rounded
        switchPhaseButton.controlSize = .small
        switchPhaseButton.target = self
        switchPhaseButton.action = #selector(handleSwitchPhase)

        resetDefaultsButton.bezelStyle = .rounded
        resetDefaultsButton.controlSize = .small
        resetDefaultsButton.toolTip = "Reset Work/Break defaults to 25 / 5 min"
        resetDefaultsButton.target = self
        resetDefaultsButton.action = #selector(handleResetDefaults)

        let switchSpacer = NSView()
        switchSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        switchRow.addArrangedSubview(switchPhaseButton)
        switchRow.addArrangedSubview(switchSpacer)
        switchRow.addArrangedSubview(resetDefaultsButton)

        mainStack.addArrangedSubview(switchRow)
        switchRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.spacing = 6

        let soundLabel = NSTextField(labelWithString: "Sound:")
        soundLabel.font = .systemFont(ofSize: 11)
        soundLabel.textColor = .secondaryLabelColor

        soundPopup.controlSize = .small
        soundPopup.font = .systemFont(ofSize: 11)
        soundPopup.addItems(withTitles: AlarmPlayer.availableSounds)
        soundPopup.target = self
        soundPopup.action = #selector(handleSoundChanged)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(handleQuit)

        footerRow.addArrangedSubview(soundLabel)
        footerRow.addArrangedSubview(soundPopup)
        footerRow.addArrangedSubview(footerSpacer)
        footerRow.addArrangedSubview(quitButton)

        mainStack.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    func update(timer: PomodoroTimer, selectedSound: String) {
        if !isViewLoaded {
            _ = self.view
        }

        countdownLabel.stringValue = timer.formattedRemainingTime
        sessionsLabel.stringValue = "Sessions: \(timer.completedWorkSessions)"
        workDurationLabel.stringValue = "\(timer.workMinutes) min"
        breakDurationLabel.stringValue = "\(timer.breakMinutes) min"

        if soundPopup.titleOfSelectedItem != selectedSound {
            soundPopup.selectItem(withTitle: selectedSound)
        }

        switch timer.status {
        case .idle:
            phaseLabel.stringValue = timer.phase.displayName.uppercased()
            phaseLabel.textColor = timer.phase == .work ? .systemRed : .systemTeal
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = "Ready"
            statusLabel.textColor = .secondaryLabelColor
            startPauseButton.title = "Start"
            resetButton.isEnabled = false
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .running:
            phaseLabel.stringValue = timer.phase.displayName.uppercased()
            phaseLabel.textColor = timer.phase == .work ? .systemRed : .systemTeal
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = "Running"
            statusLabel.textColor = .secondaryLabelColor
            startPauseButton.title = "Pause"
            resetButton.isEnabled = true
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .paused:
            phaseLabel.stringValue = timer.phase.displayName.uppercased()
            phaseLabel.textColor = .systemOrange
            countdownLabel.textColor = .labelColor
            statusLabel.stringValue = "Paused"
            statusLabel.textColor = .systemOrange
            startPauseButton.title = "Resume"
            resetButton.isEnabled = true
            normalControlsStack.isHidden = false
            ringingControlsStack.isHidden = true
        case .ringing:
            phaseLabel.stringValue = "\(timer.phase.displayName.uppercased()) COMPLETE"
            phaseLabel.textColor = .systemRed
            countdownLabel.textColor = .systemRed
            statusLabel.stringValue = "Time's up — acknowledge to silence"
            statusLabel.textColor = .systemRed
            acknowledgeAndStartButton.title = "Acknowledge & Start \(timer.phase.next.displayName)"
            normalControlsStack.isHidden = true
            ringingControlsStack.isHidden = false
        }

        let isRinging = timer.status == .ringing
        switchPhaseButton.title = "Switch to \(timer.phase.next.displayName)"
        switchPhaseButton.isEnabled = !isRinging
        resetDefaultsButton.isEnabled = !isRinging

        for button in workAdjustButtons + breakAdjustButtons {
            button.isEnabled = !isRinging
        }
    }

    private func makeDurationRow(
        title: String,
        valueLabel: NSTextField,
        phase: PomodoroPhase,
        storeButtonsIn storage: inout [NSButton]
    ) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY

        let nameLabel = NSTextField(labelWithString: title)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let minus1 = makeAdjustButton(title: "-1m", delta: -1, phase: phase)
        let plus1 = makeAdjustButton(title: "+1m", delta: 1, phase: phase)
        let plus2 = makeAdjustButton(title: "+2m", delta: 2, phase: phase)

        storage = [minus1, plus1, plus2]

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(minus1)
        row.addArrangedSubview(plus1)
        row.addArrangedSubview(plus2)

        return row
    }

    private func makeAdjustButton(title: String, delta: Int, phase: PomodoroPhase) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(handleAdjust(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.tag = (phase == .work ? 100 : 200) + delta
        let actionWord = delta > 0 ? "Add" : "Subtract"
        button.toolTip = "\(actionWord) \(abs(delta)) min for \(phase.displayName)"
        return button
    }

    private func makeSeparator(widthAnchor: NSLayoutDimension) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        return box
    }

    @objc private func handleStartPause() {
        onStartPause?()
    }

    @objc private func handleReset() {
        onReset?()
    }

    @objc private func handleAcknowledge() {
        onAcknowledge?(false)
    }

    @objc private func handleAcknowledgeAndStart() {
        onAcknowledge?(true)
    }

    @objc private func handleSwitchPhase() {
        onSwitchPhase?()
    }

    @objc private func handleResetDefaults() {
        onResetDefaults?()
    }

    @objc private func handleAdjust(_ sender: NSButton) {
        let phase: PomodoroPhase = sender.tag >= 200 ? .breakTime : .work
        let base = phase == .work ? 100 : 200
        let delta = sender.tag - base
        onAdjustMinutes?(delta, phase)
    }

    @objc private func handleSoundChanged() {
        if let title = soundPopup.titleOfSelectedItem {
            onSelectSound?(title)
        }
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}

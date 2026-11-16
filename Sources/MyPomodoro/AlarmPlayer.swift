import AppKit
import Foundation

/// Plays a repeating macOS system chime until stopped/acknowledged or until `maxRingDuration` elapses.
@MainActor
final class AlarmPlayer {
    static let availableSounds = ["Glass", "Ping", "Hero", "Submarine", "Sosumi"]
    nonisolated static let defaultMaxRingDuration: TimeInterval = 60

    var onPulse: (() -> Void)?
    var onTimeout: (() -> Void)?

    private var repeatTimer: Timer?
    private var currentSound: NSSound?
    private var cachedSoundName: String?
    private var ringStartDate: Date?
    private(set) var isRinging = false

    func start(soundName: String, maxDuration: TimeInterval = AlarmPlayer.defaultMaxRingDuration) {
        stop()
        isRinging = true
        ringStartDate = Date()
        playOnce(soundName: soundName)

        let timer = Timer(timeInterval: 1.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRinging else { return }
                if let start = self.ringStartDate, Date().timeIntervalSince(start) >= maxDuration {
                    self.stop()
                    self.onTimeout?()
                    return
                }
                self.playOnce(soundName: soundName)
                self.onPulse?()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    func stop() {
        isRinging = false
        ringStartDate = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        currentSound?.stop()
    }

    func playOnce(soundName: String) {
        if cachedSoundName != soundName || currentSound == nil {
            currentSound?.stop()
            currentSound = loadSound(named: soundName)
            cachedSoundName = soundName
        } else {
            currentSound?.stop()
        }

        if let sound = currentSound {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func loadSound(named name: String) -> NSSound? {
        if let sound = NSSound(named: NSSound.Name(name)) {
            return sound
        }
        let path = "/System/Library/Sounds/\(name).aiff"
        if FileManager.default.fileExists(atPath: path) {
            return NSSound(contentsOfFile: path, byReference: true)
        }
        return nil
    }
}

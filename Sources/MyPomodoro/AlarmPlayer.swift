import AppKit
import Foundation

/// Plays a repeating macOS system chime until stopped/acknowledged.
@MainActor
final class AlarmPlayer {
    static let availableSounds = ["Glass", "Ping", "Hero", "Submarine", "Sosumi"]

    var onPulse: (() -> Void)?

    private var repeatTimer: Timer?
    private var currentSound: NSSound?
    private(set) var isRinging = false

    func start(soundName: String) {
        stop()
        isRinging = true
        playOnce(soundName: soundName)

        let timer = Timer(timeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRinging else { return }
                self.playOnce(soundName: soundName)
                self.onPulse?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    func stop() {
        isRinging = false
        repeatTimer?.invalidate()
        repeatTimer = nil
        currentSound?.stop()
        currentSound = nil
    }

    func playOnce(soundName: String) {
        currentSound?.stop()
        if let sound = loadSound(named: soundName) {
            currentSound = sound
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

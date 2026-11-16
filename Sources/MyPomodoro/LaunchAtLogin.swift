import Foundation
import ServiceManagement

/// Manages "Autostart at Login" for both `.app` bundles (via `SMAppService.mainApp`)
/// and standalone CLI binaries (via a user LaunchAgent plist).
enum LaunchAtLogin {
    private static let launchAgentLabel = "com.mypomodoro.app"

    private static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    static var isEnabled: Bool {
        if isAppBundle {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if isAppBundle {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return isEnabled == enabled
            } catch {
                return false
            }
        }

        if enabled {
            return writeLaunchAgentPlist()
        } else {
            return removeLaunchAgentPlist()
        }
    }

    private static func writeLaunchAgentPlist() -> Bool {
        guard let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first else {
            return false
        }
        let directory = launchAgentURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": launchAgentLabel,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func removeLaunchAgentPlist() -> Bool {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path) else {
            return true
        }
        do {
            try FileManager.default.removeItem(at: launchAgentURL)
            return true
        } catch {
            return false
        }
    }
}

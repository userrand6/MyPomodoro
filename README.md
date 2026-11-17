# MyPomodoro

## Vibe coded pomodoro that is a bit more persistant in reminding you of breaks and allows to delay breaks/working ab it

.

## Features

- **Menu bar live countdown** — Shows the remaining `MM:SS` time with monospaced digits directly in the macOS menu bar while running or paused.
- **Auto-open & repeating alarm (60s cap)** — When a Work or Break timer finishes, the menu bar dropdown opens automatically and a repeating macOS system chime plays (pulsing the menu bar bell green) until you click **Acknowledge**, or stops automatically after 60 seconds if left unacknowledged.
- **Quick `+1 min` / `+5 min` & `Skip Work/Break`** — Temporarily extend the active Work or Break cycle by `+1 min` or `+5 min` without changing your saved cycle lengths, or skip straight to the next phase (`Skip Work` / `Skip Break`).
- **Cycle settings & progress** — Configure Work cycle length, Break cycle length, and number of cycles (`Cycle X/Y`, default `4`) in the built-in Settings panel.
- **Daily worked minutes & GitHub-style heatmap** — Tracks minutes worked today (`Today: X min`) and cycles with an automatic 4:00 AM daily reset (or on next wake/open), plus an optional 19-week GitHub-style activity heatmap (with hover tooltips per day) you can enable in **Settings**.
- **Mute toggle & selectable chime** — Mute/unmute the alarm sound in one click from the main popover or Settings, and choose from built-in macOS sounds (`Glass`, `Ping`, `Hero`, `Submarine`, `Sosumi`).
- **Autostart & Quit** — Toggle **Autostart at login** (`SMAppService` for `MyPomodoro.app`, or a LaunchAgent for standalone CLI binaries), optionally **Auto-start next after Acknowledge**, and quit anytime from the main popover or Settings.
- **Persistent settings** — Work/Break lengths, cycle count, mute state, auto-start preference, alarm sound, and today's worked minutes are all saved in `UserDefaults`.
- **Lightweight & native** — Built directly on `AppKit` and `Foundation` with `LSUIElement` / `.accessory` activation policy (no Electron, no web runtime, and timers only tick while running).

## Requirements

- macOS 13.0 or later
- Swift / Xcode Command Line Tools (`xcode-select --install`) if building from source

## Build & Run Locally

Build and launch the `.app` bundle:

```sh
make app
open dist/MyPomodoro.app
```

Or run the binary directly from the terminal (it runs in the menu bar without a Dock icon):

```sh
make build
.build/release/mypomodoro &
```

Run the unit tests:

```sh
swift test
```

## Adding to Your Homebrew Tap

A ready-to-use Homebrew formula template is included at `Formula/mypomodoro.rb`.

1. Tag a release on GitHub (for example `v0.1.0`):
   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```
2. Compute the SHA-256 checksum of the GitHub release tarball:
   ```sh
   curl -sL https://github.com/<your-username>/MyPomodoro/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```
3. Copy `Formula/mypomodoro.rb` into your tap repository (e.g. `homebrew-tap/Formula/mypomodoro.rb`), and update:
   - `homepage`
   - `url` (pointing to your release tarball)
   - `sha256` (from step 2)
4. Install from your tap:
   ```sh
   brew tap <your-username>/tap
   brew install mypomodoro
   ```
5. Start it from Homebrew:
   ```sh
   # Run in the background as a Homebrew service:
   brew services start mypomodoro

   # Or launch manually / link the .app bundle:
   mypomodoro &
   ln -sf "$(brew --prefix)/opt/mypomodoro/MyPomodoro.app" /Applications/MyPomodoro.app
   ```

## License

MIT — see [LICENSE](LICENSE).

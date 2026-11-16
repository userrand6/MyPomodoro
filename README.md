# MyPomodoro

A tiny, native macOS menu bar Pomodoro timer built with pure Swift and AppKit — zero external dependencies, no Dock icon, and minimal memory/CPU footprint.

## Features

- **Menu bar live countdown** — Shows the remaining `MM:SS` time with monospaced digits directly in the macOS menu bar while running or paused.
- **Repeating alarm until acknowledged** — When a Work or Break timer finishes, a repeating macOS system chime plays (and the menu bar bell pulses red) until you click **Acknowledge** (or **Acknowledge & Start Break/Work**).
- **Quick `+1m` and `+2m` buttons for both Work and Break** — Adjust Work (default `25 min`) and Break (default `5 min`) durations anytime. While a phase is running or paused, `+1m` / `+2m` on that phase immediately extends the active countdown.
- **Lightweight & native** — Built directly on `AppKit` and `Foundation` with `LSUIElement` / `.accessory` activation policy (no Electron, no web runtime, and timers only tick while running).
- **Selectable system chime** — Choose from built-in macOS sounds (`Glass`, `Ping`, `Hero`, `Submarine`, `Sosumi`); preferences are saved in `UserDefaults`.

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

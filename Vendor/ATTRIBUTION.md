# Vendored third-party source

These libraries are copied into the app target so Nino Notch can build
without Swift Package Manager (SPM hangs inside the nested macOS sandbox
used by this machine's agent). Original licenses are kept next to the
source. This does not relicense anything.

| Folder | Upstream | License |
|---|---|---|
| Defaults | sindresorhus/Defaults | MIT |
| KeyboardShortcuts | sindresorhus/KeyboardShortcuts | MIT |
| LaunchAtLogin | sindresorhus/LaunchAtLogin-Modern | MIT |
| SkyLightWindow | Lakr233/SkyLightWindow | MIT |
| AsyncXPCConnection | ChimeHQ/AsyncXPCConnection | MIT |
| MacroVisionKit | TheBoredTeam/MacroVisionKit | MIT (upstream boring.notch) |

Sparkle and Lottie are **not** vendored. Sparkle is stubbed so this fork
does not auto-update from TheBoredTeam. Lottie network loading is replaced
with a local placeholder view.

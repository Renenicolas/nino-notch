# Nino Notch

**Nino Notch** is a Nino-branded macOS notch shell. Nino is *The AI that runs your growth.*

It sits in the MacBook notch. Upstream features (music control, HUD replacement, shelf, calendar, camera) work as-is. On top, a **Nino** tab hosts plug-in modules through one protocol, so Nino Voice, AI Search and Screen Control can be wired in later by editing one file each. Today all three are placeholder stubs.

## License and credit (required)

This project is a fork of **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** by [TheBoredTeam](https://github.com/TheBoredTeam).

Upstream license: **GNU GPLv3**. `LICENSE` and `THIRD_PARTY_LICENSES` are unchanged. This fork does not relicense the work. If you ship a build you must keep GPLv3, keep the attribution, and share source.

## What this fork adds

- Nino name, bundle id `com.meetnino.notch`, gold-on-black palette, placeholder icon
- `NinoModule` protocol + registry + a switcher in the notch's Nino tab
- Four stub modules, all marked **STUB**, all off by default, no network, no secrets:
  Nino Voice, AI Search, Screen Control

To wire a real module, read [WIRE-IN.md](WIRE-IN.md).

## Screenshots (notch open, Nino tab)

| Nino Voice |
|---|
| ![Nino Voice](docs/screenshots/nino-tab-voice.png) |

| AI Search | Screen Control |
|---|---|
| ![AI Search](docs/screenshots/nino-tab-search.png) | ![Screen Control](docs/screenshots/nino-tab-screen.png) |

## Build

Requires macOS 14+ and a recent Xcode (built with Xcode 27 on macOS 26.6).

```bash
scripts/build.sh          # Release build, unsigned, into build/DerivedData
scripts/test-modules.sh   # module contract: source rules + compile + run
open build/DerivedData/Build/Products/Release/NinoNotch.app
```

Preview one module in the notch without clicking:

```bash
open build/DerivedData/Build/Products/Release/NinoNotch.app --args --nino-preview nino.search
```

## Palette

| Token | Hex | Used for |
|---|---|---|
| gold | `#d4a853` | accent, selected tab, badges |
| bg | `#050505` | notch background |
| panel | `#0a0a08` | panels, round buttons |
| text | `#e6e1d3` | primary text |
| sub | `#c2bcab` | secondary text |
| dim | `#8f8a7a` | tertiary, disabled |

Defined once in `Nino/NinoTheme.swift`. The Xcode `AccentColor` asset is gold.

## Upstream

Original project: https://github.com/TheBoredTeam/boring.notch

This fork: https://github.com/Renenicolas/nino-notch

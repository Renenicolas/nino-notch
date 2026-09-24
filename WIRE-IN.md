# Wiring a feature into Nino Notch

Nino Notch is a shell. Features are **modules**. A module is one Swift file
that conforms to `NinoModule` (`Nino/NinoModule.swift`). The notch's **Nino**
tab lists every module in a chip row and shows the selected one's panel.
You never touch the notch core to add one.

## The modules today

| Module | File | id | State |
|---|---|---|---|
| Nino Voice | `Nino/Modules/NinoVoiceModule.swift` | `nino.voice` | live |
| Ask Nino | `Nino/Modules/AskNinoModule.swift` | `nino.search` | live |
| Screen Control | `Nino/Modules/ScreenControlModule.swift` | `nino.screen` | live |

The live modules are the worked example: they read `NinoVoiceLink.shared`
(live state from the Nino Voice engine) and send it commands. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

A stub has `isStub = true`, no network, no credentials, and a
`// TODO: wire real integration here` block where the real call goes.

## Replace a stub with the real thing

1. Open the stub file. Find `// TODO: wire real integration here`.
2. Put the real call there. Keep secrets out of the app bundle and out of git.
3. Swap the placeholder views for live ones. `NinoCard` is the framed box;
   `NinoStubPanel` is the same box plus a "not wired" note.
4. Set `isStub = false` and move the file to `Nino/Modules/`. The gold
   **STUB** badge disappears and the module now defaults to **On**.
5. Add its id to `liveIDs` in `Nino/NinoModuleContract.swift`.
6. Build: `scripts/build.sh`. Check: `scripts/test-modules.sh`.
7. Preview without clicking around:
   `open build/DerivedData/Build/Products/Release/NinoNotch.app --args --nino-preview nino.screen`

## Add a brand-new module

1. Copy a file (a stub, or a live module if it needs the voice engine).
2. Set `id` (unique, never change it later), `displayName`, `summary`,
   `systemImage`, `isStub`, and `panel`.
3. Add one line to `all` in `Nino/ModuleCatalog.swift`.
4. Add the id to `expectedIDs` (and `liveIDs` if live) in
   `Nino/NinoModuleContract.swift`. The check fails on purpose until you do.
5. Build and run `scripts/test-modules.sh`.

## On / Off

Settings → **Nino modules** has a toggle per module (`NinoModuleRegistry.isEnabled(id)`).
Live modules default On, stubs Off. Nino Voice Off quits the voice engine;
Ask Nino Off keeps Right Command from opening the ask box in the notch.

## Checks

`scripts/test-modules.sh` greps the stubs for network/capture APIs and the TODO
marker, checks retired modules stay gone, then runs the contract **inside the built
app** (`--nino-module-self-test`, receipt in `/tmp/nino-module-selftest.txt`).
It ends with `ALL TESTS PASSED` or a non-zero exit.

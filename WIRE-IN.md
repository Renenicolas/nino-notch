# Wiring a real feature into Nino Notch

Nino Notch is a shell. Features are **modules**. A module is one Swift file
that conforms to `NinoModule` (`Nino/NinoModule.swift`). The notch's **Nino**
tab lists every module in a chip row and shows the selected one's panel.
You never touch the notch core to add one.

## The 4 stubs (placeholder UI only)

| Module | File | id |
|---|---|---|
| Nino Voice | `Nino/Stubs/NinoVoiceModule.swift` | `nino.voice` |
| Vellum (Nino Assistant chat) | `Nino/Stubs/VellumAssistantModule.swift` | `nino.vellum` |
| AI Search | `Nino/Stubs/AISearchModule.swift` | `nino.search` |
| Screen Control | `Nino/Stubs/ScreenControlModule.swift` | `nino.screen` |

Each file has a `// TODO: wire real integration here` block at the exact
spot where the real call goes (mic tap, send button, search submit, media
buttons). Every stub has `isStub = true`, no network, no credentials.

## Replace a stub with the real thing

1. Open the stub file. Find `// TODO: wire real integration here`.
2. Put the real call there (your Nino Voice / Vellum / search / media client).
   Keep secrets out of the app bundle and out of git.
3. Swap the placeholder views for the live ones. `NinoStubPanel` is just a
   framed box with a note; keep it or drop it.
4. Set `isStub = false`. The gold **STUB** badge disappears.
5. Build: `scripts/build.sh`. Check: `scripts/test-modules.sh`.
6. Preview without clicking around:
   `open build/DerivedData/Build/Products/Release/NinoNotch.app --args --nino-preview nino.vellum`
   then hover the notch. It opens on the Nino tab with that module selected.

## Add a brand-new module

1. Copy any stub file in `Nino/Stubs/` and rename the type.
2. Set `id` (unique, never change it later), `displayName`, `summary`,
   `systemImage`, `isStub`, and `panel`.
3. Add one line to `all` in `Nino/ModuleCatalog.swift`.
4. Add the new id to `expectedIDs` in `Nino/NinoModuleContract.swift`
   (the check fails on purpose until you do).
5. Build and run `scripts/test-modules.sh`.

## On / Off

Settings → **Nino modules** has a toggle per module. That is the module's
activation state (`NinoModuleRegistry.isEnabled(id)`); the Nino tab shows
**On** or **Off** next to the name. Default is off. The tab always lists every
module so you can see the shell; a real module should check `isEnabled`
before doing live work.

## Checks

- `scripts/test-modules.sh` greps the stubs for network/capture APIs and the
  TODO marker, compiles the contract, and **runs** it. Ends with
  `ALL TESTS PASSED` or a non-zero exit.
- `NinoNotch.app --args --nino-module-self-test` runs the same checks inside
  the real app and writes `/tmp/nino-module-selftest.txt`, then exits.

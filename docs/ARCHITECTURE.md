# Nino Notch + Nino Voice: how the one notch app works

**One screen, one engine.** Nino Notch is the only thing that draws in the notch.
Nino Voice (`~/dev/VoiceInk`, installed as `/Applications/Nino Voice.app`) is its
voice engine and runs headless: no dock icon, no menu bar icon, no notch popup.

```
 Nino Notch (com.meetnino.notch)                 Nino Voice engine (com.prakashjoshipax.VoiceInk)
 ─────────────────────────────────               ───────────────────────────────────────────────
 notch UI: Home / Shelf / Nino tabs               hotkeys (Right ⌥ talk, Right ⌘ ask, Fn, Left ⌥)
 Nino Voice tab + closed-notch indicator  ◀─state─ Parakeet / whisper.cpp / cloud speech-to-text
 Ask Nino tab (type, Return sends, Esc)   ─cmds──▶ Claude CLI polish, modes, dictionary, history
 NinoVoiceLink.swift                              paste at cursor, OpenClaw (Ask Nino)
                                                  NinoNotchBridge.swift
            └──── ~/Library/Application Support/com.meetnino.notch/voice.sock ────┘
```

## Why two processes and not one binary

- The engine is ~57k lines with SwiftData stores, whisper.cpp, FluidAudio and
  nine packages. Porting it into the notch target would be a rewrite, not a merge.
- macOS permission grants (Microphone, Accessibility, Screen Recording) belong
  to the engine's bundle id + signing certificate. Keeping the engine keeps
  every grant; moving the code would reset them all.
- The user sees one app either way: Nino Notch launches the engine, draws all of
  its UI, and quits it on exit.

## The link

- Unix socket, newline-delimited JSON. Folder `0700`, socket `0600`, peer uid
  checked. Not distributed notifications: those broadcast every transcript to
  every process, and any app could send "ask", which runs the OpenClaw agent
  with hands on this Mac.
- Engine → notch: `{"type":"state", ...}` on every change, `{"type":"meter"}`
  while recording.
- Notch → engine: `hello`, `toggleRecord`, `cancel`, `askOpen`, `askSend`,
  `askClose`, `openSettings`, `openHistory`, `openOnboarding`,
  `requestPermissions`, `quit`.
- Shapes: `NinoBridgeState` (engine) and `NinoVoiceState` (notch) must match;
  `NinoModuleContract` decodes a sample engine line to catch drift.

## Focus rules

- Dictation never takes the keyboard: the notch window cannot become key, so
  the text pastes into the app you were in.
- Ask Nino does take it: while it is open the notch window may become key,
  the notch stays open on hover-out, and Esc or the close button gives the
  keyboard back.

## Settings and first launch

- Engine settings (models, modes, dictionary, history) open from the Nino Voice
  tab. That window is the engine's own and shows only when asked for.
- Nino Notch's first-launch onboarding ends with a Nino Voice step that asks for
  the engine's microphone and Accessibility, or opens its full welcome flow.
- Escape hatch: `defaults write com.prakashjoshipax.VoiceInk NinoVoiceStandalone -bool YES`
  brings back the engine's menu bar icon. It still never draws its own notch.

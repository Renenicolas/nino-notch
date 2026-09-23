# Nino Notch + Nino Voice merge — capability checklist

Source of truth for "nothing lost". Written **before** any merge code (2026-09-23).
Every row gets an **After** location and a **Verified** result at the end.
`LIVE` = exercised in the running merged app. `CODE` = present and builds, not exercised live (reason given).
`NOT VERIFIED` = could not be checked, with the reason.

Repos:
- Nino Notch: `~/dev/nino-notch` (main)
- Nino Voice: `~/dev/VoiceInk` (branch `nino-interface-notch`, base commit `59b51e9`)

Facts found during the inventory (not assumptions):
- The Nino Voice that actually runs is `~/Downloads/VoiceInk.app` (login item, built Aug 27 from `59b51e9`,
  signed "Nino Code Signing"). `/Applications/Nino Voice.app` is an older Aug 13 build signed with a different cert.
- macOS permission grants (Microphone, Accessibility, Screen Recording) are held by bundle id
  `com.prakashjoshipax.VoiceInk` + the "Nino Code Signing" certificate. Any rebuild must keep both or the grants reset.
- **Live speech-to-text is Parakeet TDT 0.6b v3 (FluidAudio, on-device, streaming)** in all 8 modes, not whisper.cpp.
  The whisper.cpp engine is compiled in, but `WhisperModels/` is empty.
- AI enhancement uses the Local CLI provider with the template `claude -p`.
- `openclaw` lives at `/opt/homebrew/bin/openclaw` (the gateway's second candidate path).

## A. Nino Voice capabilities

| # | Capability | Before (where it lives) | After | Verified |
|---|---|---|---|---|
| V1 | Primary record key: **Right-Option**, hybrid (tap = toggle, hold = push-to-talk) | `Shortcuts/RecordingShortcutManager`, defaults `Shortcut_primaryRecording` | | |
| V2 | Ask Nino key: **Right-Command** opens the ask box | `ShortcutAction.assistantAsk` → `RecorderUIManager.toggleAssistantAsk` | | |
| V3 | Paste last enhancement: **Fn** | `Shortcut_pasteLastEnhancement` | | |
| V4 | Paste last transcription: **Left-Option** | `Shortcut_pasteLastTranscription` | | |
| V5 | Enhancement mode shortcut: **Option+Command** (mode `…0002`) | `Shortcut_mode_…0002` | | |
| V6 | Hands-free toggle and secondary record: cleared on purpose | `_cleared` flags | | |
| V7 | While the panel is up: double-Esc cancels, Option+1…0 picks a mode | `RecorderPanelShortcutManager` | | |
| V8 | Ask box: **Return sends**, Esc closes, hold Right-Option to speak into the box | `NotchRecorderView` + `shouldCaptureAssistantDictation` | | |
| V9 | Local speech-to-text in use: Parakeet (FluidAudio), live streaming | `Transcription/FluidAudio`, `Transcription/Streaming` | | |
| V10 | Local whisper.cpp engine (compiled in, no model downloaded) | `Transcription/Whisper`, `whisper.xcframework` | | |
| V11 | Other engines: Apple native speech, 13 cloud providers | `Transcription/Native`, `Transcription/Cloud` | | |
| V12 | AI enhancement through the Claude CLI (`claude -p`), plus 14 other providers | `Services/AIEnhancement/LocalCLIService`, `AIService` | | |
| V13 | Modes: 8 configured (Dictation, Enhancement, Email, Rewrite, Assistant, Prompt Architect, Chat, Answers Live) | `Modes/`, defaults `modeConfigurationsV2` | | |
| V14 | "Respond" modes (Assistant, Answers Live) show the AI answer in the notch and allow follow-ups | `VoiceInkEngine+Assistant`, `AssistantSession` | | |
| V15 | Paste at cursor (default paste method, AppleScript option) | `Paste/CursorPaster`, `ClipboardManager` | | |
| V16 | Ask Nino answered live by OpenClaw (`openclaw agent --local`, message on stdin) | `Services/NinoOpenClawGateway` via `RecorderUIManager.sendAssistantMessage` | | |
| V17 | Context: screen capture, selected text, clipboard (per mode) | `ScreenCaptureService`, `SelectedTextService` | | |
| V18 | Dictionary: vocabulary, word replacements, quick add | `Views/Dictionary`, `DictionaryService` | | |
| V19 | History window, retry last transcription, open-history shortcut | `HistoryWindowController`, `LastTranscriptionService` | | |
| V20 | Dashboard and stats (time saved, peak hours, model usage) | `Views/Dashboard`, `stats.store` | | |
| V21 | Transcribe an audio/video file (open-with, drag in) | `AudioFileTranscriptionManager` | | |
| V22 | Recording sounds, media pause/mute while recording, input device choice (C920) | `SoundManager`, `MediaController`, `AudioDeviceManager` | | |
| V23 | Per-app style memory and voice profiles | `PerAppStyleMemory`, `PerAppVoiceProfileService` | | |
| V24 | Data retention, audio cleanup, import/export backup | `TranscriptionAutoCleanupService`, `ImportExportService` | | |
| V25 | Settings and model management UI (models, providers, API keys, prompts) | `ContentView` main window | | |
| V26 | Onboarding flow (Lemon-style, intent, sectors, mic, accessibility, model setup) | `Views/Onboarding` | | |
| V27 | Permission checks: mic request, accessibility reminder, screen recording | `OnboardingPermissionModels`, `showAccessibilityReminderIfNeeded` | | |
| V28 | Toast notifications (errors, "press Esc again") at the bottom of the screen | `Notifications/NotificationManager` | | |
| V29 | Gold/black palette | `Views/Recorder/NinoPalette` (tracks `nino-os/components/studio/tokens.ts`) | | |
| V30 | Nino entitlements (persona, features, kill switch) | `Services/NinoEntitlements` | | |
| V31 | Shortcuts app actions (toggle/dismiss recorder) | `AppIntents/` | | |
| V32 | Mini recorder style (alternative floating recorder) | `Views/Recorder/Mini*` | | |
| V33 | Launch at login | login item `~/Downloads/VoiceInk.app` | | |
| V34 | Its own notch popup (the thing being retired) | `NotchWindowManager`, `NotchRecorderPanel`, `NotchRecorderView`, `NotchShape` | | |

## B. Nino Notch capabilities

| # | Capability | Before (where it lives) | After | Verified |
|---|---|---|---|---|
| N1 | Notch opens on hover and click; swipe gestures | `ContentView`, `BoringViewModel` | | |
| N2 | Music: now playing, controls, album art, closed-notch live activity (Spotify set) | `MusicManager`, `NotchHomeView` | | |
| N3 | HUD replacement for volume/brightness/backlight (off in your settings) | `MediaKeyInterceptor`, `VolumeManager`, `BrightnessManager` | | |
| N4 | Shelf: drop files, AirDrop/quick share | `components/Shelf` | | |
| N5 | Calendar and reminders panel (off in your settings) | `CalendarManager`, `BoringCalendar` | | |
| N6 | Webcam mirror (off in your settings) | `WebcamManager` | | |
| N7 | Battery indicator and charging notifications | `BatteryActivityManager` | | |
| N8 | Download progress listener | `enableDownloadListener` | | |
| N9 | Keyboard shortcuts: Cmd+Shift+I toggle notch, Cmd+Shift+H sneak peek | `ShortcutConstants` | | |
| N10 | Settings window (13 sections), menu bar icon, first-launch onboarding | `SettingsView`, `OnboardingView` | | |
| N11 | `NinoModule` plug-in system: protocol, registry, catalog, Nino tab switcher, on/off | `Nino/` | | |
| N12 | Nino Voice stub tab | `Nino/Stubs/NinoVoiceModule.swift` | | |
| N13 | AI Search stub tab | `Nino/Stubs/AISearchModule.swift` | | |
| N14 | Screen Control stub tab | `Nino/Stubs/ScreenControlModule.swift` | | |
| N15 | Vellum stub tab (to be **removed**) | `Nino/Stubs/VellumAssistantModule.swift` | | |
| N16 | `--nino-preview`, `--nino-module-self-test`, `scripts/test-modules.sh` | `Nino/` | | |
| N17 | Nino palette | `Nino/NinoTheme.swift` | | |

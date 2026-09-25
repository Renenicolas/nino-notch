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

## Result

- Architecture: Nino Notch draws everything; Nino Voice runs headless as its engine (private socket, see ARCHITECTURE.md).
- Retired: Nino Voice's notch popup, dock icon and menu bar icon. Removed: the Vellum stub.
- Not verified live (needs Rene): the physical keys other than Right ⌥ (Right ⌘, Fn, Left ⌥, Esc, Option+digits),
  and the Claude CLI polish, blocked by a one-time macOS keychain prompt.

## A. Nino Voice capabilities

| # | Capability | Before (where it lives) | After | Verified |
|---|---|---|---|---|
| V1 | Primary record key: **Right-Option**, hybrid (tap = toggle, hold = push-to-talk) | `Shortcuts/RecordingShortcutManager`, defaults `Shortcut_primaryRecording` | Engine (headless Nino Voice); key map read back live: `Right ⌥`, hybrid | LIVE — your own dictations at 5:53 and 5:54 PM went through the new headless engine (only the physical key could start them) |
| V2 | Ask Nino key: **Right-Command** opens the ask box | `ShortcutAction.assistantAsk` → `RecorderUIManager.toggleAssistantAsk` | Engine; opens Ask Nino in Nino Notch | PARTIAL — engine reports `Right ⌘`; the same `toggleAssistantAsk` path ran live via the bridge; I could not press the physical key (Terminal is denied synthetic key events) |
| V3 | Paste last enhancement: **Fn** | `Shortcut_pasteLastEnhancement` | Engine, unchanged | NOT VERIFIED live (not pressed); stored key unchanged in the settings diff |
| V4 | Paste last transcription: **Left-Option** | `Shortcut_pasteLastTranscription` | Engine, unchanged | NOT VERIFIED live (not pressed); stored key unchanged in the settings diff |
| V5 | Enhancement mode shortcut: **Option+Command** (mode `…0002`) | `Shortcut_mode_…0002` | Engine; same function also reachable as `toggleRecord` + mode | LIVE up to polish — recording started in Enhancement mode; polish blocked, see V12 |
| V6 | Hands-free toggle and secondary record: cleared on purpose | `_cleared` flags | Engine, unchanged | CODE — `_cleared` flags unchanged in the settings diff |
| V7 | While the panel is up: double-Esc cancels, Option+1…0 picks a mode | `RecorderPanelShortcutManager` | Engine, unchanged (keyed off the panel-visible flag, which is kept) | NOT VERIFIED live (keys not pressed) |
| V8 | Ask box: **Return sends**, Esc closes, hold Right-Option to speak into the box | `NotchRecorderView` + `shouldCaptureAssistantDictation` | Nino Notch Ask Nino tab: Return = onSubmit, Esc = onExitCommand, close button; voice-into-box path kept in engine | PARTIAL — send and close ran live through the bridge; typing Return/Esc and holding Right ⌥ into the box were not physically pressed |
| V9 | Local speech-to-text in use: Parakeet (FluidAudio), live streaming | `Transcription/FluidAudio`, `Transcription/Streaming` | Engine | LIVE — spoken sentence came back word for word; live words streamed into the notch |
| V10 | Local whisper.cpp engine (compiled in, no model downloaded) | `Transcription/Whisper`, `whisper.xcframework` | Engine | CODE — compiled in; no whisper model is downloaded, your modes use Parakeet |
| V11 | Other engines: Apple native speech, 13 cloud providers | `Transcription/Native`, `Transcription/Cloud` | Engine | CODE — untouched, not used by your modes |
| V12 | AI enhancement through the Claude CLI (`claude -p`), plus 14 other providers | `Services/AIEnhancement/LocalCLIService`, `AIService` | Engine | NOT VERIFIED — the polish step first reads the `PerAppStyleMemory` key from your login keychain; macOS asks for your login password once per new build and the engine waits. Needs you: enter password, **Always Allow** |
| V13 | Modes: 8 configured (Dictation, Enhancement, Email, Rewrite, Assistant, Prompt Architect, Chat, Answers Live) | `Modes/`, defaults `modeConfigurationsV2` | Engine; active mode shown in the Voice tab | LIVE — all 8 modes identical to before (field-by-field); Dictation active |
| V14 | "Respond" modes (Assistant, Answers Live) show the AI answer in the notch and allow follow-ups | `VoiceInkEngine+Assistant`, `AssistantSession` | Answers render in Nino Notch Ask Nino tab (same session state) | CODE — not run live (uses the same keychain-gated polish step as V12) |
| V15 | Paste at cursor (default paste method, AppleScript option) | `Paste/CursorPaster`, `ClipboardManager` | Engine | LIVE — dictated line landed at the cursor in TextEdit (screenshot) |
| V16 | Ask Nino answered live by OpenClaw (`openclaw agent --local`, message on stdin) | `Services/NinoOpenClawGateway` via `RecorderUIManager.sendAssistantMessage` | Engine gateway; shown in Nino Notch Ask Nino tab | LIVE — "Paris is the capital of France." (37 s) and a 5-line answer (70 s), both rendered in the notch |
| V17 | Context: screen capture, selected text, clipboard (per mode) | `ScreenCaptureService`, `SelectedTextService` | Engine, unchanged | CODE |
| V18 | Dictionary: vocabulary, word replacements, quick add | `Views/Dictionary`, `DictionaryService` | Engine, same store | DATA — dictionary was empty before and after (0 words, 0 replacements) |
| V19 | History window, retry last transcription, open-history shortcut | `HistoryWindowController`, `LastTranscriptionService` | Engine window, opened by Nino Notch's **History** button | LIVE — opened from the notch, shows your real entries |
| V20 | Dashboard and stats (time saved, peak hours, model usage) | `Views/Dashboard`, `stats.store` | Engine window, opened by Nino Notch's **Settings** button | LIVE — dashboard shows your real totals (58h 59m saved, 196.5K words) |
| V21 | Transcribe an audio/video file (open-with, drag in) | `AudioFileTranscriptionManager` | Engine, unchanged | CODE |
| V22 | Recording sounds, media pause/mute while recording, input device choice (C920) | `SoundManager`, `MediaController`, `AudioDeviceManager` | Engine, unchanged | LIVE — mute-while-recording confirmed (had to switch it off to test with `say`); fell back to the MacBook mic with the C920 unplugged |
| V23 | Per-app style memory and voice profiles | `PerAppStyleMemory`, `PerAppVoiceProfileService` | Engine, unchanged | NOT VERIFIED — same keychain prompt as V12 |
| V24 | Data retention, audio cleanup, import/export backup | `TranscriptionAutoCleanupService`, `ImportExportService` | Engine, unchanged | CODE |
| V25 | Settings and model management UI (models, providers, API keys, prompts) | `ContentView` main window | Engine main window, opened from the Voice tab **Settings** button | LIVE — window opened on request, hidden otherwise |
| V26 | Onboarding flow (Lemon-style, intent, sectors, mic, accessibility, model setup) | `Views/Onboarding` | Engine flow, launched by the new **Set up Nino Voice** step at the end of Nino Notch onboarding, or **Finish setup** in the Voice tab | CODE — you are already onboarded; not re-run |
| V27 | Permission checks: mic request, accessibility reminder, screen recording | `OnboardingPermissionModels`, `showAccessibilityReminderIfNeeded` | Engine asks (grants belong to it); Voice tab shows missing ones | LIVE — microphone and accessibility still granted after the rebuild (same certificate) |
| V28 | Toast notifications (errors, "press Esc again") at the bottom of the screen | `Notifications/NotificationManager` | Engine, unchanged (bottom of the screen, not the notch) | CODE |
| V29 | Gold/black palette | `Views/Recorder/NinoPalette` (tracks `nino-os/components/studio/tokens.ts`) | Reconciled into `Nino/NinoTheme.swift`: gold identical; your notch bg/text values kept; gold2 #eed08a, goldDim #9c7628, border added from Nino Voice. Nino Voice's own windows keep tokens.ts | DONE — see ink #070609 vs #050505 and cream #f6f3ec vs #e6e1d3 note |
| V30 | Nino entitlements (persona, features, kill switch) | `Services/NinoEntitlements` | Engine, unchanged | CODE |
| V31 | Shortcuts app actions (toggle/dismiss recorder) | `AppIntents/` | Engine, unchanged | CODE |
| V32 | Mini recorder style (alternative floating recorder) | `Views/Recorder/Mini*` | Engine, unchanged (only if you pick Mini) | CODE |
| V33 | Launch at login | login item `~/Downloads/VoiceInk.app` | Login item is now **Nino Notch**; it starts the engine and quits it on exit | LIVE — Nino Notch launch started the engine by itself |
| V34 | Its own notch popup (the thing being retired) | `NotchWindowManager`, `NotchRecorderPanel`, `NotchRecorderView`, `NotchShape` | **Retired.** Four classes deleted; engine is a background agent | LIVE — 0 on-screen engine windows while dictating; no dock icon, no menu bar icon |

## B. Nino Notch capabilities

| # | Capability | Before (where it lives) | After | Verified |
|---|---|---|---|---|
| N1 | Notch opens on hover and click; swipe gestures | `ContentView`, `BoringViewModel` | Unchanged | LIVE — hover opened the notch |
| N2 | Music: now playing, controls, album art, closed-notch live activity (Spotify set) | `MusicManager`, `NotchHomeView` | Unchanged | LIVE — Home shows Spotify now playing |
| N3 | HUD replacement for volume/brightness/backlight (off in your settings) | `MediaKeyInterceptor`, `VolumeManager`, `BrightnessManager` | Unchanged (off in your settings) | CODE |
| N4 | Shelf: drop files, AirDrop/quick share | `components/Shelf` | Unchanged | CODE — tab present, drop not exercised |
| N5 | Calendar and reminders panel (off in your settings) | `CalendarManager`, `BoringCalendar` | Unchanged (off in your settings) | CODE |
| N6 | Webcam mirror (off in your settings) | `WebcamManager` | Unchanged (off in your settings) | CODE |
| N7 | Battery indicator and charging notifications | `BatteryActivityManager` | Unchanged | LIVE — battery shows in every screenshot |
| N8 | Download progress listener | `enableDownloadListener` | Unchanged | CODE |
| N9 | Keyboard shortcuts: Cmd+Shift+I toggle notch, Cmd+Shift+H sneak peek | `ShortcutConstants` | Unchanged | CODE |
| N10 | Settings window (13 sections), menu bar icon, first-launch onboarding | `SettingsView`, `OnboardingView` | Plus a Nino Voice onboarding step and the Nino modules pane | CODE |
| N11 | `NinoModule` plug-in system: protocol, registry, catalog, Nino tab switcher, on/off | `Nino/` | Unchanged pattern; live modules default On | LIVE — 19/19 contract checks inside the built app |
| N12 | Nino Voice stub tab | `Nino/Stubs/NinoVoiceModule.swift` | `Nino/Modules/NinoVoiceModule.swift`, live | LIVE — screenshot while listening |
| N13 | AI Search stub tab | `Nino/Stubs/AISearchModule.swift` | `Nino/Modules/AskNinoModule.swift` ("Ask Nino"), live, id kept | LIVE — screenshots with real answers |
| N14 | Screen Control tab | `Nino/Stubs/ScreenControlModule.swift` | **Live** since 2026-09-24: `Nino/Modules/ScreenControlModule.swift` + `Nino/NinoScreenControl.swift` (see section D) | see D2–D4 |
| N15 | Vellum stub tab (to be **removed**) | `Nino/Stubs/VellumAssistantModule.swift` | **Removed** (file, catalog line, screenshot, docs) | LIVE — contract rejects the old id; no Vellum left in app or docs |
| N16 | `--nino-preview`, `--nino-module-self-test`, `scripts/test-modules.sh` | `Nino/` | `test-modules.sh` now runs the contract inside the built app | LIVE |
| N17 | Nino palette | `Nino/NinoTheme.swift` | Extended, see V29 | DONE |

## C. Data & Settings Migration

Nothing had to be copied. The engine keeps its bundle id (`com.prakashjoshipax.VoiceInk`) and signing identity,
so it opens the very same stores and preferences it always did. Checked against a snapshot taken before any change.

| # | Data | Where it lives | After | Verified |
|---|---|---|---|---|
| D1 | Transcript history (the copy-it-yourself log) | `~/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store` (SwiftData/SQLite) + `Recordings/` | Same store, read by the engine; opened from Nino Notch's **History** button; last line also in the Voice tab | LIVE — 1,703 transcripts (Aug 28 → today) before the tests; History window and dashboard show them |
| D2 | All settings: key map, modes, models, Claude CLI template, toggles | UserDefaults domain `com.prakashjoshipax.VoiceInk` (44 keys) | Same domain, untouched | LIVE — no key added or removed; only changes: the last-used mic id (C920 unplugged) and a byte-order re-save of the 8 modes (identical field by field). Engine reports Dictation · Parakeet V3 · Right ⌥ · Right ⌘ · Fn; `localCLICommandTemplate = claude -p` |
| D3 | Stats and dictionary | `stats.store`, `dictionary-local.store` | Same stores | LIVE — 1,674 stats sessions; dictionary was already empty |
| D4 | macOS permissions (mic, accessibility, screen) | TCC, keyed to bundle id + "Nino Code Signing" cert | Same identity | LIVE — engine reports mic and accessibility granted |
| D5 | Per-app style memory (encrypted) | `PerAppStyleMemory.enc`, key in the login keychain | Same file and key | NOT VERIFIED — needs the one-time keychain approval (V12) |
| D6 | Nino Notch's own settings | UserDefaults `com.meetnino.notch` | Untouched; new Nino module toggles added | LIVE — Spotify controller, shortcuts kept |

Side effect of testing: about 8 test dictations were added to your history (two are blank, from the
keychain-blocked polish runs). Delete them in History if you like.

## D. Added 2026-09-24: launch fix, signing, Jev, Screen Control, one-press Right ⌘

| # | Capability | Where it lives | Verified |
|---|---|---|---|
| L1 | Double-click always shows Nino Notch | `Nino/NinoSingleInstance.swift`, `applicationShouldHandleReopen` | LIVE — root cause: every copy shares `com.meetnino.notch`, so macOS only re-activated the copy already running, and a windowless app showed nothing. Installed `~/Applications/NinoNotch.app`: a Finder-style open launches it cold; a second open flashes the notch for 3 s |
| L2 | Only one copy ever runs | `NinoSingleInstance.retireOlderCopies()` | LIVE — launching a second copy retired the first; the voice engine came back by itself |
| G1 | Own signing identity for Nino Notch | "Nino Notch Signing" in `~/Library/Keychains/nino-notch-signing.keychain-db`; password only in the login keychain (`com.meetnino.notch.signing-keychain` / `nino-notch-signing`); `scripts/build.sh` reads it at build time | LIVE — locked, unlocked with the read-back password, signed; DR pinned to the certificate root; untrusted cert works, no trust prompt. `nino-signing.keychain-db` and Nino Voice's identity untouched |
| D1 | Jev (TypeSafe) intent decision | `TypeSafeJev` in `Nino/NinoScreenControl.swift` | NOT VERIFIED live — TypeSafe signups closed ("Whoops, we're full"), no key. Decision rule checked offline in the contract |
| D2 | Claude CLI fallback (`claude -p --model haiku`, no tools, empty working folder) | `ClaudeCommandParser` | LIVE — parsed "open Spotify and play my Liked Songs" into open_app + play_liked_songs |
| D3 | Actions: open app, Liked Songs, play/pause/next/previous, volume, mute, web links | `NinoScreenControl.run`, `SpotifyControl`, `AXPress` | LIVE — Spotify went from paused to playing **Liked Songs** (947 songs) from the command; Spotify 1.3 needs `play` after loading the collection |
| D4 | Spoken command → Screen Control, spoken question → Ask Nino, no Return | `NinoVoiceLink.routeSpokenDraft` | LIVE — spoken "Open Spotify and play my like songs" ran Screen Control and Liked Songs played. Speaker-to-mic tests with music playing in the room misheard words ("light songs"), which then correctly went to Ask Nino instead |
| R1 | One-press Right ⌘: press opens Ask Nino and listens; press again stops and sends; 2-minute cap only | `NinoVoiceLink.startListeningIfHotkey`, `watchRightCommand`, `AskListenSession` | PARTIAL — the engine's Right ⌘ call (`askOpen`) made Nino Notch start listening at once and keep listening through silence; the stop it sends on the second press works. The physical key presses could not be made from this terminal (no permission to post key events) |
| A1 | Ask Nino answers in the notch | engine → OpenClaw → Ask Nino tab | LIVE — "It's about 11:23 PM in Beirut right now." (12 s) |
| A2 | OpenClaw Slack permission file on reno-mac | `~/.openclaw/nino-permissions.json` (restored byte-for-byte from reno-mini, 0600) | LIVE — never existed on reno-mac (machine-local, missed in the move); its absence only printed a warning that Ask Nino's error display showed in place of the real error |

## E. Added 2026-09-24 (evening): clear Right ⌘, instant commands, fast answers

| # | Capability | Where it lives | Verified |
|---|---|---|---|
| R2 | Right ⌘ stages (physical presses LIVE, see note below): press 1 → "Listening…" + live words; press 2 → stops, sends, stays open on "Thinking…", then "Done: …" or the answer; press 3 or Esc closes; auto-close 4 s after a computer command | `NinoVoiceLink` (stage, second press acts on key RELEASE + 0.4 s), `AskNinoPanel.stageRow` | LIVE — voice "Pause the music": Listening with live words → "Done" → closed on its own 4.4 s later (screenshots `docs/screenshots/ask-*.png`). Root cause of the old close: Nino Voice fires Ask on key release; if the recording had already finished it read the press as "close" |
| F1 | Instant computer commands, no AI: play, pause, next/skip, previous/back, volume up/down ("turn it up"), mute, open [installed app], play my Liked Songs, and "and"-combinations | `QuickCommand` in `Nino/NinoScreenControl.swift` | LIVE — see timings; 17 phrasing checks in the contract, incl. "a half-heard 'play my' is not guessed" |
| F2 | Unusual commands → Claude CLI on Haiku (was Haiku before too), now started without hooks/plugins/MCP/skills/tools/session | `ClaudeCommandParser` | LIVE — "bump the volume up a little" |
| Q1 | Time in a city answered on the Mac (time-zone database) | `QuickAnswer.timeAnswer` | LIVE — Beirut |
| Q2 | Short questions → Haiku, streamed (first words appear as they arrive), web search allowed; real tasks → full Nino agent | `QuickAnswer.route`, `streamFast` | LIVE — "who wrote the novel Dune?" |
| Q3 | Nothing new runs in the background | every model call is a one-off process | CODE + measured: only Nino Notch and Nino Voice stay running |
| P1 | Old Nino Voice signing password (reno-mini search, Aug 27 command) | — | NOT FOUND — reno-mini has no Aug 27 creation command; only Sep 2 lines (for reno-mini's own keychain), not used |

**Timings (measured through the installed app, 2026-09-24):**

| Request | Before | After | Path after |
|---|---|---|---|
| "pause the music" | 8.6–10.5 s (Claude/Haiku parse) | **0.11–0.21 s** | instant rules |
| "open Spotify and play my Liked Songs" | 7.5–9.4 s parse, then ~2.5 s Spotify | **2.56 s** (all Spotify) | instant rules |
| "bump the volume up a little" (unusual) | 7.5–8.1 s | **6.98 s** | Haiku, lean start |
| "what time is it in Beirut" | 12 s best, 37–70 s typical, 180 s+ worst | **0.04 s** | on the Mac |
| "who wrote the novel Dune?" | full agent (12–70 s) | **first words 2.5 s, done 3.3 s** | Haiku, streamed |

**Right ⌘ physical-press fix (2026-09-24, debugged live with timestamped logs):** two bugs, both in Nino Notch.
1. While Ask Nino is open the notch window is key, so the second press is delivered to Nino Notch itself, and a
   *global* key monitor never sees its own app's events. Added a local monitor next to the global one.
2. Right after `toggleRecord` Nino Voice can send one more "idle" update before "starting"; Nino Notch read it as
   "recording ended" and switched listening off 0.1 s after starting it. Now it only ends when a recording that
   had started stops.
Result: physical Right ⌘ → speak → Right ⌘ stopped and sent in 2 of 2 rounds with Rene (one question routed to
the full agent, "What time is it in Beirut?" answered instantly). Temporary logging removed.

## F. Added 2026-09-24 (night): stay on your app, play a specific song

| # | Capability | Where it lives | Verified |
|---|---|---|---|
| S1 | "open X" starts the app in the background; "switch to / show / bring up X" brings it forward; if anything else still jumps in front, the app Rene was in is put back | `AppTarget.open(inFront:)`, `NinoScreenControl.handle` | LIVE — "open Calculator": 0.17 s, front app (Aside) unchanged |
| S2 | "play <song / artist / album / playlist>" on Spotify, in the background | `QuickCommand` → `play_song`, `SpotifyLookup` (Haiku + web search finds the open.spotify.com link), `SpotifyControl.play(search:)` | LIVE — "play Blinding Lights by The Weeknd" → Blinding Lights playing, front app unchanged, 16.9 s (almost all of it the web lookup) |
| S3 | Spotify's own search (free "Nino Notch" developer app; Client ID/Secret only in the login keychain `com.meetnino.notch.spotify`; token kept in memory) with the web lookup as fallback; artists play their top song in the artist's context; playback must still be on 1.5 s later | `SpotifyWebSearch`, `SpotifyControl.play(search:)` | LIVE — "play Blinding Lights" 16.9 s → 1.4 s lookup (2.8 s incl. the hold check), "put on Drake" 2.9 s; both still playing 5 s later; front app unchanged |
| S4 | Rene's rule: nothing comes to the front unless his words ask ("switch to", "show", "bring up", "pull up", "take me to", "go to", "focus on", "in front", "on screen"). Enforced in code even if the rules or the AI pick focus_app; links open in the background; the front app is put back if anything steals it | `NinoScreenControl.asksForFocus`, `handle(_:)` | LIVE — "open Calculator" and "play Blinding Lights" left Terminal in front; "show Calculator" brought it forward; contract checks pass |


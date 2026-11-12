# Voice Type 🎙️

An iPhone app for **typing by voice** in any app (WhatsApp, Mail, Notes…).
It transcribes your speech with the Google **Gemini API**: adds punctuation, removes "um"s and "uh"s, and never changes the meaning.

There are two ways to use it; pick whichever is handier at the moment:

| Route | How | Result |
|---|---|---|
| **Keyboard** | Switch to the Voice Type keyboard → speak → tap the mic | Text is **typed at the cursor** |
| **Back Tap** | Double-tap the back of the phone → speak → tap | Text is **copied to the clipboard** → paste |

---

## Setup on a Mac

Requirements: Xcode 16 or later, an Apple Developer account, an iPhone on iOS 17 or later.

```bash
git clone https://github.com/denizardaslan/ios-speech-to-text.git
cd ios-speech-to-text
./scripts/bootstrap.sh ABCDE12345     # your Team ID (Xcode › Settings › Accounts)
```

The script installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), generates `SesliYaz.xcodeproj` from `project.yml`, and opens it in Xcode.
> The `.xcodeproj` is not checked in. Run `xcodegen generate` again whenever `project.yml` or the file layout changes.

In Xcode:
1. Pick the **SesliYaz** scheme and your iPhone as the destination, then run with ▶︎.
2. If you get a signing error, set **Signing & Capabilities › Team** on both targets (*SesliYaz*, *SesliYazKeyboard*).
   The App Group (`group.com.denizardaslan.sesliyaz`) is created automatically by automatic signing.
3. To use a different bundle ID, change `BUNDLE_ID_PREFIX` in `project.yml`. The App Group follows it.

> The internal target, bundle ID, URL scheme and App Group still use the original name `SesliYaz` / `sesliyaz`. The name shown to users is `APP_DISPLAY_NAME` in `project.yml`.

## First run on the phone

1. **API key:** Open the app. Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), paste it, and tap "Save and Validate". You only need to do this once.
2. **Keyboard:** Settings › General › Keyboard › Keyboards › Add New Keyboard › *Voice Type* → tap it → **Allow Full Access**.
3. **Back Tap:**
   - In the Shortcuts app, create a new shortcut:
     1. **Record Audio** (Start Recording: *Immediately*, Finish Recording: *On Tap*)
     2. **Voice Type › Transcribe Audio** (Audio: *Recorded Audio*)
     3. *(optional)* **Show Notification** → *Transcribed Text*
   - Settings › Accessibility › Touch › **Back Tap** › Double Tap › this shortcut.

These steps are also explained in the app's **Setup** section.

---

## Architecture

```
┌────────────────────────────── iPhone ──────────────────────────────┐
│                                                                    │
│  Double back tap ─► Shortcut: [Record Audio] ─► [Transcribe Audio]─┐│
│                                                  (App Intent)      ││
│  ┌──────────────── SesliYaz (main app) ─────────────────────┐      ││
│  │ DictationController  ← session, recording, delivery      │◄─────┘│
│  │ AudioRecorder        ← AVAudioEngine → 16 kHz mono WAV   │       │
│  │ GeminiTranscriber    ← REST: interactions/generateContent│──────►│── HTTPS ─► Gemini API
│  │ AppSettings/Keychain ← API key, model, style             │       │
│  └──────────▲─────────────────────────────┬─────────────────┘       │
│   Darwin    │ start/stop/cancel/ping      │ state.json / result.json │
│ notifications                             ▼ (App Group folder)       │
│  ┌──────────┴─────── SesliYazKeyboard (keyboard extension) ┐        │
│  │ 🎤 → send command   ·   insertText() when result arrives │        │
│  └──────────────────────────────────────────────────────────┘        │
└────────────────────────────────────────────────────────────────────┘
```

### Why doesn't the keyboard record by itself?
Apple **does not allow** keyboard extensions to use the microphone. So:

1. As soon as you switch to the Voice Type keyboard (or tap the mic), it asks the app to record. If the app's microphone is off, the keyboard opens the app via `sesliyaz://session?record=1`.
2. The app turns on the microphone (`UIBackgroundModes: audio`) and **starts recording right away**. iOS has no way for an app to send you back to the previous app, so the screen asks you to **swipe right along the bar at the bottom**. You can talk the whole time; tap the mic on the keyboard when you are done.
3. The app sends the audio to Gemini and writes the result to the App Group folder. The keyboard types it at the cursor with `textDocumentProxy.insertText`. **Undo** removes it again; **Retry** resends the audio if the request failed.
4. What happens next depends on **Settings › Keep Microphone On**:
   - *Off after each dictation* (default): the microphone turns off the moment you stop. No indicator lingers, but the next dictation opens the app again.
   - *1 minute … 1 hour / Until I turn it off*: the microphone stays ready, and the keyboard starts recording instantly through Darwin notifications, without leaving your app.

While the microphone is on, iOS shows its **microphone indicator** (Dynamic Island or the orange dot). No app can hide it. Audio is only written to a file and sent between start and stop; nothing else is stored anywhere.

Tip: the **Start Keyboard Session** shortcut action (bind it to the Action Button) turns the microphone on before you start typing.

### Why does Back Tap copy to the clipboard?
iOS does not let an app type directly into another app's text field. Only a keyboard can do that.

### Transcription
- Default model: `gemini-3.5-transcribe`, a dedicated speech-to-text model on the Interactions API (`POST /v1beta/interactions`). Style maps to `transcription_config.mode` ("Clean" = `smart`, "Verbatim" = default) and language to `language_codes`.
- Other Gemini models can be picked in Settings; they use `generateContent` with a system prompt.

### Files

```
project.yml                       XcodeGen project definition (targets, permissions, Info.plist)
Shared/                           Code shared by the app and the keyboard
  AppConfig.swift                 App Group, URL scheme
  IPC.swift                       Darwin notifications (cross-process signals)
  SharedStore.swift               JSON state/result files in the App Group
  Theme.swift                     Colors and the mic orb, shared by both UIs
App/
  SesliYazApp.swift               Entry point, handles sesliyaz://session
  Audio/AudioRecorder.swift       AVAudioEngine recording + file converter
  Services/DictationController    Session/recording/transcription state machine
  Services/GeminiTranscriber      Gemini REST client + prompt
  Services/AppSettings, Keychain  Settings and API key
  Intents/Intents.swift           Shortcut actions (App Intents)
  Views/                          SwiftUI screens
Keyboard/
  KeyboardViewController.swift    Keyboard ↔ app communication, text insertion
  KeyboardView.swift              Keyboard UI (SwiftUI)
```

## Privacy
- The API key is stored only in the device **Keychain**.
- Audio goes **directly** to Google; there is no server in between.
- ⚠️ On Gemini's **free tier**, Google may use submitted content to improve its products. For sensitive content, consider the paid tier (a project with billing enabled).
- The keyboard never records keystrokes. "Full Access" is only needed to talk to the app.

## Known limitations / roadmap
- [ ] On-device (offline) model option (WhisperKit / Apple SpeechAnalyzer)
- [ ] Custom vocabulary (names, terms) → `custom_vocabulary` for the Transcribe model
- [ ] Tone options ("formal email", "short message")
- [ ] Live preview while recording (streaming)
- There is no automatic return to the app you were typing in: iOS offers no API for it, and since iOS 26.4 the private workarounds are closed. Other dictation keyboards (Wispr Flow, Superwhisper) ask you to swipe back too.
- The way the keyboard opens the app (responder chain) is not an official Apple API. Fine for personal use, but it may cause trouble in App Store review.

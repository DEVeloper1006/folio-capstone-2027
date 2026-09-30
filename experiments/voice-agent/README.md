# voice-agent

**Status: Active (scaffold)**

A native macOS 26 menu-bar app that controls your Mac by voice. It's a Jarvis-style agent inspired by the Jev demo.

The split of responsibilities:
- **Jev** (TypeSafe's System One decision model, `typesafe/jev-1.13` on OpenRouter's Decisions API) makes fast, typed routing decisions. It is not a chat model.
- **Code** does all execution, through the Accessibility (AX) APIs.
- **Claude** handles open-ended chat.

## What it does

```
mic ─▶ SFSpeechRecognizer (streaming, on-device when available)
      ─▶ AXTreeCrawler: focused app → ≤50 actionable elements, indexed 0…49
      ─▶ Jev  POST /api/alpha/decisions   (one pass: intent / target_index / text_payload / key / app)
           ├─ OPEN_APP CLICK TYPE_TEXT PRESS_KEY SCROLL_* VOLUME_* BRIGHTNESS_* … ─▶ ActionExecutor
           ├─ TASK ─▶ TaskRunner loop   (AX crawl → Jev picks verb + element index → execute → repeat)
           ├─ CHAT ─▶ Claude via /chat/completions ─▶ ElevenLabs TTS
           └─ WAIT / DONE / BLOCKED ─▶ pill feedback
      ─▶ spoken confirmation ("Opened YouTube", "Volume up", "Done") via ElevenLabs,
         falling back to AVSpeechSynthesizer
```

The request `state` is the transcript plus the serialized element table. `questions` is a map of typed questions (the shape was checked with a live call):

```json
{
  "model": "typesafe/jev-1.13",
  "state": "User said: \"click submit\"\n\nCurrent screen:\nApp: Chrome\n[4] AXButton \"Submit\" id=submit-btn actions=AXPress",
  "questions": {
    "intent":       {"type": "choice", "instructions": "…", "criteria": {"OPEN_APP": "…", "CLICK": "…", "TASK": "…", "CHAT": "…"}},
    "target_index": {"type": "choice", "instructions": "…", "criteria": {"4": "button 'Submit'"}}
  }
}
→ {"answers": {"intent": {"type": "choice", "choice": "CLICK", "confidence": 0.97, "probabilities": {…}}, …}}
```

**Jev never generates text.** It returns `choice` keys with a confidence, and `noul` probabilities, over sets that code defines:
- `IntentOption`: `OPEN_APP CLICK TYPE_TEXT PRESS_KEY SCROLL_UP SCROLL_DOWN TASK CHAT WAIT DONE BLOCKED`, plus `VOLUME_UP VOLUME_DOWN TOGGLE_MUTE TOGGLE_DND BRIGHTNESS_UP BRIGHTNESS_DOWN`
- `KeyChord`: a fixed list of keys and shortcuts
- `AppCatalog`: apps installed in `/Applications`
- `ElementTable`: indices `0…49`, one per actionable AX element observed on the current step
- `TextPayload`: phrases cut out of the user's own words by code (quoted spans, the text after "type", "write", "that says" and so on, and the whole utterance)

Every click or type target is an `AXUIElement` the app actually observed. Every typed string is a verbatim span of the transcript. The model never emits selectors, coordinates, scripts or shell commands.

A single action whose `intent` confidence is below 0.45, or whose payload doesn't validate (an unknown index, an app that isn't installed, text outside the candidates), escalates to the task loop.

### Layout

| Path | Role |
|---|---|
| `VoiceAgent/App/` | `MenuBarExtra` dropdown, floating `OverlayPill` (`NSPanel`), `ConversationPanel`, `SettingsView`. All use Liquid Glass (`GlassEffectContainer`, `glassEffectID` morphs, `.glass` / `.glassProminent`). |
| `VoiceAgent/Voice/` | Streaming STT (`AsyncThrowingStream`), `ElevenLabsTTS` (streaming PCM through ElevenLabsKit, with an `AVSpeechSynthesizer` fallback), and the `VoiceSession` state machine. |
| `VoiceAgent/Brain/` | `JevClient` (Decisions API) and `LLMClient` (chat) actors, `IntentRouter` with `ActionIntent`, `TextPayload`, `ConversationManager`. |
| `VoiceAgent/Accessibility/` | `AXTreeCrawler` (breadth-first search of the focused window, capped at 50 actionable elements) and `ElementTable`. |
| `VoiceAgent/Actions/` | One handler per verb, plus `ActionExecutor` and the registries. |
| `VoiceAgent/Agent/TaskRunner.swift` | Multi-step loop. It stops on DONE or BLOCKED, `goal_met` ≥ 0.9, the step cap, 3 identical steps in a row, or Esc. |
| `VoiceAgent/Utilities/` | Permissions, a fixed-template AppleScript bridge, config (env → `.env` → Keychain), and the Carbon global hotkey. |
| `eval_router.py`, `configs/router_eval.yaml` | Router accuracy and latency eval. |

## How to run

Requirements: macOS 26 or later, Apple Silicon, Xcode 26 or later.

1. **API keys.** Create `experiments/voice-agent/.env`:
   ```bash
   OPENROUTER_API_KEY=<your OpenRouter key>
   ELEVENLABS_API_KEY=<your ElevenLabs key>
   ```
   The app (in dev builds) and `eval_router.py` both read this file. It's gitignored.

   Each key is looked up in this order: the environment variable, then `experiments/voice-agent/.env`, then the Keychain. An OpenRouter key pasted in **Settings → OpenRouter → Add…** goes to the Keychain.

   **The ElevenLabs key is optional.** Without it, or if a request fails before any audio plays, speech falls back to `AVSpeechSynthesizer`. The key needs only text-to-speech access; `voices_read` isn't required.
2. **Build and run:**
   ```bash
   open experiments/voice-agent/VoiceAgent.xcodeproj   # ⌘R
   # or headless:
   xcodebuild -project experiments/voice-agent/VoiceAgent.xcodeproj -scheme VoiceAgent \
     -destination 'platform=macOS,arch=arm64' build
   ```
3. **Permissions.** The app asks on first launch:
   - **Accessibility**: System Settings → Privacy & Security → Accessibility → enable Voice Agent.
   - **Microphone** and **Speech Recognition**.

   Ad-hoc signed debug builds get a new code signature on every rebuild. If AX control stops working, remove Voice Agent from the Accessibility list and add it again.
4. **Use it:**
   - Press **⌥Space** anywhere and speak. It stops listening automatically after about 1.4 s of silence. Press ⌥Space again to cancel.
   - Press **Esc** while an action or task is running to abort it.
   - Clicking the pill also toggles listening. The menu bar icon opens the glass dropdown, which links to Conversation and Settings.

The app is not sandboxed, because AX control and CGEvent posting need that. It uses the hardened runtime with the `audio-input` and `apple-events` entitlements.

### Driving the pipeline without the mic (Debug builds)
`-Utterance "<text>"` feeds text into the same pipeline as the conversation panel. Debug builds print each state change and which TTS engine was used to stdout:
```bash
~/Library/Developer/Xcode/DerivedData/VoiceAgent-*/Build/Products/Debug/VoiceAgent.app/Contents/MacOS/VoiceAgent \
  -Utterance "open youtube"
```

### Pill state preview (Debug builds)
To hold the pill in one state for a visual check, launch with the `-PillState` argument. It also skips the permission prompts.
```bash
open -n ~/Library/Developer/Xcode/DerivedData/VoiceAgent-*/Build/Products/Debug/VoiceAgent.app \
  --args -PillState listening   # idle | listening | thinking | executing | speaking | done | error
```
You can also add it under Scheme → Run → Arguments.

### Voices
Choose one under **Settings → Voice**. Preview plays a sample. The model is `eleven_turbo_v2_5`, the lowest-latency one.

| Voice | ElevenLabs voice_id | Character |
|---|---|---|
| Rachel (default) | `21m00Tcm4TlvDq8ikWAM` | Calm, warm female |
| Drew | `29vD33N1CtxCmqQRPOHJ` | Confident male |
| Clyde | `2EiwWnXFnvU5JabPnv8n` | Deep, authoritative male |
| Bella | `EXAVITQu4vr4xnSDxMaL` | Soft, friendly female |
| Charlie | `IKne3meq5aSn9XLyUdCD` | Casual male |
| System Default | none | `AVSpeechSynthesizer`, with a system-voice picker |

### Opening apps and websites
`OPEN_APP` resolves the name Jev picks in this order:
1. A bundle-ID map (for example "chrome" → `com.google.Chrome`).
2. Apps found in `/Applications`, `/System/Applications` and `~/Applications`.
3. A website map, opened in your default browser: YouTube, Gmail, X/Twitter, Reddit, Spotify, Slack, Notion, GitHub, Netflix, ChatGPT, Claude.

If nothing matches, it says "I couldn't find *name* as an app or website".

### Do Not Disturb
macOS has no public API that sets Focus. `TOGGLE_DND` runs a Shortcut named exactly **Toggle Focus**. Create it once in Shortcuts with a **Set Focus** action set to toggle Do Not Disturb. If that Shortcut doesn't exist, the pill says so.

### Accessibility
Clicking, typing, key presses, scrolling, tasks and brightness need Accessibility. Debug rebuilds change the code signature, which silently invalidates the grant. The app doesn't re-open the system prompt; instead the pill shows **"Re-grant Accessibility in System Settings"**. To fix it, remove Voice Agent from Privacy & Security → Accessibility, add it again, and relaunch. Volume and mute still work without Accessibility, through AppleScript.

### Manual smoke test
| Say | Expect |
|---|---|
| "open Safari" | The pill goes listening → thinking → executing → "Opened Safari", which is also spoken |
| "open YouTube" | youtube.com opens in the default browser, and "Opened YouTube" is spoken |
| "turn the volume down" | Volume drops by one step, and "Volume down" is spoken |
| "make the screen dimmer" | Brightness drops one step (needs Accessibility) |
| In Notes: "create a new note that says hello" | Task loop: ⌘N or a click, then TYPE_TEXT "hello", then DONE |
| "what's 17 times 23" | The conversation panel shows the reply, which is also spoken |

### Router eval
```bash
python experiments/voice-agent/eval_router.py \
  --config experiments/voice-agent/configs/router_eval.yaml
```
It prints per-question accuracy and p50/p95 latency, and writes `results/voice-agent/router_eval_<timestamp>.json`. It reads the key from `experiments/voice-agent/.env` (or the environment). Without a key it exits with code 2.

## Metrics to expect

| Metric | Target | Measured |
|---|---|---|
| Jev latency p50 / p95 | ~250 ms p50 | 258 / 448 ms |
| Intent accuracy (17 options) | ≥ 95% | 97.7% (43/44) |
| Key / app-or-website accuracy | ≥ 90% | 100% (5/5) / 100% (9/9) |
| Target-index accuracy (fixture screens) | ≥ 90% | 100% (6/6) |
| Text-payload accuracy | ≥ 90% | 100% (2/2) |

Measured 2026-09-30 with `typesafe/jev-1.13-20260917`. The run is in `results/voice-agent/router_eval_20260930-145823.json`. The sample is small: 44 cases, some of them on fixture screens.

ElevenLabs time to first audio byte on `eleven_turbo_v2_5`, measured 2026-09-30: 0.25–0.5 s.

## Known gaps

- **Do Not Disturb depends on a Shortcut you create yourself** (see above).
- **Brightness media keys haven't been verified.** They need Accessibility, which the test build didn't have. They may not affect external displays.
- **What has been run end to end** (through the DEBUG `-Utterance` driver, without the mic): chat with ElevenLabs speech, opening a website, volume through the AppleScript fallback, the Accessibility gate, and the missing-Shortcut message. The live mic path, clicking and typing in real apps, and the task loop haven't been run yet.
- **Criteria are duplicated.** They exist in Swift and in `configs/router_eval.yaml`, and the text-candidate logic exists in both `TextPayload.swift` and `eval_router.py`. All of it must be kept in sync by hand.
- **Latency has a long tail.** About 1 call in 7 takes 1.3–1.8 s. The client times out at 3 s and retries once.
- **The "Show floating status pill" setting only applies at the next launch.**
- **The crawler only reads the focused window.** Menus, sheets opened in other windows, and web content deeper than depth 25 may be missed.

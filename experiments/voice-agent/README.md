# voice-agent

**Status: Active (scaffold)**

A native macOS 26 menu-bar app that controls your Mac by voice. It's a Jarvis-style agent inspired by the Jev demo.

The split of responsibilities:
- **Jev** (TypeSafe's System One model, called through OpenRouter) makes fast, typed routing decisions.
- **Code** does all execution, through the Accessibility (AX) APIs.
- **Claude** handles open-ended chat.

## What it does

```
mic ─▶ SFSpeechRecognizer (streaming, on-device when available)
      ─▶ Jev  POST /api/v1/systemone   (one parallel call: mode / action / key / app)
           ├─ action ─▶ ActionExecutor           (open app, shortcut, scroll, volume)
           ├─ task   ─▶ TaskRunner loop          (AX crawl → Jev picks verb + element id → execute → repeat)
           └─ chat   ─▶ Claude via OpenRouter ─▶ AVSpeechSynthesizer
```

**Jev never generates text.** It returns `choice` keys and `noul` probabilities over sets that code defines:
- `ActionKind`: `OPEN_APP CLICK TYPE_TEXT PRESS_KEY SCROLL_UP SCROLL_DOWN WAIT DONE BLOCKED`, plus the system actions
- `KeyChord`: a fixed list of keys and shortcuts
- `AppCatalog`: apps installed in `/Applications`
- `ElementTable`: element IDs `e0…e49`, one per actionable AX element observed on the current step

Every click or type target is an `AXUIElement` the app actually observed. The model never emits selectors, coordinates, scripts or shell commands.

The only free text anywhere in the pipeline is the string for `TYPE_TEXT`. It is extracted from the user's own words, first with a regex (`type "…"`) and otherwise with a small Claude call (`LLMClient.extractTextToType`).

### Layout

| Path | Role |
|---|---|
| `VoiceAgent/App/` | `MenuBarExtra` dropdown, floating `OverlayPill` (`NSPanel`), `ConversationPanel`, `SettingsView`. All use Liquid Glass (`GlassEffectContainer`, `glassEffectID` morphs, `.glass` / `.glassProminent`). |
| `VoiceAgent/Voice/` | Streaming STT (`AsyncThrowingStream`), async TTS, and the `VoiceSession` state machine. |
| `VoiceAgent/Brain/` | `JevClient` and `LLMClient` actors, `IntentRouter`, `ConversationManager`. |
| `VoiceAgent/Accessibility/` | `AXTreeCrawler` (breadth-first search of the focused window, capped at 50 actionable elements) and `ElementTable`. |
| `VoiceAgent/Actions/` | One handler per verb, plus `ActionExecutor` and the registries. |
| `VoiceAgent/Agent/TaskRunner.swift` | Multi-step loop. It stops on DONE or BLOCKED, `goal_met` ≥ 0.9, the step cap, 3 identical steps in a row, or Esc. |
| `VoiceAgent/Utilities/` | Permissions, a fixed-template AppleScript bridge, config (env → `.env` → Keychain), and the Carbon global hotkey. |
| `eval_router.py`, `configs/router_eval.yaml` | Router accuracy and latency eval. |

## How to run

Requirements: macOS 26 or later, Apple Silicon, Xcode 26 or later.

1. **API key.** Choose one:
   - Paste the key in **Settings → OpenRouter → Add…**. It's stored in the Keychain.
   - `cp .env.example ~/.config/voice-agent/.env` and fill in the key.
   - Set the `OPENROUTER_API_KEY` environment variable in the scheme.
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

### Manual smoke test
| Say | Expect |
|---|---|
| "open Safari" | The pill goes listening → thinking → executing → "Opened Safari" |
| "turn the volume down" | Volume drops by one step |
| In Notes: "create a new note that says hello" | Task loop: ⌘N or a click, then TYPE_TEXT "hello", then DONE |
| "what's 17 times 23" | The conversation panel shows the reply, which is also spoken |

### Router eval
```bash
OPENROUTER_API_KEY=... python experiments/voice-agent/eval_router.py \
  --config experiments/voice-agent/configs/router_eval.yaml
```
It prints per-question accuracy and p50/p95 latency, and writes `results/voice-agent/router_eval_<timestamp>.json`. Without a key it exits with code 2.

## Metrics to expect

| Metric | Target | Measured |
|---|---|---|
| Jev latency p50 | ~250 ms (the demo's claim) | not yet run |
| Mode accuracy (action / task / chat) | ≥ 95% | not yet run |
| Single-action accuracy | ≥ 90% | not yet run |
| App resolution accuracy | ≥ 90% | not yet run |

## Known gaps

- **Do Not Disturb and brightness have no public API.** `TOGGLE_DND` throws `unsupported`. The planned route is a fixed-name Shortcut run through `shortcuts run`.
- **The task loop has only been checked by compiling it.** It hasn't been run end to end against real apps yet.
- **Criteria are duplicated.** They exist in Swift and in `configs/router_eval.yaml`, and must be kept in sync by hand.
- **The "Show floating status pill" setting only applies at the next launch.**
- **The crawler only reads the focused window.** Menus, sheets opened in other windows, and web content deeper than depth 25 may be missed.

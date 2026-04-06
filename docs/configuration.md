# Configuration

All settings live in `settings.json` — project-local (`.mirroir-mcp/settings.json`) or global (`~/.mirroir-mcp/settings.json`). Project-local settings override global ones.

```json
{
  "screenDescriberMode": "auto",
  "agent": "embacle",
  "visionImageWidth": 500,
  "ocrBackend": "auto",
  "keystrokeDelayUs": 20000,
  "clickHoldUs": 100000
}
```

Every setting has a corresponding environment variable (e.g. `MIRROIR_SCREEN_DESCRIBER_MODE`, `MIRROIR_KEYSTROKE_DELAY_US`). Resolution order: project-local `settings.json` → global `settings.json` → environment variable → built-in default.

## Screen Intelligence

| Setting | Default | Description |
|---------|---------|-------------|
| `screenDescriberMode` | `"auto"` | `"auto"` uses vision when embacle FFI is linked, OCR otherwise. `"vision"` forces AI vision, `"ocr"` forces local OCR + YOLO |
| `agent` | `""` | AI agent name for vision mode and diagnosis (e.g. `"embacle"`, `"embacle:claude"`) |
| `agentTransport` | `"auto"` | Agent transport: `"auto"` uses embedded Rust FFI if linked, HTTP otherwise. `"http"` forces HTTP |
| `visionImageWidth` | `500` | Target image width in pixels for vision API calls (screenshots are resized before sending) |
| `ocrBackend` | `"auto"` | OCR backend: `"auto"`, `"vision"` (text only), `"yolo"` (icons only), or `"both"` |
| `ocrRecognitionLevel` | `"accurate"` | Apple Vision OCR quality: `"accurate"` or `"fast"` |
| `ocrLanguageCorrection` | `true` | Enable language correction during OCR text recognition |
| `ocrLanguages` | `["en-US"]` | BCP-47 language codes for `VNRecognizeTextRequest.recognitionLanguages`. Add languages to recognise non-Latin scripts (e.g. `["ja-JP","en-US"]`). Also configurable via `MIRROIR_OCR_LANGUAGES` env var (comma-separated) |
| `yoloModelURL` | `""` | URL to download a YOLO `.mlmodel` on first use |
| `yoloModelPath` | `""` | Local path to a pre-compiled `.mlmodelc` directory (overrides download) |
| `yoloConfidenceThreshold` | `0.3` | Minimum confidence for YOLO element detections (0.0–1.0) |

## Input Timing

| Setting | Default | Description |
|---------|---------|-------------|
| `keystrokeDelayUs` | `15000` | Delay between keystrokes in microseconds |
| `clickHoldUs` | `80000` | Click hold duration in microseconds |
| `doubleTapHoldUs` | `40000` | Hold duration per tap in a double-tap gesture (microseconds) |
| `doubleTapGapUs` | `50000` | Gap between taps in a double-tap (microseconds) |
| `dragModeHoldUs` | `150000` | Initial hold before drag movement for iOS drag recognition (microseconds) |
| `focusSettleUs` | `200000` | Delay after focus click for keyboard focus to settle (microseconds) |
| `deadKeyDelayUs` | `30000` | Delay between dead-key trigger and base character for accented input (microseconds) |
| `defaultDragDurationMs` | `1000` | Default drag gesture duration in milliseconds |
| `defaultLongPressDurationMs` | `500` | Default long press duration in milliseconds |
| `defaultSwipeDurationMs` | `300` | Default swipe duration in milliseconds |

## Scroll & Swipe

| Setting | Default | Description |
|---------|---------|-------------|
| `swipeDistanceFraction` | `0.3` | Swipe distance as a fraction of window height |
| `scrollSwipeFromYFraction` | `0.56` | Scroll start Y as a fraction of window height |
| `scrollSwipeToYFraction` | `0.11` | Scroll end Y as a fraction of window height |
| `defaultScrollMaxAttempts` | `10` | Maximum scroll attempts for `scroll_to` before giving up |
| `scrollDedupStrategy` | `"exact"` | Dedup strategy for scroll-collected elements: `"exact"`, `"levenshtein"`, `"proximity"` |

## Exploration

| Setting | Default | Description |
|---------|---------|-------------|
| `explorationMaxDepth` | `6` | Maximum BFS/DFS depth before forcing backtrack |
| `explorationMaxScreens` | `30` | Maximum distinct screens before stopping exploration |
| `explorationMaxTimeSeconds` | `300` | Maximum wall-clock seconds before stopping exploration |
| `componentDetection` | `"llm_first_screen"` | Component detection mode: `"heuristic"`, `"llm_first_screen"`, `"llm_every_screen"`, `"llm_fallback"` |
| `calibrationStrict` | `true` | Fail exploration if too many elements are unclassified after calibration |
| `calibrationUnclassifiedThreshold` | `0.5` | Maximum fraction of unclassified content elements (0.0–1.0) before calibration fails |
| `compiledTapMinConfidence` | `0.7` | Minimum confidence for compiled taps (below this, falls back to live OCR) |
| `verifyTaps` | `false` | Follow compiled taps with a verification OCR call |

## Keyboard Layout

| Setting | Default | Description |
|---------|---------|-------------|
| `keyboardLayout` | `""` | iPhone keyboard layout for character substitution (e.g. `"Canadian-CSA"`, `"French"`). Empty = US QWERTY |

## AI Provider Timeouts

| Setting | Default | Description |
|---------|---------|-------------|
| `openAITimeoutSeconds` | `30` | Timeout for OpenAI API requests |
| `anthropicTimeoutSeconds` | `30` | Timeout for Anthropic API requests |
| `ollamaTimeoutSeconds` | `120` | Timeout for Ollama API requests |
| `embacleTimeoutSeconds` | `60` | Timeout for embacle FFI/API requests |
| `commandTimeoutSeconds` | `60` | Timeout for command-based AI agent processes |
| `defaultAIMaxTokens` | `1024` | Maximum tokens for AI model responses |

## Advanced Tuning

Additional low-level tuning constants (icon detection, scroll deduplication, tap point calculation, grid overlay) are available in [`TimingConstants.swift`](../Sources/HelperLib/TimingConstants.swift) and [`EnvConfigFeatures.swift`](../Sources/HelperLib/EnvConfigFeatures.swift).

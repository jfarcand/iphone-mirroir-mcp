# Scenario grammar reference

This document is the canonical reference for the YAML grammar `mirroir-run`
parses. Every `SkillStep` variant is listed below with the YAML shape and its
dispatch target (process / http / web / oracle / unwired). Which run path
exercises a step end-to-end depends on the invocation flag
(`--sample` / `--validate` / `--run-scenario` / `--compile-scenario` /
`--diff-text`).

Source of truth: `runner/src/parser/step.rs`. Run `cargo doc --open` from
`runner/` for the auto-generated rustdoc; this file gives the prose view
keyed by scenario-author concerns.

## Top-level shape

```yaml
version: 1                  # schema major; mismatch is a hard load error
name: "scenario name"
description: "free-form prose"   # optional
app: "spring-boot-chat"          # optional; references SAMPLE.md slug
tags: ["smoke", "streaming"]     # optional
steps:
  - <step>
  - <step>
```

`${VAR}` and `${VAR:-default}` substitution runs over the raw YAML *before*
parsing. POSIX semantics — unset or empty variables resolve to the default
when one is given, else to the empty string.

In `--sample` mode the runner additionally exposes `${MIRROIR_SAMPLE_DIR}`
so scenarios can reference baseline files relative to the sample directory.

---

## Process target steps (dispatched via `tokio::process`)

### `spawn`

Start a subprocess. `command:` or `from: SAMPLE.md` is required; inline values
win over manifest values when both are present.

```yaml
- spawn:
    id: server                       # required; later kill/assert_log/wait_port reference this id
    command: "java -jar foo.jar"     # required unless `from:` is set
    from: SAMPLE.md                  # optional; pulls boot.command / cwd / env / timeout_s from SAMPLE.md
    cwd: "samples/foo"               # optional; resolved relative to the sample dir in --sample mode
    env:                             # optional; merged with manifest env (inline wins per-key)
      SPRING_PROFILES_ACTIVE: ci
    timeout_s: 60                    # optional ceiling on subprocess runtime
    expect_exit: 0                   # optional required exit code (post-mortem check)
    capture_stdout: var_name         # optional; capture stdout into a runner variable
```

Errors: `DuplicateProcessId`, `SpawnMissingSource`, `ProcessSpawn`.

### `kill`

Terminate a previously-spawned subprocess. Graceful: waits `grace_s` for
natural exit, then SIGTERM, then SIGKILL.

```yaml
- kill: { id: server, grace_s: 5 }   # cleanup: optional shell command after exit
```

Errors: `UnknownProcess`, `ProcessControl`.

### `wait_port`

Block until a TCP port reaches the expected state. Both loopback addresses are
probed — IPv4 `127.0.0.1` **and** IPv6 `[::1]` — so dev servers that bind only
one are detected either way (Vite, for example, binds `[::1]` when told to
listen on `localhost`). `expect: open` resolves once either connects; `expect:
closed` once both refuse.

```yaml
- wait_port: { port: 8081, timeout_s: 30, expect: open }   # expect: open|closed
```

Errors: `WaitPortTimeout`.

### `assert_log`

Auto-polling regex match against the subprocess's captured stdout+stderr.
Mirrors Playwright's "expect-with-retry" model — polls every 100 ms up to
`timeout_s` (default 5 s).

```yaml
- assert_log:
    id: server
    pattern: 'Started ServerApplication'
    flags: "i"           # optional: i (case-insensitive), m, s, x, U
    timeout_s: 10        # optional
```

Errors: `UnknownProcess`, `RegexFlags`, `RegexCompile`, `LogAssertion`.

### `assert_log_clean`

Single-shot scan: fail if any `deny` pattern matches a line that no `allow`
pattern also matches.

```yaml
- assert_log_clean:
    id: server
    deny:
      - { pattern: '^\s*ERROR\b', flags: "im" }
      - { pattern: 'BeanInstantiationException' }
    allow:
      - { pattern: 'Disabled retry on ERROR\.RATE_LIMIT' }
```

---

## HTTP target step (dispatched via `reqwest`)

### `http`

REST probe with optional status + body substring assertions.

```yaml
- http:
    method: GET                              # GET|POST|PUT|DELETE|HEAD|PATCH
    url: "http://127.0.0.1:8081/api/info"
    expect_status: 200                       # optional
    expect_body_contains:                    # optional list of substrings
      - "webtransport"
      - "websocket"
    timeout_s: 30                            # optional per-request timeout (default 30)
```

Errors: `HttpClient`, `HttpRequest`, `HttpStatusMismatch`, `HttpBodyRead`, `HttpBodyMismatch`.

---

## Web target steps (dispatched via Playwright)

Web steps buffer between non-web steps; the buffer is compiled to a
single Playwright spec and run via `npx playwright test`.

### `target`

Declares the web surface for subsequent web steps. Required as the first
web step of any web batch.

```yaml
- target:
    kind: web                                       # web|process|http|ios|macos (only web compiles to Playwright)
    browsers: [chrome, firefox, webkit]             # default [chrome]
    url: "http://localhost:8081/"                   # initial navigation
```

### `tap`, `type`, `wait_for`, `assert_visible`, `assert_not_visible`

Click a labelled element / type into the focused element / wait for label /
assert visibility. A label resolves in three ways, in priority order:

1. **Raw CSS / locator passthrough** — label starts with one of `[ # . : > *`
   → `page.locator(label)`. Use for form fields and attribute selectors:
   `[name="email"]`, `[placeholder^="Type a message"]`, `.message--assistant`.
2. **Playwright locator-engine passthrough** — label starts with `role=`,
   `text=`, `xpath=`, `css=`, `id=`, or `data-testid=` → `page.locator(label)`.
   This is the workhorse for accessible apps (ARIA role + accessible name):
   `role=button[name="Send message"]`, `role=heading[name="Settings"]`.
3. **Otherwise** → `[data-test="<label>"]` **OR**
   `page.getByText(<label>, { exact: true })`.

```yaml
- tap: "role=button[name=\"Send message\"]"          # role engine (preferred for real apps)
- tap: "[name=\"email\"]"                            # raw CSS for inputs
- type: "hello mirroir"
- wait_for: { label: "text=claude-opus", timeout_s: 60 }  # text= = substring; survives version bumps
- assert_visible: "role=heading[name=\"Directory listing for /\"]"
- assert_not_visible: "Error toast"
```

Selector gotchas (each surfaced by real onboarding):

- **`role=…[name="X"]` matches the accessible name EXACTLY** (trimmed,
  case-insensitive) — not a substring. It won't match an element whose
  accessible name is a longer concatenation (e.g. a card `<button>` whose name
  is title + description). Target the unique inner text node instead (bare
  text → `getByText`, which the click bubbles up), or use `text=`.
- **`text=` is a substring match**; bare text (no prefix) is **exact** via
  `getByText`. A label with a trailing count/badge ("Pending Users (3)") needs
  `text=Pending Users`, not the bare exact form.
- **Duplicate matches** (label resolves to >1 element → Playwright strict-mode
  error) → append `>> nth=0`: `role=button[name="Create Group"] >> nth=0`.
- Trust the accessible name from a browser **accessibility tree** snapshot, not
  `el.textContent` — they differ (e.g. a tab reads `Pending 3` with a space in
  the a11y name even when `textContent` is `Pending3`).

### `press_key`

Key combos with mirroir-style modifier names (mapped to Playwright's
`Meta+Shift+Enter` form at compile time).

```yaml
- press_key: { key: "return", modifiers: ["command", "shift"] }
```

### `swipe`, `scroll_to`, `long_press`, `drag`

```yaml
- swipe: "up"                                       # up|down|left|right; emits page.mouse.wheel
- scroll_to: "Welcome"
- long_press: { label: "Send", duration_ms: 1000 }
- drag: { from: "card-1", to: "drop-zone" }
```

### `screenshot`, `open_url`, `remember`

```yaml
- screenshot: "after-send"                          # writes screenshots/after-send.png
- open_url: "https://example.com/profile"
- remember: "user is in deep blue mode"             # comment in emitted spec; no runtime effect
```

---

## Native-only steps (iOS / macOS via mirroir-mcp Swift)

The Rust runner does not execute these. They parse so cross-platform
scenarios stay portable; in `mirroir-run` they are no-ops (logged as
"step kind not yet wired"). The Swift `mirroir-mcp` binary dispatches them
on iOS/macOS targets.

```yaml
- launch: "Expo Go"
- home: null
- shake: null
- reset_app: "com.example.app"
- set_network: "airplane"
- measure: { name: "first_token_latency", action: "tap:send", until: "delivered", max_seconds: 5 }
```

---

## Control-flow steps

### `condition`

Branch on visibility of a label. The runner does **not** yet dispatch
condition; it parses for grammar compatibility.

```yaml
- condition:
    if_visible: "Invalid credentials"
    then:
      - tap: "Sign Up"
    else:
      - wait_for: "Welcome"
```

### `report`

Emit a final verdict. The `report:` step itself parses and is skipped at
runtime — it does not yet drive the verdict. The JSON report artifact is a
separate, wired path: `--report` (default `mirroir-run-report.json`) is always
written by the run summary regardless of this step.

```yaml
- report: pass                                       # or fail | drift | cross_surface_pass
- report: { verdict: drift }
```

---

## Oracle steps

### `judge`

LLM scoring of a captured response. See [judge-profiles.md](judge-profiles.md)
for the profile registry.

```yaml
- judge:
    profile: byte-stable                             # fast-ci | byte-stable | cheap-local
    user_prompt_template_hash: "sha256:abc123…"      # pinned; verified every run, hard-fails on mismatch
    response_selector: "[data-test=reply]"           # for diagnostics; capture is via response_text / response_file
    pass_threshold: 0.85
    pass_threshold_tolerance: 0.05                   # optional; effective = threshold - tolerance
    expected_signal: "summary covers transports"     # human-readable; not load-bearing
    response_text: "…"                               # inline OR
    response_file: "${MIRROIR_SAMPLE_DIR}/captured.txt"   # from-file OR (one of these is required)
    response_drift:                                  # optional drift check
      max_levenshtein_pct: 0.15
    drift_baseline_file: "${MIRROIR_SAMPLE_DIR}/baselines/judge.txt"
```

Errors: `JudgeUnknownProfile`, `JudgeMissingApiKey`, `JudgeTransport`,
`JudgeDecode`, `JudgeBelowThreshold`, `JudgeTemplateMismatch`, `DriftDetected`.

### `cross_surface`

Pairwise equivalence check across N captured response files (one per
surface). Uses Jaccard fingerprint similarity over normalized token sets.

```yaml
- cross_surface:
    response_files:
      - "${MIRROIR_SAMPLE_DIR}/baselines/surface-web.txt"
      - "${MIRROIR_SAMPLE_DIR}/baselines/surface-ios.txt"
    min_similarity: 0.7                              # default 0.7
    capture:                                         # optional: produce the web baseline
      selector: "main"                               #   scrape this selector's textContent()
      to: "${MIRROIR_SAMPLE_DIR}/baselines/surface-web.txt"  #   into this file (one of response_files)
```

With `capture`, the runner scrapes `selector`'s text into `to` during the
preceding web batch (reusing the `judge:` Playwright capture path), so the web
baseline is produced at run time rather than hand-authored. Without it, all
`response_files` must already exist.

`to` **must** be one of the `response_files`, and the step fails when it is not:
a capture aimed elsewhere writes text nothing reads, leaving the comparison to
run against whatever sits at the listed path — a stale baseline from an earlier
run compares clean and the check passes for the wrong reason.

Errors: `CrossSurfaceTooFewFiles`, `CrossSurfaceCaptureTargetNotListed`,
`CrossSurfaceMismatch`.

---

## Step kind ↔ dispatch target

| Step kinds | Dispatcher | Notes |
|---|---|---|
| `spawn`, `kill`, `wait_port`, `assert_log`, `assert_log_clean` | `target::process` (tokio) | Per-scenario `ProcessRegistry`; shared in `boot_once` mode |
| `http` | `target::http` (reqwest) | One `HttpClient` per scenario |
| `target` (kind=web), `tap`, `type`, `wait_for`, `assert_visible`, `assert_not_visible`, `screenshot`, `press_key`, `swipe`, `scroll_to`, `long_press`, `drag`, `open_url`, `remember` | `compile::playwright` + `compile::invoke` | Batched into one spec per contiguous web run |
| `judge` | `oracle::judge` | OpenAI-compatible chat completions |
| `cross_surface` | `oracle::drift` | Jaccard over `Fingerprint` |
| `launch`, `home`, `shake`, `reset_app`, `set_network`, `measure`, `condition`, `report` | unwired | Parse and skip; logged. iOS-side dispatched by `mirroir-mcp` (Swift) when the scenario also runs there. |

# mirroir-run

Cross-platform replayer for [mirroir](https://mirroir.dev) `SkillStep` YAML
scenarios. Reads scenarios authored against mirroir's step grammar and drives:

- **Web** — compiles steps to Playwright `.spec.ts` and invokes `npx playwright test` against Chromium / Firefox / WebKit.
- **Process** — spawns subprocesses (server lifecycle, CLI tests), captures logs, asserts log shape, kills cleanly.
- **HTTP** — REST probes against MCP, A2A, and other JSON-RPC endpoints.

Runs on Linux + macOS CI without macOS-only AppKit dependencies. iOS replay
stays on mirroir's existing Swift `StepExecutor` at the parent level.

## Status

Shipped. The full build sequence is delivered (13 / 13) and `main.rs` dispatches
a multi-mode runner: scenario `--validate` / `--compile-scenario` /
`--run-scenario`, `--sample` session replay, `--diff-text` drift, and the
`.mirroir/` consumer pipeline (explicit `--config` or bare-invocation
autodiscovery). Every module carries real implementation — no placeholder code
per `AGENTS.md`.

## Design

Two secret design gists hold the locked specification:

- [Complete planned solution](https://gist.github.com/jfarcand/e4cc69eeddde2ec4988aa20104566c17)
  — every artifact, every browser, every supported sample type, full step grammar,
  drift threshold ownership, build sequence.
- [Brainstorm history](https://gist.github.com/jfarcand/7c30b04801ecfb6ba59c6ca1f62506f7)
  — how we got here (Rust vs. Swift, the Playwright decision, the
  agent + chrome-devtools-mcp canonical chrome recorder).

## Install

```bash
# crates.io
cargo install mirroir-run

# Homebrew
brew install jfarcand/tap/mirroir-run
```

Prebuilt binaries for macOS (Intel + Apple Silicon), Linux (gnu + musl), and
Windows are attached to each [`runner-v*` release](https://github.com/jfarcand/mirroir-mcp/releases).

## Build

To build from source (contributors):

```bash
cd runner
cargo build --release
```

Static-musl Linux binary for CI:

```bash
cargo build --release --target=x86_64-unknown-linux-musl
```

## Usage

Six modes are wired and verified end-to-end:

```bash
# 0) PRIMARY — `.mirroir/` pipeline. A bare invocation walks `cwd ↑` to the
#    nearest `.mirroir/mirroir.yaml`, resolves archetypes against
#    `~/.mirroir/skills/`, checks the lockfile, composes into `.mirroir/.build/`,
#    then replays each sample. `--config` points at an explicit plan instead.
mirroir-run
mirroir-run --config path/to/.mirroir/mirroir.yaml

# 1) Validate a scenario YAML against the SkillStep grammar.
mirroir-run --validate scenarios/connect-then-broadcast.yaml

# 2) Compile a scenario's web steps to a Playwright spec + config (prints to stdout).
mirroir-run --compile-scenario scenarios/connect-then-broadcast.yaml

# 3) Run a single scenario end-to-end (process / http / web / judge / drift).
MIRROIR_PLAYWRIGHT_HOME=/path/to/playwright \
  mirroir-run --run-scenario scenarios/connect-then-broadcast.yaml

# 4) Drive a full sample (SAMPLE.md + multiple scenarios; supports boot_once).
MIRROIR_PLAYWRIGHT_HOME=/path/to/playwright \
  mirroir-run --sample samples/mega-sample --scenarios must-pass

# 5) Compute drift between two text files (Jaccard + Levenshtein).
mirroir-run --diff-text baseline.txt current.txt --levenshtein-threshold 0.2
```

The `.mirroir/` pipeline (mode 0) takes these flags: `--config <PATH>` (explicit
plan, overrides cwd-based discovery), `--no-local` (skip `mirroir.local.yaml`),
`--compose-only` (compose `.mirroir/.build/` and exit without replaying),
`--recompose` (delete `.mirroir/.build/` and recompose from scratch),
`--no-compose` (reuse the existing `.build/` tree as-is), `--locked` (CI gate:
error when `mirroir.lock` is missing or stale vs `mirroir.yaml`), `--frozen`
(`--locked` plus no network fetch), `--no-playwright` (skip web step batches),
`--report <PATH>` (JSON report artifact), `--skills <PATH>`
(`MIRROIR_SKILLS` checkout), and `--scenarios <set>` (defaults to the config's
`default_set`, falling back to `must_pass`).

The `samples/mega-sample/` reference walks every primitive in four scenarios:
cross-browser web (chromium + firefox + webkit), HTTP probe, judge + drift
against a local Ollama instance, and cross-surface equivalence. Run it with
the command above to verify the full pipeline on your machine.

## Documentation

| Topic | Doc |
|---|---|
| Scenario grammar (every `SkillStep` variant, dispatch routing) | [docs/scenario-grammar.md](docs/scenario-grammar.md) |
| `SAMPLE.md` schema (`Session`, `Boot`, `Scenarios`, `boot_once`) | [docs/sample-md-format.md](docs/sample-md-format.md) |
| Judge profile registry + Ollama / OpenAI wire format | [docs/judge-profiles.md](docs/judge-profiles.md) |
| Playwright install + `MIRROIR_PLAYWRIGHT_HOME` walkthrough | [docs/playwright-setup.md](docs/playwright-setup.md) |
| CI lanes, caching, integration into downstream repos | [docs/ci-integration.md](docs/ci-integration.md) |

## Build sequence — fully delivered (13 / 13)

| # | Milestone | Commit |
|---|-----------|--------|
| 1 | Parser (SkillStep grammar + env substitution + `--validate`) | `9101a2d` |
| 2 | Process target (`spawn/kill/wait_port/assert_log{,_clean}`) | `17ce319` |
| 3 | HTTP target (REST probe with status + body assertions) | `78b7c26` |
| 4 | First runnable CLI smoke scenarios (process + http end-to-end) | `78b7c26` |
| 5 | `SAMPLE.md` + `--sample` mode + `from: SAMPLE.md` resolution | `4ba2aa7` |
| 6 | Compile web steps → Playwright `.spec.ts` + config | `63c3a43` |
| 7 | Invoke `npx playwright test` + ingest JSON reporter | `5bedbac` |
| 8 | Oracle profile registry + drift detection + session boot | `a494206` |
| 9 | Judge `:` post-hook (OpenAI-compatible LLM client) | `6779364` |
| 10 | Cross-browser fallback (chromium + firefox + webkit, real) | verified in `a494206` |
| 11 | Sample expansion — `samples/mega-sample/` reference | `3d2c040` |
| 12 | Session-scoped boot (`session.boot_once: true`) | `a494206` |
| 13 | Cross-surface invariants (`cross_surface:` step primitive) | `2de3692` |

Cross-surface implementation note: the runner provides the equivalence-comparison
primitive (`cross_surface:` step + pairwise Jaccard fingerprint). Surfaces feed
their captured responses to it via filesystem paths. The web side captures via
the Playwright spec calling `page.locator(...).textContent()` and writing out;
the iOS side captures via `mirroir-mcp` (Swift) writing its observed AX/OCR
output. The runner is surface-agnostic — both are just files to compare.

## Module layout

```
src/
├── main.rs                # CLI entry; clap arg parsing; dispatches to replay:: / mirroir::
├── error.rs               # RunnerError + Result (thiserror, ~50 typed variants)
├── replay.rs              # scenario dispatch + sample loop + web-batch buffering
├── replay_dispatch.rs     # judge / drift / cross_surface step dispatch helpers
├── replay_sample.rs       # `--sample <dir>` session machinery (SAMPLE.md + shared boot)
├── parser/
│   ├── mod.rs             # parser index + compiled.json cache structs
│   ├── archetype.rs       # archetype.md manifest (YAML frontmatter + markdown body)
│   ├── env.rs             # ${VAR} / ${VAR:-default} textual substitution
│   ├── substitute.rs      # post-parse ${VAR} substitution on serde_yaml::Value trees
│   ├── local_overrides.rs # mirroir.local.yaml merge (instance wins; arrays replace)
│   ├── lockfile.rs        # mirroir.lock schema + (de)serializer
│   ├── mirroir.rs         # .mirroir/mirroir.yaml plan (samples + archetype refs)
│   ├── mirroir_plan.rs    # archetype reference parsing (pack / ./path / user refs)
│   ├── sample.rs          # SAMPLE.md manifest (fenced-yaml block + Session)
│   ├── scenario.rs        # Scenario top-level (singleton_map_recursive enum form)
│   ├── step.rs            # SkillStep enum — 30 variants (Launch..CrossSurface)
│   ├── step_args.rs       # oracle/verdict step args (judge, drift, http, report, cross_surface)
│   └── step_process_args.rs # process-target step args (spawn, wait_port, kill, assert_log)
├── mirroir/
│   ├── mod.rs             # `.mirroir/` discovery → resolve → compose → run index
│   ├── discover.rs        # walk-up cwd discovery of `.mirroir/mirroir.yaml`
│   ├── resolve.rs         # ArchetypeRef → on-disk directory + manifest (per-kind dispatch)
│   ├── resolve_version.rs # semver-ish version parsing + constraint matching
│   ├── lock.rs            # lockfile freshness check + --locked/--frozen enforcement
│   ├── lock_generate.rs   # lockfile generation (source/version/checksum + git provenance)
│   ├── compose.rs         # archetype + plan entry → `.mirroir/.build/<sample>/` tree
│   ├── compose_cache.rs   # compose-cache freshness (sha256 + mtime fast-path)
│   ├── compose_synth.rs   # ${VAR} substitution + SAMPLE.md synthesis helpers
│   ├── run.rs             # `run_mirroir` orchestrator (discover+resolve+lock+compose+run_sample)
│   └── run_io.rs          # config + local-override loading + run-summary JSON
├── target/
│   ├── mod.rs             # execution targets index (process + http)
│   ├── process.rs         # tokio::process registry (spawn/kill/SIGTERM/log capture)
│   ├── process_log.rs     # log-capture plumbing (stream pumping, group signalling, regex)
│   ├── process_port.rs    # TCP port-readiness polling for `wait_port:`
│   └── http.rs            # reqwest probe + status/body assertions
├── compile/
│   ├── mod.rs             # compilation targets index (Playwright only today)
│   ├── playwright.rs      # YAML web steps → .spec.ts + playwright.config.ts
│   ├── playwright_emit.rs # per-step Playwright emission (key/modifier/swipe translation)
│   └── invoke.rs          # spawn `npx playwright test` + parse JSON reporter
└── oracle/
    ├── mod.rs             # oracle index (drift + judge + judge profiles)
    ├── drift.rs           # Fingerprint + Jaccard + Levenshtein verdict
    ├── judge.rs           # OpenAI-compatible HTTP client + template-hash verification
    └── judge_profiles.rs  # judge profile registry (built-in + overlay, trust-tiered)
```

Single crate; no internal sub-crates until an external consumer appears.

## Relationship to Swift mirroir

This runner does **not** port mirroir's Swift code. It implements the **shared
schema** — `SkillStep` grammar verbatim + `.compiled.json` cache format —
against which both runtimes operate.

- Swift `Sources/mirroir-mcp/StepExecutor.swift` keeps running iOS / macOS targets.
- Rust `runner/src/` adds web (via Playwright) / process / http targets for Linux CI.
- A cross-parser fixture test diffs both implementations' parsed AST against
  the same `mirroir-skills/legacy/testing/expo-go/login-flow.yaml` to catch
  drift between the two parsers.

The runner owns its own `.mirroir/` consumer pipeline (`runner/src/mirroir/`): a
checked-out repo carries a `.mirroir/mirroir.yaml` plan that lists samples plus
archetype references. The runner discovers it by walking `cwd ↑`, resolves each
archetype against `~/.mirroir/skills/`, verifies the `mirroir.lock`, composes the
ready-to-replay tree into `.mirroir/.build/`, and replays it. This `.mirroir/`
dotfile (a consumer repo's checked-in plan) is distinct from `.mirroir-mcp/`,
the Swift MCP server's home directory for element patterns and skills.

## Discipline

This workspace enforces a strict Rust posture documented in the parent
[`AGENTS.md`](../AGENTS.md#rust-workspace-runner). The headlines:

- `unsafe_code = "deny"`. No FFI; any `unsafe` is a hard fail.
- Clippy `all`/`pedantic`/`nursery` at `deny`. `unwrap_used` / `expect_used` /
  `panic` denied in production code.
- `anyhow!()` macro forbidden — structured `RunnerError` everywhere; convert
  external errors via `#[from]` or `.map_err(|source| RunnerError::Variant { ... })`.
- `anyhow::Context` disallowed via `clippy.toml` `disallowed-methods`.
- Test functions return `Result<()>` and propagate via `?` — no `.unwrap()` /
  `.expect()` / `panic!()` even in test code.
- Every `.rs` file starts with two `// ABOUTME:` header lines. Max 500 lines
  per file.

`scripts/ci/pre-push-validate.sh` enforces these mechanically: fmt, the
limitation-register gates (`.registre/limitation-gates.sh` at the repo root —
deferral prose ban, 500-line cap, inline clippy allow-list), clippy, tests.

## License

Apache-2.0 — same as the parent `iphone-mirroir-mcp` project.

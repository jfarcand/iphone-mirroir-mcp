// ABOUTME: Structured error type for the mirroir-run binary — no anyhow!(), no untyped errors.
// ABOUTME: Every fallible operation returns Result<T, RunnerError> built from thiserror variants.

use std::fmt;
use std::io;
use std::ops::RangeInclusive;
use std::path::PathBuf;
use std::result::Result as StdResult;

use thiserror::Error;

/// `Result` alias used throughout the `mirroir-run` binary.
///
/// All fallible operations propagate [`RunnerError`] via `?`. No `anyhow!()`
/// macros, no `anyhow::Result`, no ad-hoc string errors.
pub type Result<T> = StdResult<T, RunnerError>;

/// All errors the runner produces.
///
/// Each variant carries enough context for both human-readable display via
/// [`std::fmt::Display`] and downstream programmatic handling (e.g. CLI exit
/// codes, structured logging fields). Every variant is constructed somewhere in
/// the crate — there is no blanket `dead_code` allow masking unused variants.
#[derive(Debug, Error)]
pub enum RunnerError {
    /// A regex pattern failed to compile.
    #[error("regex compilation failed for `{pattern}`")]
    RegexCompile {
        /// Short identifier for the pattern that failed (e.g. `"env-substitution"`).
        pattern: String,
        /// Underlying error from the `regex` crate.
        #[source]
        source: regex::Error,
    },

    /// YAML deserialization failed.
    #[error("YAML parse failed for {file}")]
    YamlParse {
        /// Path or label of the YAML document that failed.
        file: String,
        /// Underlying error from `serde_yaml`.
        #[source]
        source: serde_yaml::Error,
    },

    /// Filesystem or other I/O operation failed.
    #[error("I/O error: {context}")]
    Io {
        /// What the runner was attempting when the I/O failed.
        context: String,
        /// Underlying [`std::io::Error`].
        #[source]
        source: io::Error,
    },

    /// An artifact (`SAMPLE.md` / scenario YAML / `APP.md` / `profiles.yaml`) declares
    /// a `version` field outside the range the running binary supports.
    #[error("unsupported {artifact} version {found} (supported range: {expected:?})")]
    UnsupportedVersion {
        /// Artifact kind (e.g. `"SAMPLE.md"`, `"scenario.yaml"`).
        artifact: String,
        /// Version found in the artifact header.
        found: u32,
        /// Inclusive range of major versions the binary supports.
        expected: RangeInclusive<u32>,
    },

    /// `spawn` step could not start the requested subprocess.
    #[error("spawn `{id}` failed: command `{command}`")]
    ProcessSpawn {
        /// Scenario-supplied identifier for the subprocess.
        id: String,
        /// The command line that was attempted (already env-substituted).
        command: String,
        /// Underlying I/O error from `tokio::process::Command::spawn`.
        #[source]
        source: io::Error,
    },

    /// `kill` / `wait` against a previously-spawned subprocess failed.
    #[error("kill/wait on `{id}` failed: {context}")]
    ProcessControl {
        /// Subprocess identifier.
        id: String,
        /// Short phrase describing which control operation tripped.
        context: String,
        /// Underlying I/O error.
        #[source]
        source: io::Error,
    },

    /// Step referenced a subprocess id that the registry has never seen.
    #[error("no spawned process registered under id `{id}`")]
    UnknownProcess {
        /// The unknown identifier.
        id: String,
    },

    /// `spawn` step asked for an id that is already live in the registry.
    #[error("subprocess id `{id}` is already registered (call `kill` first)")]
    DuplicateProcessId {
        /// The conflicting identifier.
        id: String,
    },

    /// `spawn` step declared neither a `command:` nor a `from: SAMPLE.md` source.
    #[error("spawn `{id}` declared no command and no `from:` source")]
    SpawnMissingSource {
        /// The subprocess identifier whose spawn args were under-specified.
        id: String,
    },

    /// `wait_port` step did not see the expected port state before its deadline.
    #[error("wait_port {port} (expect {expect}) timed out after {timeout_s}s")]
    WaitPortTimeout {
        /// TCP port that was being probed.
        port: u16,
        /// Configured timeout in seconds.
        timeout_s: u32,
        /// Expected state at the deadline (`open` or `closed`).
        expect: &'static str,
    },

    /// `assert_log` / `assert_log_clean` step found the log in the wrong shape.
    #[error("log assertion on `{id}` failed: {reason}")]
    LogAssertion {
        /// Subprocess identifier whose log was being inspected.
        id: String,
        /// Why the assertion failed (e.g. "pattern not found", "deny matched").
        reason: String,
    },

    /// A regex flag string from the YAML used unsupported characters.
    #[error("invalid regex flags `{flags}`: {reason}")]
    RegexFlags {
        /// The offending flag string.
        flags: String,
        /// What was wrong with it.
        reason: String,
    },

    /// Building the underlying `reqwest::Client` failed (TLS, DNS resolver init, …).
    #[error("HTTP client initialization failed")]
    HttpClient {
        /// Underlying `reqwest` error.
        #[source]
        source: reqwest::Error,
    },

    /// An `http:` step could not complete the request (DNS, refused connect, timeout, …).
    #[error("HTTP request to `{url}` failed")]
    HttpRequest {
        /// Target URL.
        url: String,
        /// Underlying `reqwest` error.
        #[source]
        source: reqwest::Error,
    },

    /// An `http:` step's response had a different status code than `expect_status:`.
    #[error("HTTP `{url}` returned status {actual}, expected {expected}")]
    HttpStatusMismatch {
        /// Target URL.
        url: String,
        /// Status code declared in the YAML.
        expected: u16,
        /// Status code the server actually returned.
        actual: u16,
    },

    /// Reading an `http:` step's response body failed (connection drop, decode error, …).
    #[error("HTTP `{url}` body read failed")]
    HttpBodyRead {
        /// Target URL.
        url: String,
        /// Underlying `reqwest` error.
        #[source]
        source: reqwest::Error,
    },

    /// An `http:` step's response body did not contain a required substring.
    #[error("HTTP `{url}` body missing required substring `{expected}`")]
    HttpBodyMismatch {
        /// Target URL.
        url: String,
        /// The substring from `expect_body_contains:` that was missing.
        expected: String,
    },

    /// `SAMPLE.md` had no fenced `yaml` code block to parse as the manifest.
    #[error("SAMPLE.md at `{path}` has no fenced yaml block")]
    SampleMissingYaml {
        /// Filesystem path of the offending `SAMPLE.md`.
        path: String,
    },

    /// A scenario used `spawn: { from: SAMPLE.md }` in a mode where no sample
    /// context is available (typically `--run-scenario`, which is single-file).
    #[error(
        "spawn `{id}` requested `from: SAMPLE.md` but no sample context is active (use `--sample` mode)"
    )]
    SpawnFromSampleNoContext {
        /// The subprocess id whose spawn args needed manifest resolution.
        id: String,
    },

    /// At least one `must_pass` scenario in a `--sample` run reported FAIL.
    #[error("sample run: {failed} of {total} scenarios failed")]
    SampleScenarioFailures {
        /// Number of scenarios that returned `Err`.
        failed: usize,
        /// Total scenarios attempted in the run.
        total: usize,
    },

    /// Scenario can't be compiled into a Playwright `.spec.ts` file.
    #[error("cannot compile scenario for Playwright: {reason}")]
    PlaywrightUnsupported {
        /// Why this scenario isn't web-compilable (missing target, wrong kind, …).
        reason: String,
    },

    /// Internal: failed to encode a TypeScript string literal during compilation.
    #[error("playwright compile: {context}")]
    PlaywrightEncode {
        /// What was being encoded (label, scenario name, URL, …).
        context: String,
        /// Underlying `serde_json` encode error.
        #[source]
        source: serde_json::Error,
    },

    /// `std::fmt::Write` failure while building emitter output. Theoretically
    /// unreachable when writing to `String`, but typed for `?`-propagation.
    #[error("internal formatting error")]
    Format(#[from] fmt::Error),

    /// Failed to set up the temporary workspace for a Playwright invocation.
    #[error("playwright workspace setup failed: {context}")]
    PlaywrightWorkspace {
        /// What was being done (mkdir, write spec, write config, …).
        context: String,
        /// Underlying I/O error.
        #[source]
        source: io::Error,
    },

    /// `npx playwright test` exited non-zero without a parseable report.
    #[error("playwright invocation failed (status: {status:?})\nstderr tail:\n{stderr_tail}")]
    PlaywrightInvoke {
        /// Exit status of `npx`, `None` if killed by signal.
        status: Option<i32>,
        /// Stderr captured from the subprocess (truncated to ~4 KiB).
        stderr_tail: String,
    },

    /// `npx` could not be found on `PATH` — Playwright cannot be invoked.
    #[error("`npx` is not on PATH; install Node + run `npm i -D @playwright/test`")]
    PlaywrightNotInstalled,

    /// The JSON reporter file is missing or unparseable.
    #[error("could not parse playwright-report.json at `{path}`")]
    PlaywrightReport {
        /// Path to the JSON reporter output we tried to read.
        path: String,
        /// Underlying parse error.
        #[source]
        source: serde_json::Error,
    },

    /// Playwright completed and reported per-test failures.
    #[error("playwright: {failed} of {total} test cases failed")]
    PlaywrightTestFailures {
        /// Number of test cases that reporter marked `status != passed`.
        failed: usize,
        /// Total test cases recorded by reporter.
        total: usize,
    },

    /// Drift detection flagged the current response as too far from baseline.
    #[error("drift detected: {reason}")]
    DriftDetected {
        /// Human-readable description of which thresholds tripped.
        reason: String,
    },

    /// Scenario named a judge profile the registry doesn't know.
    #[error("unknown judge profile `{profile}`")]
    JudgeUnknownProfile {
        /// Name of the missing profile.
        profile: String,
    },

    /// The judge profile required an environment variable for its API key.
    #[error("judge profile `{profile}` requires env `{env_var}` to be set")]
    JudgeMissingApiKey {
        /// The profile that requires the key.
        profile: String,
        /// Name of the environment variable that wasn't found.
        env_var: String,
    },

    /// HTTP transport to the LLM provider failed.
    #[error("judge HTTP transport to `{url}` failed")]
    JudgeTransport {
        /// Provider URL that was being contacted.
        url: String,
        /// Underlying `reqwest` error.
        #[source]
        source: reqwest::Error,
    },

    /// The provider responded but the shape was unexpected.
    #[error("judge response decode failed: {reason}")]
    JudgeDecode {
        /// Short human-readable description of what was wrong.
        reason: String,
    },

    /// `oracles/profiles.yaml` exists but could not be read or parsed as a
    /// `profiles:` list of judge profiles.
    #[error("failed to load judge profiles from {path}: {reason}")]
    JudgeProfilesParse {
        /// Path to the offending `profiles.yaml`.
        path: PathBuf,
        /// Read or parse error description.
        reason: String,
    },

    /// Scenario pinned a `user_prompt_template_hash` that no longer matches the
    /// current oracle prompt template — the prompt changed, so the scenario's
    /// score calibration is stale and must be re-pinned.
    #[error(
        "judge user_prompt_template_hash mismatch: scenario pinned `{declared}` but current template is `{expected}` — re-pin the scenario"
    )]
    JudgeTemplateMismatch {
        /// Hash of the current oracle user-prompt template.
        expected: String,
        /// Hash the scenario declared.
        declared: String,
    },

    /// Judge scored the response below `pass_threshold - tolerance`.
    #[error("judge score {score:.3} below pass_threshold {threshold:.3} (profile `{profile}`)")]
    JudgeBelowThreshold {
        /// Profile that ran the scoring.
        profile: String,
        /// Score the judge returned.
        score: f64,
        /// Effective pass threshold (after tolerance subtracted).
        threshold: f64,
    },

    /// `cross_surface:` step found a pair of responses whose fingerprint
    /// similarity dropped below the configured threshold.
    #[error("cross_surface mismatch: `{a}` vs `{b}` similarity {observed:.3} < min {threshold:.3}")]
    CrossSurfaceMismatch {
        /// First file path of the mismatching pair.
        a: String,
        /// Second file path of the mismatching pair.
        b: String,
        /// Jaccard similarity actually observed for that pair.
        observed: f64,
        /// Minimum similarity required.
        threshold: f64,
    },

    /// `cross_surface:` step requires at least two response files to compare.
    #[error("cross_surface: need at least 2 response files, got {count}")]
    CrossSurfaceTooFewFiles {
        /// How many were supplied.
        count: usize,
    },

    /// `cross_surface:` capture writes somewhere the step never reads. The
    /// capture produces one of the compared baselines, so a `to` outside
    /// `response_files` — a typo, usually — would leave the scraped text
    /// unread and compare a stale or missing file in its place.
    #[error(
        "cross_surface capture writes to `{to}`, which is not one of response_files {response_files:?}"
    )]
    CrossSurfaceCaptureTargetNotListed {
        /// Path the capture would have written.
        to: String,
        /// The files the step actually compares.
        response_files: Vec<String>,
    },

    /// An archetype reference in `mirroir.yaml` could not be parsed.
    ///
    /// Valid forms: `<pack>/<name>[@<version>]`, `./<path>`, `user/<name>[@<version>]`.
    /// Bare `<name>` refs are rejected to eliminate pack/user collision ambiguity.
    #[error("invalid archetype reference `{value}`: {reason}")]
    MirroirInvalidArchetypeRef {
        /// The reference string from `mirroir.yaml`.
        value: String,
        /// Human-readable explanation of why parsing failed.
        reason: String,
    },

    /// A plan entry declares more than one archetype. Cross-archetype
    /// composition is on the roadmap but not implemented in v1.
    #[error(
        "plan entry `{entry_name}` declares {count} archetypes; v1 supports exactly one (cross-archetype composition is planned)"
    )]
    MirroirCompositionUnsupported {
        /// `name` field of the offending plan entry.
        entry_name: String,
        /// Number of archetypes declared.
        count: usize,
    },

    /// A plan entry has both `archetypes:` and `local:` set, or neither.
    /// Exactly one is required.
    #[error("plan entry `{entry_name}`: {reason}")]
    MirroirPlanEntryAmbiguous {
        /// `name` field of the offending plan entry.
        entry_name: String,
        /// "both archetypes and local set" or "neither archetypes nor local set".
        reason: String,
    },

    /// `mirroir-run` walked from `searched_from` to the filesystem root and
    /// never found a `.mirroir/mirroir.yaml`. Run inside a consumer repo, or
    /// pass `--config <PATH>` explicitly.
    #[error("no `.mirroir/mirroir.yaml` found walking up from `{searched_from}`")]
    MirroirConfigNotFound {
        /// Starting directory of the walk.
        searched_from: PathBuf,
    },

    /// An archetype reference could not be resolved to a directory on disk.
    #[error("archetype `{reference}` not found (searched: {searched:?})")]
    MirroirArchetypeNotFound {
        /// The reference string from `mirroir.yaml`.
        reference: String,
        /// Directories the resolver inspected.
        searched: Vec<PathBuf>,
    },

    /// A plan entry referenced a local sample that doesn't exist on disk.
    #[error("plan entry `{sample}` declared `local: {expected_path}` but the path does not exist")]
    MirroirSampleMissing {
        /// Plan entry name.
        sample: String,
        /// The resolved path that was missing.
        expected_path: PathBuf,
    },

    /// At least one sample in a `mirroir-run` invocation reported failures.
    #[error("mirroir plan: {failed} of {total} samples failed")]
    MirroirPlanFailures {
        /// Number of failed samples.
        failed: usize,
        /// Total samples attempted.
        total: usize,
    },

    /// The composed `.build/<sample>/` could not be built for the named sample.
    #[error("compose failed for sample `{sample}`: {context}")]
    MirroirComposeFailed {
        /// Plan entry name being composed.
        sample: String,
        /// Human-readable description of the compose step that failed.
        context: String,
        /// Underlying I/O error from the compose subprocess (file write, etc.).
        #[source]
        source: io::Error,
    },

    /// The lockfile drifted from `mirroir.yaml` and the run mode is `--locked`.
    #[error("lockfile is stale relative to mirroir.yaml: {reason}")]
    MirroirLockfileStale {
        /// What drifted (ref added, ref removed, version changed, …).
        reason: String,
    },

    /// `--frozen` mode requires the lockfile to be present and not require
    /// network fetch; one of those conditions was violated.
    #[error("frozen mode violation: {reason}")]
    MirroirFrozenViolation {
        /// What violated the frozen invariant.
        reason: String,
    },

    /// `mirroir.lock` was expected but is missing. Run `mirroir-run` without
    /// `--locked` to regenerate, or commit a lockfile.
    #[error("mirroir.lock not found at `{path}` (required by --locked)")]
    MirroirLockfileMissing {
        /// Where the lockfile was expected.
        path: PathBuf,
    },

    /// `HOME` environment variable is not set; can't locate `~/.mirroir/`.
    #[error("cannot resolve user home directory ($HOME is unset)")]
    MirroirHomeDirUnavailable,
}

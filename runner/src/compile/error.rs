// ABOUTME: Structured error type for the Playwright compile + invoke pipeline — emit, spawn, report.
// ABOUTME: Converts into RunnerError via #[from]; every variant carries the fields its message needs.

use std::io;

use thiserror::Error;

use crate::compile::report::TestFailure;

/// Errors raised while compiling a scenario to a Playwright spec, invoking
/// `npx playwright test`, or ingesting the JSON reporter it writes.
///
/// The compile pipeline owns this enum so [`crate::error::RunnerError`] stays
/// the runner-wide surface. Every variant converts into
/// [`crate::error::RunnerError::Playwright`] through `#[from]`, so `?`
/// propagates them unchanged.
#[derive(Debug, Error)]
pub enum PlaywrightError {
    /// Scenario can't be compiled into a Playwright `.spec.ts` file.
    #[error("cannot compile scenario for Playwright: {reason}")]
    Unsupported {
        /// Why this scenario isn't web-compilable (missing target, wrong kind, …).
        reason: String,
    },

    /// Internal: failed to encode a TypeScript string literal during compilation.
    #[error("playwright compile: {context}")]
    Encode {
        /// What was being encoded (label, scenario name, URL, …).
        context: String,
        /// Underlying `serde_json` encode error.
        #[source]
        source: serde_json::Error,
    },

    /// Failed to set up the temporary workspace for a Playwright invocation.
    #[error("playwright workspace setup failed: {context}")]
    Workspace {
        /// What was being done (mkdir, write spec, write config, …).
        context: String,
        /// Underlying I/O error.
        #[source]
        source: io::Error,
    },

    /// `npx playwright test` exited non-zero without a parseable report.
    #[error(
        "playwright invocation failed (status: {status:?})\nstdout tail:\n{stdout_tail}\nstderr tail:\n{stderr_tail}"
    )]
    Invoke {
        /// Exit status of `npx`, `None` if killed by signal.
        status: Option<i32>,
        /// Stdout captured from the subprocess (truncated to ~4 KiB) — where
        /// Playwright prints its own failure summary.
        stdout_tail: String,
        /// Stderr captured from the subprocess (truncated to ~4 KiB).
        stderr_tail: String,
    },

    /// `npx` could not be found on `PATH` — Playwright cannot be invoked.
    #[error("`npx` is not on PATH; install Node + run `npm i -D @playwright/test`")]
    NotInstalled,

    /// The JSON reporter file is missing or unparseable.
    #[error("could not parse playwright-report.json at `{path}`")]
    Report {
        /// Path to the JSON reporter output we tried to read.
        path: String,
        /// Underlying parse error.
        #[source]
        source: serde_json::Error,
    },

    /// The reporter recorded a status the ingest does not know. Walking past
    /// it would drop the result from every count, which turns an unrecognized
    /// outcome into a silent pass.
    #[error("playwright reported the unknown status `{status}` for `{title}`")]
    UnknownStatus {
        /// The status string the reporter wrote.
        status: String,
        /// Title of the spec that carried it.
        title: String,
    },

    /// The reporter parsed but recorded no test results at all — the spec was
    /// filtered out, the config selected no project, or Playwright aborted
    /// before running anything. Nothing was asserted, so this is not a pass.
    #[error("playwright wrote no test results to `{path}`; nothing was asserted")]
    ReportEmpty {
        /// Path to the JSON reporter output.
        path: String,
    },

    /// Playwright completed and reported per-test failures. Each failure
    /// carries the reporter's own title + error text, so the locator that
    /// actually failed reaches the run summary instead of a bare count.
    #[error("playwright: {failed} of {total} test cases failed{}", render_failures(.failures))]
    TestFailures {
        /// Number of test cases the reporter marked failed.
        failed: usize,
        /// Total test cases recorded by the reporter.
        total: usize,
        /// Title + message of each failed test case, in reporter order.
        failures: Vec<TestFailure>,
    },

    /// A `mirroir-captures` attachment was present but its body could not be
    /// decoded. The JSON reporter base64-encodes attachment bodies.
    #[error("could not decode the `mirroir-captures` attachment: {reason}")]
    CaptureDecode {
        /// What failed — base64 decoding, UTF-8 decoding, or JSON parsing.
        reason: String,
    },
}

/// Render the per-test failure detail appended to the `TestFailures` message.
fn render_failures(failures: &[TestFailure]) -> String {
    let mut out = String::new();
    for failure in failures {
        out.push_str("\n  - ");
        out.push_str(&failure.title);
        out.push_str(": ");
        out.push_str(&failure.message);
    }
    out
}

#[cfg(test)]
mod tests {
    use std::result::Result as StdResult;

    use super::{PlaywrightError, render_failures};
    use crate::compile::report::TestFailure;

    type TestResult = StdResult<(), String>;

    #[test]
    fn test_failures_message_carries_every_locator_text() -> TestResult {
        let err = PlaywrightError::TestFailures {
            failed: 2,
            total: 3,
            failures: vec![
                TestFailure {
                    title: "checkout".to_owned(),
                    message: "strict mode violation: resolved to 3 elements".to_owned(),
                },
                TestFailure {
                    title: "login".to_owned(),
                    message: "Timeout 5000ms exceeded".to_owned(),
                },
            ],
        };
        let rendered = err.to_string();
        for needle in [
            "playwright: 2 of 3 test cases failed",
            "checkout: strict mode violation: resolved to 3 elements",
            "login: Timeout 5000ms exceeded",
        ] {
            if !rendered.contains(needle) {
                return Err(format!("`{needle}` missing from:\n{rendered}"));
            }
        }
        Ok(())
    }

    #[test]
    fn render_failures_is_empty_for_no_failures() {
        assert_eq!(render_failures(&[]), String::new());
    }
}

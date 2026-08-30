// ABOUTME: The three verdicts — PASS, FAIL, DRIFT — as types, plus the process exit codes they map to.
// ABOUTME: DRIFT is "every assertion green and the semantics moved"; it has its own code so CI can decide.

use std::fmt;

use serde::{Deserialize, Serialize};

/// Exit code for a run in which every assertion held and nothing drifted.
pub const EXIT_PASS: u8 = 0;

/// Exit code for a run in which something failed: an assertion, a status code,
/// a judge score under its threshold, a dirty log, a runner error.
pub const EXIT_FAIL: u8 = 1;

/// Exit code for the DRIFT verdict: every structural assertion held, but at
/// least one drift metric moved past its resolved threshold. Distinct from
/// [`EXIT_FAIL`] on purpose — a CI lane decides for itself whether a drifted
/// run blocks the merge or only opens a review.
///
/// Chosen from the `sysexits.h` band this runner reserves (64-71);
/// `EX_DATAERR` is the closest classical meaning — the run's data moved.
pub const EXIT_DRIFT: u8 = 65;

/// What a scenario, sample, or plan concluded when it did not error out.
///
/// A failure is an `Err(RunnerError)`, never a variant here: this enum only
/// distinguishes the two outcomes a completed run can have.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunVerdict {
    /// Everything asserted held and nothing drifted.
    Pass,
    /// Everything asserted held, and at least one drift metric moved.
    Drift,
}

impl RunVerdict {
    /// The process exit code for this verdict.
    #[must_use]
    pub const fn exit_code(self) -> u8 {
        match self {
            Self::Pass => EXIT_PASS,
            Self::Drift => EXIT_DRIFT,
        }
    }

    /// Combine two verdicts: DRIFT is sticky across an aggregate run.
    #[must_use]
    pub const fn merge(self, other: Self) -> Self {
        match (self, other) {
            (Self::Pass, Self::Pass) => Self::Pass,
            _ => Self::Drift,
        }
    }
}

impl fmt::Display for RunVerdict {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Pass => "pass",
            Self::Drift => "drift",
        })
    }
}

/// The verdict recorded for one plan entry in the run summary JSON.
///
/// Serializes lowercase, so the strings a consumer's CI already greps for
/// (`"pass"`, `"fail"`, `"skipped"`, `"composed"`) are unchanged; `"drift"` is
/// the new one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SampleStatus {
    /// Every scenario in the sample passed.
    Pass,
    /// At least one scenario failed.
    Fail,
    /// No scenario failed and at least one drifted.
    Drift,
    /// The plan entry declared `skip: true`.
    Skipped,
    /// `--compose-only`: the tree was built and nothing was replayed.
    Composed,
}

impl From<RunVerdict> for SampleStatus {
    fn from(verdict: RunVerdict) -> Self {
        match verdict {
            RunVerdict::Pass => Self::Pass,
            RunVerdict::Drift => Self::Drift,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drift_is_sticky_across_an_aggregate() {
        assert_eq!(RunVerdict::Pass.merge(RunVerdict::Pass), RunVerdict::Pass);
        assert_eq!(RunVerdict::Pass.merge(RunVerdict::Drift), RunVerdict::Drift);
        assert_eq!(RunVerdict::Drift.merge(RunVerdict::Pass), RunVerdict::Drift);
    }

    /// The three states must be distinguishable by exit code alone — a CI lane
    /// that cannot tell DRIFT from FAIL has no way to gate on it.
    #[test]
    fn the_three_verdicts_have_three_distinct_exit_codes() {
        assert_eq!(RunVerdict::Pass.exit_code(), EXIT_PASS);
        assert_eq!(RunVerdict::Drift.exit_code(), EXIT_DRIFT);
        assert_ne!(EXIT_PASS, EXIT_FAIL);
        assert_ne!(EXIT_FAIL, EXIT_DRIFT);
        assert_ne!(EXIT_PASS, EXIT_DRIFT);
    }

    #[test]
    fn sample_status_serializes_lowercase() -> Result<(), serde_json::Error> {
        assert_eq!(serde_json::to_string(&SampleStatus::Pass)?, "\"pass\"");
        assert_eq!(serde_json::to_string(&SampleStatus::Fail)?, "\"fail\"");
        assert_eq!(serde_json::to_string(&SampleStatus::Drift)?, "\"drift\"");
        assert_eq!(
            serde_json::to_string(&SampleStatus::Skipped)?,
            "\"skipped\""
        );
        assert_eq!(
            serde_json::to_string(&SampleStatus::Composed)?,
            "\"composed\""
        );
        Ok(())
    }
}

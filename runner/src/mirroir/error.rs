// ABOUTME: Structured error type for the `.mirroir/` consumer pipeline — discovery, resolve, lock, compose.
// ABOUTME: Converts into RunnerError via #[from]; every variant carries the fields its message needs.

use std::io;
use std::path::PathBuf;

use thiserror::Error;

/// Errors raised while driving a consumer repository's `.mirroir/` plan.
///
/// The `.mirroir/` pipeline — config discovery, archetype resolution, lockfile
/// freshness, compose, plan aggregation — owns this enum so
/// [`crate::error::RunnerError`] stays the runner-wide surface. Every variant
/// converts into [`crate::error::RunnerError::Mirroir`] through `#[from]`, so
/// `?` propagates them unchanged.
#[derive(Debug, Error)]
pub enum MirroirError {
    /// An archetype reference in `mirroir.yaml` could not be parsed.
    ///
    /// Valid forms: `<pack>/<name>[@<version>]`, `./<path>`, `user/<name>[@<version>]`.
    /// Bare `<name>` refs are rejected to eliminate pack/user collision ambiguity.
    #[error("invalid archetype reference `{value}`: {reason}")]
    InvalidArchetypeRef {
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
    CompositionUnsupported {
        /// `name` field of the offending plan entry.
        entry_name: String,
        /// Number of archetypes declared.
        count: usize,
    },

    /// A plan entry has both `archetypes:` and `local:` set, or neither.
    /// Exactly one is required.
    #[error("plan entry `{entry_name}`: {reason}")]
    PlanEntryAmbiguous {
        /// `name` field of the offending plan entry.
        entry_name: String,
        /// "both archetypes and local set" or "neither archetypes nor local set".
        reason: String,
    },

    /// `mirroir-run` walked from `searched_from` to the filesystem root and
    /// never found a `.mirroir/mirroir.yaml`. Run inside a consumer repo, or
    /// pass `--config <PATH>` explicitly.
    #[error("no `.mirroir/mirroir.yaml` found walking up from `{searched_from}`")]
    ConfigNotFound {
        /// Starting directory of the walk.
        searched_from: PathBuf,
    },

    /// An archetype reference could not be resolved to a directory on disk.
    #[error("archetype `{reference}` not found (searched: {searched:?})")]
    ArchetypeNotFound {
        /// The reference string from `mirroir.yaml`.
        reference: String,
        /// Directories the resolver inspected.
        searched: Vec<PathBuf>,
    },

    /// A plan entry referenced a local sample that doesn't exist on disk.
    #[error("plan entry `{sample}` declared `local: {expected_path}` but the path does not exist")]
    SampleMissing {
        /// Plan entry name.
        sample: String,
        /// The resolved path that was missing.
        expected_path: PathBuf,
    },

    /// At least one sample in a `mirroir-run` invocation reported failures.
    #[error("mirroir plan: {failed} of {total} samples failed")]
    PlanFailures {
        /// Number of failed samples.
        failed: usize,
        /// Total samples attempted.
        total: usize,
    },

    /// The composed `.build/<sample>/` could not be built for the named sample.
    #[error("compose failed for sample `{sample}`: {context}")]
    ComposeFailed {
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
    LockfileStale {
        /// What drifted (ref added, ref removed, version changed, …).
        reason: String,
    },

    /// `--frozen` mode requires the lockfile to be present and not require
    /// network fetch; one of those conditions was violated.
    #[error("frozen mode violation: {reason}")]
    FrozenViolation {
        /// What violated the frozen invariant.
        reason: String,
    },

    /// `mirroir.lock` was expected but is missing. Run `mirroir-run` without
    /// `--locked` to regenerate, or commit a lockfile.
    #[error("mirroir.lock not found at `{path}` (required by --locked)")]
    LockfileMissing {
        /// Where the lockfile was expected.
        path: PathBuf,
    },

    /// `HOME` environment variable is not set; can't locate `~/.mirroir/`.
    #[error("cannot resolve user home directory ($HOME is unset)")]
    HomeDirUnavailable,
}

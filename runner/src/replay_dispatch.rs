// ABOUTME: Judge / drift / cross_surface step dispatch helpers for scenario replay.
// ABOUTME: Resolves response sources, runs the judge registry, and enforces drift / similarity verdicts.

use std::fs;

use tempfile::{Builder, NamedTempFile};
use tracing::info;

use crate::compile::playwright::ResponseCapture;
use crate::error::{Result, RunnerError};
use crate::oracle::drift::{DriftVerdict, Fingerprint, detect_drift, jaccard_similarity};
use crate::oracle::judge::{JudgeRegistry, enforce_threshold, run_judge};
use crate::parser::step::{CrossSurfaceArgs, JudgeArgs, SkillStep};
use crate::replay::ReplayOptions;

/// Dispatch a `cross_surface:` step: read every response file and fail on the
/// first pair whose Jaccard similarity falls below the configured threshold.
///
/// # Errors
///
/// * [`RunnerError::CrossSurfaceTooFewFiles`] when fewer than two files are listed.
/// * [`RunnerError::CrossSurfaceCaptureTargetNotListed`] when a `capture.to` is
///   not one of the compared files.
/// * [`RunnerError::Io`] when a response file can't be read.
/// * [`RunnerError::CrossSurfaceMismatch`] when a pair falls below threshold.
pub fn dispatch_cross_surface(args: &CrossSurfaceArgs) -> Result<()> {
    if args.response_files.len() < 2 {
        return Err(RunnerError::CrossSurfaceTooFewFiles {
            count: args.response_files.len(),
        });
    }
    // Checked before any file is read: a capture aimed outside the compared set
    // leaves its text unread, and the comparison silently falls back to whatever
    // sits at the listed path — a stale baseline from an earlier run passes.
    if let Some(capture) = args.capture.as_ref()
        && !args.response_files.contains(&capture.to)
    {
        return Err(RunnerError::CrossSurfaceCaptureTargetNotListed {
            to: capture.to.clone(),
            response_files: args.response_files.clone(),
        });
    }
    let threshold = args.min_similarity.unwrap_or(0.7);
    let mut bodies: Vec<(String, String)> = Vec::with_capacity(args.response_files.len());
    for path in &args.response_files {
        let body = fs::read_to_string(path).map_err(|source| RunnerError::Io {
            context: format!("read cross_surface.response_files entry `{path}`"),
            source,
        })?;
        bodies.push((path.clone(), body));
    }

    // Compute pairwise Jaccard similarity. Fail on the first pair below threshold.
    for i in 0..bodies.len() {
        for j in (i + 1)..bodies.len() {
            let fp_a = Fingerprint::of(&bodies[i].1);
            let fp_b = Fingerprint::of(&bodies[j].1);
            let sim = jaccard_similarity(&fp_a, &fp_b);
            info!(
                a = %bodies[i].0,
                b = %bodies[j].0,
                similarity = sim,
                threshold,
                "cross_surface pairwise check"
            );
            if sim < threshold {
                return Err(RunnerError::CrossSurfaceMismatch {
                    a: bodies[i].0.clone(),
                    b: bodies[j].0.clone(),
                    observed: sim,
                    threshold,
                });
            }
        }
    }
    info!(
        files = args.response_files.len(),
        threshold, "cross_surface: all pairs above threshold"
    );
    Ok(())
}

/// If `step` is a `judge:` whose response must be scraped from the DOM (it has
/// a `response_selector` but no inline `response_text`/`response_file`) and a
/// web batch is pending to scrape from, create a temp file and a matching
/// [`ResponseCapture`]. Returns `None` (no capture) under `--no-playwright` or
/// when there is nothing to scrape. The returned [`NamedTempFile`] must outlive
/// the judge dispatch so the scraped file isn't deleted before it is read.
///
/// # Errors
///
/// * [`RunnerError::Io`] when the temp capture file can't be created.
pub fn judge_capture_file(
    step: &SkillStep,
    web_buffer: &[SkillStep],
    options: ReplayOptions,
) -> Result<Option<(NamedTempFile, ResponseCapture)>> {
    let SkillStep::Judge(args) = step else {
        return Ok(None);
    };
    if options.skip_playwright
        || web_buffer.is_empty()
        || args.response_text.is_some()
        || args.response_file.is_some()
        || args.response_selector.trim().is_empty()
    {
        return Ok(None);
    }
    let tmp = Builder::new()
        .prefix("mirroir-judge-response-")
        .suffix(".txt")
        .tempfile()
        .map_err(|source| RunnerError::Io {
            context: "create temp file for judge response capture".to_owned(),
            source,
        })?;
    let capture = ResponseCapture {
        selector: args.response_selector.clone(),
        out_path: tmp.path().display().to_string(),
    };
    Ok(Some((tmp, capture)))
}

/// If `step` is a `cross_surface:` with a `capture` and a web batch is pending,
/// build a [`ResponseCapture`] that scrapes the capture selector's text into the
/// capture's `to` path — the persistent web baseline the equivalence check then
/// reads. Returns `None` under `--no-playwright`, with no pending web batch, or
/// when the step has no `capture`. Unlike the judge capture this targets a real
/// file (not a temp), so no handle needs to outlive the call.
#[must_use]
pub fn cross_surface_capture(
    step: &SkillStep,
    web_buffer: &[SkillStep],
    options: ReplayOptions,
) -> Option<ResponseCapture> {
    let SkillStep::CrossSurface(args) = step else {
        return None;
    };
    let capture = args.capture.as_ref()?;
    if options.skip_playwright || web_buffer.is_empty() || capture.selector.trim().is_empty() {
        return None;
    }
    Some(ResponseCapture {
        selector: capture.selector.clone(),
        out_path: capture.to.clone(),
    })
}

/// Dispatch a `judge:` step: load the response, run the judge registry,
/// enforce the pass threshold, and optionally run drift detection against a
/// baseline file.
///
/// # Errors
///
/// * [`RunnerError::JudgeDecode`] when no response source is set.
/// * [`RunnerError::Io`] when a response or baseline file can't be read.
/// * Any error from judge registry loading, judging, threshold enforcement.
/// * [`RunnerError::DriftDetected`] when drift is observed against the baseline.
pub async fn dispatch_judge(args: &JudgeArgs) -> Result<()> {
    let response = load_response_text(args)?;
    let registry = JudgeRegistry::load_from_cwd()?;
    let outcome = run_judge(&registry, args, &response).await?;
    enforce_threshold(&args.profile, args, &outcome)?;
    info!(
        profile = %args.profile,
        score = outcome.score,
        pass_threshold = args.pass_threshold,
        "judge passed"
    );

    // Optional drift detection if a baseline file is provided.
    if let Some(drift_config) = &args.response_drift
        && let Some(baseline_path) = args.drift_baseline_file.as_deref()
    {
        let baseline = fs::read_to_string(baseline_path).map_err(|source| RunnerError::Io {
            context: format!("read drift baseline {baseline_path}"),
            source,
        })?;
        match detect_drift(&baseline, &response, drift_config) {
            DriftVerdict::Match {
                fingerprint_similarity,
                levenshtein_pct,
            } => info!(
                fingerprint_similarity,
                levenshtein_pct, "drift check: MATCH"
            ),
            DriftVerdict::Drift { reason, .. } => {
                return Err(RunnerError::DriftDetected { reason });
            }
        }
    }
    Ok(())
}

fn load_response_text(args: &JudgeArgs) -> Result<String> {
    if let Some(text) = &args.response_text {
        return Ok(text.clone());
    }
    if let Some(path) = &args.response_file {
        return fs::read_to_string(path).map_err(|source| RunnerError::Io {
            context: format!("read judge.response_file {path}"),
            source,
        });
    }
    Err(RunnerError::JudgeDecode {
        reason: "no response source: set response_text or response_file".to_owned(),
    })
}

#[cfg(test)]
mod tests {
    use std::result::Result as StdResult;

    use serde_yaml::from_str;
    use tempfile::tempdir;

    use super::*;
    use crate::parser::step_args::{CrossSurfaceArgs, CrossSurfaceCapture};

    type TestResult = StdResult<(), String>;

    fn cross_surface(capture: Option<CrossSurfaceCapture>) -> SkillStep {
        SkillStep::CrossSurface(CrossSurfaceArgs {
            response_files: vec!["a.txt".to_owned(), "b.txt".to_owned()],
            min_similarity: Some(0.5),
            capture,
        })
    }

    #[test]
    fn capture_emitted_with_pending_web_batch() -> TestResult {
        let step = cross_surface(Some(CrossSurfaceCapture {
            selector: "main".to_owned(),
            to: "/tmp/b.web.txt".to_owned(),
        }));
        let web_buffer = vec![SkillStep::Tap("Go".to_owned())];
        let Some(cap) = cross_surface_capture(&step, &web_buffer, ReplayOptions::default()) else {
            return Err("expected a capture".to_owned());
        };
        if cap.selector != "main" || cap.out_path != "/tmp/b.web.txt" {
            return Err(format!("wrong capture: {cap:?}"));
        }
        Ok(())
    }

    #[test]
    fn no_capture_when_empty_batch_missing_field_or_skip_playwright() {
        let with_cap = cross_surface(Some(CrossSurfaceCapture {
            selector: "main".to_owned(),
            to: "b.txt".to_owned(),
        }));
        let buffer = vec![SkillStep::Tap("Go".to_owned())];
        // Empty web batch → nothing to scrape.
        assert!(cross_surface_capture(&with_cap, &[], ReplayOptions::default()).is_none());
        // No capture field → no capture.
        assert!(
            cross_surface_capture(&cross_surface(None), &buffer, ReplayOptions::default())
                .is_none()
        );
        // --no-playwright disables the scrape.
        let skip = ReplayOptions {
            skip_playwright: true,
        };
        assert!(cross_surface_capture(&with_cap, &buffer, skip).is_none());
    }

    #[test]
    fn capture_target_outside_response_files_is_rejected() -> TestResult {
        // Typo: the capture writes `b.web.txt`, the step compares `b.txt`. The
        // scraped text would go unread and `b.txt` — stale or missing — would be
        // compared in its place.
        let SkillStep::CrossSurface(args) = cross_surface(Some(CrossSurfaceCapture {
            selector: "main".to_owned(),
            to: "b.web.txt".to_owned(),
        })) else {
            return Err("expected a cross_surface step".to_owned());
        };
        match dispatch_cross_surface(&args) {
            Err(RunnerError::CrossSurfaceCaptureTargetNotListed { to, response_files }) => {
                if to != "b.web.txt" || !response_files.contains(&"b.txt".to_owned()) {
                    return Err(format!("wrong error payload: {to} / {response_files:?}"));
                }
                Ok(())
            }
            other => Err(format!("expected capture-target error, got {other:?}")),
        }
    }

    #[test]
    fn capture_target_listed_in_response_files_is_accepted() -> TestResult {
        // The valid form must still reach the comparison: identical bodies pass.
        let dir = tempdir().map_err(|e| e.to_string())?;
        let a = dir.path().join("a.txt");
        let b = dir.path().join("b.txt");
        for path in [&a, &b] {
            fs::write(path, "same body text").map_err(|e| e.to_string())?;
        }
        let b_path = b.display().to_string();
        let args = CrossSurfaceArgs {
            response_files: vec![a.display().to_string(), b_path.clone()],
            min_similarity: Some(0.5),
            capture: Some(CrossSurfaceCapture {
                selector: "main".to_owned(),
                to: b_path,
            }),
        };
        dispatch_cross_surface(&args).map_err(|e| format!("valid capture rejected: {e}"))
    }

    #[test]
    fn capture_field_parses_and_is_optional() -> TestResult {
        let with: CrossSurfaceArgs = from_str(
            "response_files: [a.txt, b.txt]\nmin_similarity: 0.5\ncapture:\n  selector: main\n  to: b.txt\n",
        )
        .map_err(|e| e.to_string())?;
        match with.capture {
            Some(c) if c.selector == "main" && c.to == "b.txt" => {}
            other => return Err(format!("capture not parsed: {other:?}")),
        }
        // Backward compatible: scenarios without capture still parse.
        let without: CrossSurfaceArgs =
            from_str("response_files: [a.txt, b.txt]\n").map_err(|e| e.to_string())?;
        if without.capture.is_some() {
            return Err("capture should default to None".to_owned());
        }
        Ok(())
    }
}

// ABOUTME: `cross_surface:` step dispatch — write the web capture, then compare every surface pairwise.
// ABOUTME: Accept mode regenerates the capture and reports the surfaces this runner does not drive.

use std::fs;
use std::path::Path;

use tracing::{info, warn};

use crate::compile::report::PlaywrightCaptures;
use crate::error::{Result, RunnerError};
use crate::oracle::baseline::BaselineMode;
use crate::oracle::drift::{Fingerprint, jaccard_similarity};
use crate::parser::step::CrossSurfaceArgs;

/// Dispatch a `cross_surface:` step: materialise the web baseline from the
/// invocation's captures when the step declares one, then read every response
/// file and fail on the first pair whose Jaccard similarity falls below the
/// configured threshold.
///
/// `index` is the step's position in the scenario — the key the compiled spec
/// filed its capture under.
///
/// In [`BaselineMode::Accept`] the capture is still written — that write *is*
/// the regeneration of the web surface's baseline — and the pairwise
/// similarities are reported rather than enforced. The other listed files are
/// surfaces this runner does not drive: `baselines/<flow>.ios.txt` is written
/// by mirroir-mcp's `generate_skill` against a connected iPhone, so accept
/// names each one it left alone instead of overwriting it with web text, which
/// would turn the parity oracle into a tautology.
///
/// # Errors
///
/// * [`RunnerError::CrossSurfaceTooFewFiles`] when fewer than two files are listed.
/// * [`RunnerError::CrossSurfaceCaptureTargetNotListed`] when a `capture.to` is
///   not one of the compared files.
/// * [`RunnerError::CrossSurfaceNotCaptured`] when a declared capture carries
///   no text in the `mirroir-captures` attachment.
/// * [`RunnerError::Io`] when a response file can't be read or the capture
///   can't be written.
/// * [`RunnerError::CrossSurfaceEmptySurface`] when a listed file carries no
///   comparable text, in either baseline mode.
/// * [`RunnerError::CrossSurfaceMismatch`] when a pair falls below threshold
///   in [`BaselineMode::Compare`].
pub fn dispatch_cross_surface(
    index: usize,
    args: &CrossSurfaceArgs,
    captures: &PlaywrightCaptures,
    baselines: BaselineMode,
) -> Result<()> {
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
    // The web baseline, when the step declares one, arrives on the
    // `mirroir-captures` attachment and is written to its `to` path here —
    // that file is one of the compared surfaces.
    if let Some(capture) = args.capture.as_ref() {
        let Some(text) = captures.cross_surface.get(&index.to_string()) else {
            return Err(RunnerError::CrossSurfaceNotCaptured {
                index,
                to: capture.to.clone(),
            });
        };
        fs::write(&capture.to, text).map_err(|source| RunnerError::Io {
            context: format!("write cross_surface capture to `{}`", capture.to),
            source,
        })?;
        info!(index, to = %capture.to, bytes = text.len(), "cross_surface capture written");
    }

    if baselines == BaselineMode::Accept {
        report_surfaces_accept_cannot_regenerate(args);
    }

    let threshold = args.min_similarity;
    let mut surfaces: Vec<(String, Fingerprint)> = Vec::with_capacity(args.response_files.len());
    for path in &args.response_files {
        let body = fs::read_to_string(path).map_err(|source| RunnerError::Io {
            context: format!("read cross_surface.response_files entry `{path}`"),
            source,
        })?;
        // Rejected before any pair is scored, in both baseline modes: Jaccard
        // reads two empty token sets as identical — the right answer for drift
        // against a recorded baseline, and a free pass here. An iOS capture of a
        // screen that yielded no OCR text is a lone newline, so the empty
        // surface is a real arrival, not a hypothetical one, and accepting it
        // would bless a gate that can never fail.
        let fingerprint = Fingerprint::of(&body);
        if fingerprint.is_empty() {
            return Err(RunnerError::CrossSurfaceEmptySurface { path: path.clone() });
        }
        surfaces.push((path.clone(), fingerprint));
    }

    // Compute pairwise Jaccard similarity. Fail on the first pair below threshold.
    for i in 0..surfaces.len() {
        for j in (i + 1)..surfaces.len() {
            let sim = jaccard_similarity(&surfaces[i].1, &surfaces[j].1);
            info!(
                a = %surfaces[i].0,
                b = %surfaces[j].0,
                similarity = sim,
                threshold,
                "cross_surface pairwise check"
            );
            if sim < threshold {
                if baselines == BaselineMode::Accept {
                    // Accept regenerates what it can reach and reports the rest:
                    // a pair still below threshold means a surface accept does
                    // not drive has to be re-captured, and the next ordinary run
                    // fails on it.
                    warn!(
                        a = %surfaces[i].0,
                        b = %surfaces[j].0,
                        similarity = sim,
                        threshold,
                        "cross_surface pair is still below threshold after accept"
                    );
                    continue;
                }
                return Err(RunnerError::CrossSurfaceMismatch {
                    a: surfaces[i].0.clone(),
                    b: surfaces[j].0.clone(),
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

/// Name every compared surface `accept` did not write, so the human knows which
/// baselines still have to come from somewhere else.
///
/// The runner drives web (Playwright), process and HTTP targets. An iOS
/// baseline is produced by mirroir-mcp's `generate_skill` against a connected
/// iPhone and lands in the same `.mirroir/apps/<slug>/baselines/` directory; a
/// hand-authored fixture is a checked-in file. Either way it is not this
/// process's to regenerate.
fn report_surfaces_accept_cannot_regenerate(args: &CrossSurfaceArgs) {
    let written = args.capture.as_ref().map(|capture| capture.to.as_str());
    for path in &args.response_files {
        if Some(path.as_str()) == written {
            continue;
        }
        let present = Path::new(path).is_file();
        warn!(
            file = %path,
            present,
            "accept left this cross_surface baseline alone: it is written by the surface that owns it (an iOS capture comes from `generate_skill`)"
        );
    }
}

#[cfg(test)]
mod tests {
    use std::result::Result as StdResult;

    use serde_yaml::from_str;
    use tempfile::tempdir;

    use super::*;
    use crate::parser::step_args::CrossSurfaceCapture;

    type TestResult = StdResult<(), String>;

    fn captures_with_cross_surface(index: usize, text: &str) -> PlaywrightCaptures {
        let mut captures = PlaywrightCaptures::default();
        captures
            .cross_surface
            .insert(index.to_string(), text.to_owned());
        captures
    }

    #[test]
    fn capture_target_outside_response_files_is_rejected() -> TestResult {
        // Typo: the capture writes `b.web.txt`, the step compares `b.txt`. The
        // scraped text would go unread and `b.txt` — stale or missing — would be
        // compared in its place.
        let args = CrossSurfaceArgs {
            response_files: vec!["a.txt".to_owned(), "b.txt".to_owned()],
            min_similarity: 0.5,
            capture: Some(CrossSurfaceCapture {
                selector: "main".to_owned(),
                to: "b.web.txt".to_owned(),
            }),
        };
        match dispatch_cross_surface(
            2,
            &args,
            &captures_with_cross_surface(2, "text"),
            BaselineMode::Compare,
        ) {
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
    fn declared_capture_missing_from_the_attachment_is_rejected() -> TestResult {
        let args = CrossSurfaceArgs {
            response_files: vec!["a.txt".to_owned(), "b.txt".to_owned()],
            min_similarity: 0.5,
            capture: Some(CrossSurfaceCapture {
                selector: "main".to_owned(),
                to: "b.txt".to_owned(),
            }),
        };
        match dispatch_cross_surface(
            4,
            &args,
            &PlaywrightCaptures::default(),
            BaselineMode::Compare,
        ) {
            Err(RunnerError::CrossSurfaceNotCaptured { index, to }) => {
                if index != 4 || to != "b.txt" {
                    return Err(format!("wrong payload: index={index} to={to}"));
                }
                Ok(())
            }
            other => Err(format!("expected CrossSurfaceNotCaptured, got {other:?}")),
        }
    }

    #[test]
    fn attachment_capture_is_written_and_compared() -> TestResult {
        let dir = tempdir().map_err(|e| e.to_string())?;
        let a = dir.path().join("a.txt");
        let b = dir.path().join("b.txt");
        fs::write(&a, "the shared answer text").map_err(|e| e.to_string())?;
        let b_path = b.display().to_string();
        let args = CrossSurfaceArgs {
            response_files: vec![a.display().to_string(), b_path.clone()],
            min_similarity: 0.5,
            capture: Some(CrossSurfaceCapture {
                selector: "main".to_owned(),
                to: b_path,
            }),
        };
        // `b.txt` does not exist yet: only the attachment can produce it.
        dispatch_cross_surface(
            1,
            &args,
            &captures_with_cross_surface(1, "the shared answer text"),
            BaselineMode::Compare,
        )
        .map_err(|e| format!("valid capture rejected: {e}"))?;
        let written = fs::read_to_string(&b).map_err(|e| e.to_string())?;
        if written != "the shared answer text" {
            return Err(format!("capture not written: {written}"));
        }
        Ok(())
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
        // Scenarios that supply their own baselines still parse.
        let without: CrossSurfaceArgs =
            from_str("response_files: [a.txt, b.txt]\nmin_similarity: 0.5\n")
                .map_err(|e| e.to_string())?;
        if without.capture.is_some() {
            return Err("capture should default to None".to_owned());
        }
        Ok(())
    }

    #[test]
    fn a_step_without_min_similarity_does_not_parse() -> TestResult {
        // The threshold is the gate: no default stands in for one the scenario
        // never declared.
        match from_str::<CrossSurfaceArgs>("response_files: [a.txt, b.txt]\n") {
            Err(e) if e.to_string().contains("min_similarity") => Ok(()),
            Err(e) => Err(format!("rejected for the wrong reason: {e}")),
            Ok(args) => Err(format!("an undeclared threshold parsed: {args:?}")),
        }
    }
}

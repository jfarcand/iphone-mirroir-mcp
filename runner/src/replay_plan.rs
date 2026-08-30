// ABOUTME: Builds one scenario's execution plan — pre-hooks, the single web block, post-hooks.
// ABOUTME: Rejects a scenario whose web steps are split, because a scenario compiles to one invocation.

use std::ops::Range;

use crate::error::{Result, RunnerError};
use crate::parser::step::SkillStep;
use crate::parser::surface::{is_annotation, is_web, step_kind};

/// How one scenario executes.
///
/// A scenario compiles to exactly one `npx playwright test` invocation, so its
/// web steps must form a single adjacent run. Everything before that run
/// executes as a pre-hook; everything after it as a post-hook, reading the
/// values the invocation attached.
///
/// A scenario with no web steps has an empty [`Self::web`] and runs entirely
/// as pre-hooks, in file order.
///
/// Annotation steps (`remember:`) are transparent to the partition: one
/// between two web steps rides along inside the block, and one anywhere else
/// is a hook like any other runner-side step.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScenarioPlan {
    pre: Vec<usize>,
    web: Option<Range<usize>>,
    post: Vec<usize>,
}

impl ScenarioPlan {
    /// Partition `steps` into pre-hooks, the web block, and post-hooks.
    ///
    /// # Errors
    ///
    /// [`RunnerError::WebBlockNotContiguous`] when a web step follows a
    /// runner-side step that already ended the scenario's web run. Re-entering
    /// the browser would mean a second invocation with a fresh context —
    /// cookies, storage, auth and in-memory state silently discarded — so the
    /// shape is rejected instead of quietly reordered.
    pub fn build(steps: &[SkillStep]) -> Result<Self> {
        let Some(start) = steps.iter().position(is_web) else {
            return Ok(Self {
                pre: (0..steps.len()).collect(),
                web: None,
                post: Vec::new(),
            });
        };
        // The web run ends at the first step that actually executes on the
        // runner side. An annotation executes nowhere, so it does not end it.
        let separator = steps[start..]
            .iter()
            .position(|step| !is_web(step) && !is_annotation(step))
            .map_or(steps.len(), |offset| start + offset);
        // Trailing annotations are not part of the invocation: the block stops
        // at its last web step and they run as post-hooks.
        let end = steps[start..separator]
            .iter()
            .rposition(is_web)
            .map_or(separator, |offset| start + offset + 1);

        for (offset, step) in steps[separator..].iter().enumerate() {
            if is_web(step) {
                let index = separator + offset;
                return Err(RunnerError::WebBlockNotContiguous {
                    index,
                    kind: step_kind(step),
                    block_end: end - 1,
                    separator_kind: step_kind(&steps[separator]),
                });
            }
        }

        Ok(Self {
            pre: (0..start).collect(),
            web: Some(start..end),
            post: (end..steps.len()).collect(),
        })
    }

    /// Indices of the runner-side steps that execute before the invocation.
    #[must_use]
    pub fn pre(&self) -> &[usize] {
        &self.pre
    }

    /// Indices of the runner-side steps that execute after the invocation.
    #[must_use]
    pub fn post(&self) -> &[usize] {
        &self.post
    }

    /// The scenario's single web block, if it has one.
    #[must_use]
    pub fn web(&self) -> Option<Range<usize>> {
        self.web.clone()
    }
}

#[cfg(test)]
mod tests {
    use std::result::Result as StdResult;

    use serde_yaml::Deserializer;
    use serde_yaml::with::singleton_map_recursive;

    use super::ScenarioPlan;
    use crate::error::RunnerError;
    use crate::parser::scenario::Scenario;

    type TestResult = StdResult<(), String>;

    fn steps(yaml: &str) -> StdResult<Scenario, String> {
        singleton_map_recursive::deserialize(Deserializer::from_str(yaml))
            .map_err(|e| format!("parse: {e}"))
    }

    #[test]
    fn contiguous_scenario_splits_into_pre_web_post() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: contiguous
steps:
  - spawn: { id: s, command: "echo hi" }
  - target: { kind: web, url: "http://x/" }
  - tap: "Go"
  - http: { method: GET, url: "http://x/" }
  - kill: { id: s }
"#,
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        assert_eq!(plan.pre(), &[0]);
        assert_eq!(plan.web(), Some(1..3));
        assert_eq!(plan.post(), &[3, 4]);
        Ok(())
    }

    #[test]
    fn scenario_without_web_steps_is_all_pre_hooks() -> TestResult {
        let scenario = steps(
            "version: 1\nname: no-web\nsteps:\n  - http: { method: GET, url: \"http://x/\" }\n  - report: pass\n",
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        assert_eq!(plan.pre(), &[0, 1]);
        assert_eq!(plan.web(), None);
        assert!(plan.post().is_empty());
        Ok(())
    }

    #[test]
    fn split_web_block_is_rejected_naming_the_offending_step() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: split
steps:
  - target: { kind: web, url: "http://x/" }
  - assert_visible: "Dashboard"
  - http: { method: GET, url: "http://x/" }
  - tap: "Settings"
"#,
        )?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::WebBlockNotContiguous {
                index,
                kind,
                block_end,
                separator_kind,
            }) => {
                if index != 3 || kind != "tap" || block_end != 1 || separator_kind != "http" {
                    return Err(format!(
                        "wrong payload: index={index} kind={kind} block_end={block_end} separator_kind={separator_kind}"
                    ));
                }
                Ok(())
            }
            other => Err(format!("expected WebBlockNotContiguous, got {other:?}")),
        }
    }

    /// `remember:` records a note; it drives no browser, so a trailing one is
    /// not a web step resuming after the block. The design's own canonical
    /// scenario ends this way — `http` → `kill` → `assert_log_clean` →
    /// `remember` — and the partition must accept it.
    #[test]
    fn a_trailing_remember_does_not_split_the_web_block() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: trailing remember
steps:
  - spawn: { id: s, command: "echo hi" }
  - target: { kind: web, url: "http://x/" }
  - assert_visible: "Dashboard"
  - http: { method: GET, url: "http://x/" }
  - kill: { id: s }
  - remember: "Verified streaming reply over preferred transport"
"#,
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        assert_eq!(plan.pre(), &[0]);
        assert_eq!(plan.web(), Some(1..3));
        // The note is dispatched on the runner side, after the invocation.
        assert_eq!(plan.post(), &[3, 4, 5]);
        Ok(())
    }

    /// A note between two web steps rides along inside the block rather than
    /// cutting it in two: the emitted spec carries it as a comment at its own
    /// position, and the invocation stays single.
    #[test]
    fn a_remember_inside_the_web_run_keeps_the_block_whole() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: interior remember
steps:
  - target: { kind: web, url: "http://x/" }
  - remember: "the console shows the connected badge"
  - assert_visible: "Dashboard"
  - http: { method: GET, url: "http://x/" }
"#,
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        assert!(plan.pre().is_empty());
        assert_eq!(plan.web(), Some(0..3));
        assert_eq!(plan.post(), &[3]);
        Ok(())
    }

    /// A note before the first web step is a pre-hook — it cannot be part of a
    /// block that has not started.
    #[test]
    fn a_leading_remember_runs_as_a_pre_hook() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: leading remember
steps:
  - remember: "starting from a signed-out browser"
  - target: { kind: web, url: "http://x/" }
  - assert_visible: "Sign in"
"#,
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        assert_eq!(plan.pre(), &[0]);
        assert_eq!(plan.web(), Some(1..3));
        assert!(plan.post().is_empty());
        Ok(())
    }

    /// A `screenshot:` needs the live page, so it stays a web step: a trailing
    /// one after the block is still rejected, and the note that sits beside it
    /// does not launder it through.
    #[test]
    fn a_remember_does_not_launder_a_trailing_screenshot() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: screenshot after the block
steps:
  - target: { kind: web, url: "http://x/" }
  - assert_visible: "Dashboard"
  - kill: { id: s }
  - remember: "server is down"
  - screenshot: "after"
"#,
        )?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::WebBlockNotContiguous {
                index,
                kind,
                block_end,
                separator_kind,
            }) => {
                if index != 4 || kind != "screenshot" || block_end != 1 || separator_kind != "kill"
                {
                    return Err(format!(
                        "wrong payload: index={index} kind={kind} block_end={block_end} separator_kind={separator_kind}"
                    ));
                }
                Ok(())
            }
            other => Err(format!("expected WebBlockNotContiguous, got {other:?}")),
        }
    }

    #[test]
    fn trailing_web_step_after_a_runner_step_is_rejected() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: trailing
steps:
  - target: { kind: web, url: "http://x/" }
  - judge:
      profile: fast-ci
      user_prompt_template_hash: "sha256:abc"
      response_selector: "[data-test=reply]"
      pass_threshold: 0.9
  - screenshot: "after"
"#,
        )?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::WebBlockNotContiguous { index, kind, .. }) => {
                if index != 2 || kind != "screenshot" {
                    return Err(format!("wrong payload: index={index} kind={kind}"));
                }
                Ok(())
            }
            other => Err(format!("expected WebBlockNotContiguous, got {other:?}")),
        }
    }
}

// ABOUTME: Builds one scenario's execution plan — pre-hooks, the single web block, post-hooks.
// ABOUTME: Rejects a scenario whose web steps are split, because a scenario compiles to one invocation.

use std::ops::Range;

use crate::error::{Result, RunnerError};
use crate::parser::step::{SkillStep, TargetArgs, TargetKind};
use crate::parser::surface::{is_annotation, is_web, step_kind};
use crate::replay_target::{no_web_target, resolve_target};

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
    /// [`RunnerError::NoExecutorForTargetKind`] when any `target:` declares a
    /// surface this binary cannot drive, [`RunnerError::SecondTargetDeclared`]
    /// when it declares its surface twice, and [`RunnerError::NoWebTarget`]
    /// when it plans web steps no `target: { kind: web }` opens. A plan
    /// nothing can execute is not a valid plan, so all three are refused here
    /// rather than deep inside the compiler, where only a run would have
    /// reached them.
    ///
    /// [`RunnerError::WebBlockNotContiguous`] when a web step follows a
    /// runner-side step that already ended the scenario's web run. Re-entering
    /// the browser would mean a second invocation with a fresh context —
    /// cookies, storage, auth and in-memory state silently discarded — so the
    /// shape is rejected instead of quietly reordered.
    pub fn build(steps: &[SkillStep]) -> Result<Self> {
        let declared = resolve_target(steps)?;
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

        // The block compiles to one Playwright invocation, so a browser has to
        // open it. A web step before the `target:` would run before the page
        // is navigated, which is why the target must be the block's first step
        // and not merely present somewhere inside it.
        let opens_the_block = matches!(
            declared,
            Some((index, target)) if index == start && target.kind == TargetKind::Web
        );
        if !opens_the_block {
            return Err(no_web_target(steps));
        }

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

    /// The `target: { kind: web }` step the web block opens with.
    ///
    /// [`Self::build`] proves the block starts there, so the compiler receives
    /// the target the plan resolved instead of scanning the scenario for one
    /// of its own — and validate and run cannot disagree about which target a
    /// file declares.
    ///
    /// # Errors
    ///
    /// [`RunnerError::NoWebTarget`] when the scenario plans no web block:
    /// there is no browser work to compile.
    pub fn web_target<'a>(&self, steps: &'a [SkillStep]) -> Result<&'a TargetArgs> {
        match self.web.as_ref().and_then(|block| steps.get(block.start)) {
            Some(SkillStep::Target(target)) => Ok(target),
            _ => Err(no_web_target(steps)),
        }
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
    use crate::parser::step::TargetKind;

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

    /// `ios` and `macos` are mirroir-mcp surfaces. The plan is what a run
    /// executes, so a scenario naming one is refused here — where the kind can
    /// be named — rather than deeper down, where the only symptom is a web
    /// block nothing compiles.
    #[test]
    fn a_target_kind_with_no_executor_is_rejected_naming_the_kind() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: ios-target
steps:
  - target: { kind: ios, app: "Expo Go" }
  - launch: "Expo Go"
  - tap: "Email"
"#,
        )?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::NoExecutorForTargetKind { index, kind }) => {
                if index != 0 || kind != TargetKind::Ios {
                    return Err(format!("wrong payload: index={index} kind={kind:?}"));
                }
                Ok(())
            }
            other => Err(format!("expected NoExecutorForTargetKind, got {other:?}")),
        }
    }

    /// Web steps compile to a Playwright invocation, which has no browser to
    /// start and no page to navigate unless a `target: { kind: web }` opens
    /// the block. A scenario that declares no target at all plans exactly that,
    /// so the plan refuses it instead of reporting a block nothing can run.
    #[test]
    fn web_steps_with_no_web_target_are_rejected() -> TestResult {
        let scenario = steps("version: 1\nname: no-target\nsteps:\n  - tap: \"Send\"\n")?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::NoWebTarget {
                first_step,
                declared,
            }) => {
                if first_step != "tap" || declared != "none" {
                    return Err(format!(
                        "wrong payload: first_step={first_step} declared={declared:?}"
                    ));
                }
                Ok(())
            }
            other => Err(format!("expected NoWebTarget, got {other:?}")),
        }
    }

    /// The `target:` opens the block: a web step before it would run before the
    /// page is navigated. Declaring the browser late is the same missing-target
    /// bug as never declaring one.
    #[test]
    fn a_web_step_before_the_target_is_rejected() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: target declared late
steps:
  - assert_visible: "Dashboard"
  - target: { kind: web, url: "http://x/" }
"#,
        )?;
        match ScenarioPlan::build(&scenario.steps) {
            Err(RunnerError::NoWebTarget {
                first_step,
                declared,
            }) => {
                if first_step != "assert_visible" || declared != "web" {
                    return Err(format!(
                        "wrong payload: first_step={first_step} declared={declared:?}"
                    ));
                }
                Ok(())
            }
            other => Err(format!("expected NoWebTarget, got {other:?}")),
        }
    }

    /// The plan resolves the target the compiler receives, so the two cannot
    /// disagree about which browser a scenario declared.
    #[test]
    fn the_plan_hands_the_compiler_the_target_that_opens_the_block() -> TestResult {
        let scenario = steps(
            r#"
version: 1
name: resolved target
steps:
  - spawn: { id: s, command: "echo hi" }
  - target: { kind: web, url: "http://x/" }
  - assert_visible: "Dashboard"
"#,
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        let target = plan
            .web_target(&scenario.steps)
            .map_err(|e| format!("web_target: {e}"))?;
        assert_eq!(target.kind, TargetKind::Web);
        assert_eq!(target.url.as_deref(), Some("http://x/"));
        Ok(())
    }

    /// A scenario with no web block has nothing to compile: asking it for a
    /// target is an error, not an empty success a caller could mistake for one.
    #[test]
    fn a_scenario_with_no_web_block_has_no_target_to_compile() -> TestResult {
        let scenario = steps(
            "version: 1\nname: no-web\nsteps:\n  - http: { method: GET, url: \"http://x/\" }\n",
        )?;
        let plan = ScenarioPlan::build(&scenario.steps).map_err(|e| format!("build: {e}"))?;
        match plan.web_target(&scenario.steps) {
            Err(RunnerError::NoWebTarget { first_step, .. }) => {
                if first_step != "http" {
                    return Err(format!("wrong payload: first_step={first_step}"));
                }
                Ok(())
            }
            other => Err(format!("expected NoWebTarget, got {:?}", other.map(|_| ()))),
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

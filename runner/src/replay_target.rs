// ABOUTME: Resolves the surface a scenario declares, and which executor — if any — this binary has for it.
// ABOUTME: The plan layer asks here first, so a plan nothing can execute never reaches a compiler or a run.

use crate::error::{Result, RunnerError};
use crate::parser::step::{SkillStep, TargetArgs};
use crate::parser::surface::step_kind;

/// Stands in for the first step's kind when the scenario declares no steps.
const NO_STEPS: &str = "<empty>";

/// Stands in for the declared surface when the scenario declares no `target:`.
const NO_TARGET: &str = "none";

/// The surface the scenario declares, with the index of the `target:` step
/// declaring it, checked against the executors this binary actually has.
///
/// Every declaration is checked, not just the opening one: a `target:` lower
/// down names a surface as loudly as the first, and the compiler emits nothing
/// for it, so a scenario that switches to the phone halfway would otherwise
/// compile the phone's steps into the browser's run.
///
/// `None` when the scenario declares no `target:` at all: a scenario of
/// `spawn:` / `http:` / `report:` steps needs no surface to run.
///
/// # Errors
///
/// [`RunnerError::NoExecutorForTargetKind`] when a declared kind names a
/// surface nothing here opens — `ios` and `macos` are mirroir-mcp's, and
/// `process` / `http` steps carry their own work.
///
/// [`RunnerError::SecondTargetDeclared`] when the scenario declares its
/// surface more than once.
pub fn resolve_target(steps: &[SkillStep]) -> Result<Option<(usize, &TargetArgs)>> {
    let mut resolved: Option<(usize, &TargetArgs)> = None;
    for (index, target) in declared_targets(steps) {
        if !target.kind.runner_executes() {
            return Err(RunnerError::NoExecutorForTargetKind {
                index,
                kind: target.kind,
            });
        }
        if let Some((first, _)) = resolved {
            return Err(RunnerError::SecondTargetDeclared { first, index });
        }
        resolved = Some((index, target));
    }
    Ok(resolved)
}

/// The error for a scenario whose web steps have no browser to run in, naming
/// what the scenario opens with and what surface it did declare.
#[must_use]
pub fn no_web_target(steps: &[SkillStep]) -> RunnerError {
    RunnerError::NoWebTarget {
        first_step: steps.first().map_or(NO_STEPS, step_kind),
        declared: declared_targets(steps)
            .next()
            .map_or(NO_TARGET, |(_, t)| t.kind.as_yaml()),
    }
}

/// The scenario's `target:` declarations, each with the index it reads at.
fn declared_targets(steps: &[SkillStep]) -> impl Iterator<Item = (usize, &TargetArgs)> {
    steps
        .iter()
        .enumerate()
        .filter_map(|(index, step)| match step {
            SkillStep::Target(target) => Some((index, target)),
            _ => None,
        })
}

#[cfg(test)]
mod tests {
    use std::result::Result as StdResult;

    use serde_yaml::Deserializer;
    use serde_yaml::with::singleton_map_recursive;

    use super::{no_web_target, resolve_target};
    use crate::error::{Result, RunnerError};
    use crate::parser::scenario::Scenario;
    use crate::parser::step::{TargetArgs, TargetKind};

    type TestResult = StdResult<(), String>;

    fn steps(yaml: &str) -> StdResult<Scenario, String> {
        singleton_map_recursive::deserialize(Deserializer::from_str(yaml))
            .map_err(|e| format!("parse: {e}"))
    }

    /// Render a resolution outcome for a failure message, keeping the borrowed
    /// `TargetArgs` out of it.
    fn show(outcome: Result<Option<(usize, &TargetArgs)>>) -> String {
        match outcome {
            Ok(declared) => format!("Ok({:?})", declared.map(|(index, t)| (index, t.kind))),
            Err(error) => format!("Err({error})"),
        }
    }

    /// `ios` names a surface only mirroir-mcp drives, so the scenario is
    /// refused where the kind can still be named.
    #[test]
    fn a_kind_with_no_executor_is_refused_with_its_index() -> TestResult {
        let scenario = steps(
            "version: 1\nname: ios\nsteps:\n  - launch: \"Acme\"\n  - target: { kind: ios, app: \"Acme\" }\n",
        )?;
        match resolve_target(&scenario.steps) {
            Err(RunnerError::NoExecutorForTargetKind { index, kind }) => {
                if index != 1 || kind != TargetKind::Ios {
                    return Err(format!("wrong payload: index={index} kind={kind:?}"));
                }
                Ok(())
            }
            other => Err(format!(
                "expected NoExecutorForTargetKind, got {}",
                show(other)
            )),
        }
    }

    /// `web` is the surface a `target:` can declare here, and a scenario may
    /// declare no surface at all — neither is an unrunnable plan.
    #[test]
    fn a_web_target_resolves_and_no_target_is_allowed() -> TestResult {
        let scenario = steps(
            "version: 1\nname: web\nsteps:\n  - target: { kind: web, url: \"http://x/\" }\n  - tap: \"Go\"\n",
        )?;
        match resolve_target(&scenario.steps) {
            Ok(Some((0, target))) if target.kind == TargetKind::Web => {}
            other => return Err(format!("web target must resolve, got {}", show(other))),
        }

        let bare = steps("version: 1\nname: bare\nsteps:\n  - report: pass\n")?;
        match resolve_target(&bare.steps) {
            Ok(None) => Ok(()),
            other => Err(format!(
                "a scenario with no target must resolve to None, got {}",
                show(other)
            )),
        }
    }

    /// Subprocess and REST work is spelled out in `spawn:` / `http:` steps,
    /// which need no `target:`. Declaring one as the scenario's surface names
    /// something no executor here opens, so it is refused by its kind — the
    /// same refusal `ios` gets, for the same reason.
    #[test]
    fn a_process_target_is_refused_naming_its_kind() -> TestResult {
        let scenario = steps(
            "version: 1\nname: process\nsteps:\n  - target: { kind: process }\n  - spawn: { id: s, command: \"echo hi\" }\n",
        )?;
        match resolve_target(&scenario.steps) {
            Err(RunnerError::NoExecutorForTargetKind { index, kind }) => {
                if index != 0 || kind != TargetKind::Process {
                    return Err(format!("wrong payload: index={index} kind={kind:?}"));
                }
                Ok(())
            }
            other => Err(format!(
                "expected NoExecutorForTargetKind, got {}",
                show(other)
            )),
        }
    }

    /// A `target:` lower down declares a surface just as loudly as the first
    /// one. Reading only the first would let a web scenario switch to the
    /// phone mid-file and compile the phone's steps into the browser run.
    #[test]
    fn a_later_declaration_with_no_executor_is_refused_at_its_own_index() -> TestResult {
        let scenario = steps(
            "version: 1\nname: web then ios\nsteps:\n  - target: { kind: web, url: \"http://x/\" }\n  - assert_visible: \"Dashboard\"\n  - target: { kind: ios, app: \"Acme\" }\n  - tap: \"Sign in\"\n",
        )?;
        match resolve_target(&scenario.steps) {
            Err(RunnerError::NoExecutorForTargetKind { index, kind }) => {
                if index != 2 || kind != TargetKind::Ios {
                    return Err(format!("wrong payload: index={index} kind={kind:?}"));
                }
                Ok(())
            }
            other => Err(format!(
                "expected NoExecutorForTargetKind, got {}",
                show(other)
            )),
        }
    }

    /// The compiler consumes the declaration the block opens with and emits
    /// nothing for a later one, so re-declaring the same surface is a step
    /// that executes nothing — refused naming both declarations.
    #[test]
    fn a_second_declaration_of_the_same_surface_is_refused() -> TestResult {
        let scenario = steps(
            "version: 1\nname: two web targets\nsteps:\n  - target: { kind: web, url: \"http://a/\" }\n  - tap: \"Go\"\n  - target: { kind: web, url: \"http://b/\" }\n",
        )?;
        match resolve_target(&scenario.steps) {
            Err(RunnerError::SecondTargetDeclared { first, index }) => {
                if first != 0 || index != 2 {
                    return Err(format!("wrong payload: first={first} index={index}"));
                }
                Ok(())
            }
            other => Err(format!(
                "expected SecondTargetDeclared, got {}",
                show(other)
            )),
        }
    }

    /// The refusal names the step the scenario opens with and the surface it
    /// declared — a browser declared too late reads differently to an author
    /// than one never declared at all.
    #[test]
    fn the_missing_browser_error_names_what_the_scenario_declared() -> TestResult {
        let scenario = steps(
            "version: 1\nname: late target\nsteps:\n  - tap: \"Go\"\n  - target: { kind: web, url: \"http://x/\" }\n",
        )?;
        match no_web_target(&scenario.steps) {
            RunnerError::NoWebTarget {
                first_step,
                declared,
            } => {
                if first_step != "tap" || declared != "web" {
                    return Err(format!(
                        "wrong payload: first_step={first_step} declared={declared:?}"
                    ));
                }
                Ok(())
            }
            other => Err(format!("expected NoWebTarget, got {other:?}")),
        }
    }
}

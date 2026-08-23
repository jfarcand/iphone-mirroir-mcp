// ABOUTME: Scenario replay orchestration — loads scenarios, dispatches steps, aggregates verdicts.
// ABOUTME: Both `--run-scenario <file>` and `--sample <dir>` modes funnel through `run_scenario_with_context`.

use std::collections::HashMap;
use std::env;
use std::fs;
use std::mem;
use std::path::Path;

use tracing::info;

use crate::compile::invoke::PlaywrightRunner;
use crate::compile::playwright::{ResponseCapture, compile_scenario_with_captures};
use crate::error::{Result, RunnerError};
use crate::parser::env::substitute;
use crate::parser::sample::{SAMPLE_SCHEMA_VERSION, SampleManifest, extract_yaml_block};
use crate::parser::scenario::{SCHEMA_VERSION, Scenario};
use crate::parser::step::{JudgeArgs, SkillStep};
use crate::replay_dispatch::{
    cross_surface_capture, dispatch_cross_surface, dispatch_judge, judge_capture_file,
};
use crate::replay_sample::resolve_spawn_args;
use crate::target::http::HttpClient;
use crate::target::process::ProcessRegistry;

pub use crate::replay_sample::{ScenarioSet, run_sample};

/// Read + env-substitute + parse a scenario YAML file with `version` gating.
///
/// `extras` is merged on top of the process environment before substitution
/// — `--sample` mode uses this to expose `${MIRROIR_SAMPLE_DIR}` without
/// touching the global process env (which would require `unsafe`).
///
/// # Errors
///
/// * [`RunnerError::Io`] when the file can't be read.
/// * [`RunnerError::RegexCompile`] when env substitution fails.
/// * [`RunnerError::YamlParse`] when YAML deserialization fails.
/// * [`RunnerError::UnsupportedVersion`] when the `version:` field is out of range.
pub fn load_scenario_with_extras(path: &Path, extras: &[(&str, String)]) -> Result<Scenario> {
    let raw = fs::read_to_string(path).map_err(|source| RunnerError::Io {
        context: format!("read scenario file {}", path.display()),
        source,
    })?;

    let mut environment: HashMap<String, String> = env::vars().collect();
    for (k, v) in extras {
        environment.insert((*k).to_owned(), v.clone());
    }
    let substituted = substitute(&raw, &environment)?;

    let scenario: Scenario =
        serde_yaml::from_str(&substituted).map_err(|source| RunnerError::YamlParse {
            file: path.display().to_string(),
            source,
        })?;

    if scenario.version != SCHEMA_VERSION {
        return Err(RunnerError::UnsupportedVersion {
            artifact: "scenario.yaml".to_owned(),
            found: scenario.version,
            expected: SCHEMA_VERSION..=SCHEMA_VERSION,
        });
    }
    Ok(scenario)
}

/// Convenience wrapper for [`load_scenario_with_extras`] with no extras —
/// used by `--validate` / `--run-scenario` / `--compile-scenario` modes.
///
/// # Errors
///
/// Same as [`load_scenario_with_extras`].
pub fn load_scenario(path: &Path) -> Result<Scenario> {
    load_scenario_with_extras(path, &[])
}

/// Read + env-substitute + parse a `SAMPLE.md` manifest, gating on its `version` field.
///
/// `extras` is merged on top of the process environment before substitution,
/// mirroring [`load_scenario_with_extras`]. The substitution runs on the
/// extracted yaml body only — markdown prose around the fenced block is left
/// untouched. This lets a SAMPLE.md declare `cwd: "${ATMOSPHERE_HOME}"` and
/// resolve it from the caller's environment at load time.
///
/// # Errors
///
/// * [`RunnerError::Io`] when the file can't be read.
/// * [`RunnerError::SampleMissingYaml`] when no fenced yaml block is present.
/// * [`RunnerError::RegexCompile`] when env substitution fails.
/// * [`RunnerError::YamlParse`] when the YAML body fails deserialization.
/// * [`RunnerError::UnsupportedVersion`] when the manifest's `version:` is out of range.
pub fn load_sample_manifest_with_extras(
    path: &Path,
    extras: &[(&str, String)],
) -> Result<SampleManifest> {
    let raw = fs::read_to_string(path).map_err(|source| RunnerError::Io {
        context: format!("read SAMPLE.md at {}", path.display()),
        source,
    })?;
    let body = extract_yaml_block(&raw).ok_or_else(|| RunnerError::SampleMissingYaml {
        path: path.display().to_string(),
    })?;

    let mut environment: HashMap<String, String> = env::vars().collect();
    for (k, v) in extras {
        environment.insert((*k).to_owned(), v.clone());
    }
    let substituted = substitute(&body, &environment)?;

    let manifest: SampleManifest =
        serde_yaml::from_str(&substituted).map_err(|source| RunnerError::YamlParse {
            file: path.display().to_string(),
            source,
        })?;
    if manifest.version != SAMPLE_SCHEMA_VERSION {
        return Err(RunnerError::UnsupportedVersion {
            artifact: "SAMPLE.md".to_owned(),
            found: manifest.version,
            expected: SAMPLE_SCHEMA_VERSION..=SAMPLE_SCHEMA_VERSION,
        });
    }
    Ok(manifest)
}

/// Convenience wrapper for [`load_sample_manifest_with_extras`] with no extras —
/// used by `--sample` mode and the `--atmosphere` dispatcher.
///
/// # Errors
///
/// Same as [`load_sample_manifest_with_extras`].
pub fn load_sample_manifest(path: &Path) -> Result<SampleManifest> {
    load_sample_manifest_with_extras(path, &[])
}

/// Bundle of the SAMPLE.md manifest + the directory it was loaded from.
///
/// Carried by [`run_scenario_with_context`] when running a sample-driven
/// replay so `from: SAMPLE.md` on a `spawn:` step can fill in defaults.
#[derive(Debug, Clone, Copy)]
pub struct SampleContext<'a> {
    /// Directory `SAMPLE.md` lives in. `cwd:` overrides resolve relative to this.
    pub sample_dir: &'a Path,
    /// Parsed manifest.
    pub manifest: &'a SampleManifest,
}

/// Tunables for [`run_scenario_with_context`].
///
/// Default behavior: web step batches dispatched through `npx playwright test`.
/// Set `skip_playwright = true` to log and skip web steps instead (useful in CI
/// lanes where Playwright isn't installed); process / HTTP / `assert_log` steps
/// still run. This skips rather than fails — web assertions are not evaluated.
#[derive(Debug, Clone, Copy, Default)]
pub struct ReplayOptions {
    /// When true, web steps are logged and skipped instead of dispatched
    /// through Playwright. Process / HTTP / `assert_log` steps still run.
    pub skip_playwright: bool,
}

/// Execute one scenario end-to-end.
///
/// Walks the scenario's steps in order, dispatching:
/// - Process target steps (`spawn`/`kill`/`wait_port`/`assert_log{,_clean}`)
///   through a per-scenario [`ProcessRegistry`].
/// - HTTP steps through a per-scenario [`HttpClient`].
/// - Web steps (`target` + `tap`/`type`/`wait_for`/etc.) buffered into
///   contiguous batches; on the next non-web step (or end of scenario) the
///   buffer is compiled to a Playwright spec and run via `npx playwright test`.
/// - Judge / report / iOS / measure / condition steps logged and skipped
///   until their targets land.
///
/// # Errors
///
/// Any error returned by the dispatched step variants propagates verbatim.
pub async fn run_scenario_with_context(
    path: &Path,
    context: Option<SampleContext<'_>>,
    options: ReplayOptions,
    shared_processes: Option<&mut ProcessRegistry>,
) -> Result<()> {
    let extras: Vec<(&str, String)> = context.map_or_else(Vec::new, |ctx| {
        vec![("MIRROIR_SAMPLE_DIR", ctx.sample_dir.display().to_string())]
    });
    let scenario = load_scenario_with_extras(path, &extras)?;
    let mut local_processes = ProcessRegistry::default();
    let http = HttpClient::new()?;
    let mut web_buffer: Vec<SkillStep> = Vec::new();
    let session_shared = shared_processes.is_some();
    let processes: &mut ProcessRegistry = shared_processes.unwrap_or(&mut local_processes);

    info!(
        file = %path.display(),
        name = %scenario.name,
        steps = scenario.steps.len(),
        with_sample = context.is_some(),
        session_shared,
        skip_playwright = options.skip_playwright,
        "scenario run starting"
    );

    for (idx, step) in scenario.steps.iter().enumerate() {
        if is_web_step(step) {
            web_buffer.push(step.clone());
            continue;
        }
        // Non-web step: flush any pending web batch before dispatching. When a
        // judge: step needs its response scraped from the live DOM, capture the
        // selector's text during this final flush and read it back below.
        let judge_capture = judge_capture_file(step, &web_buffer, options)?;
        let mut capture_specs: Vec<ResponseCapture> = judge_capture
            .as_ref()
            .map(|(_, cap)| vec![cap.clone()])
            .unwrap_or_default();
        // A cross_surface: step with a `capture` scrapes its web baseline during
        // this same flush, then reads it back when the step dispatches below.
        if let Some(cap) = cross_surface_capture(step, &web_buffer, options) {
            capture_specs.push(cap);
        }
        flush_web_buffer(&mut web_buffer, &scenario.name, options, &capture_specs).await?;
        info!(idx, kind = step_kind(step), "dispatching step");
        match step {
            SkillStep::Spawn(args) => {
                let resolved = resolve_spawn_args(args, context.as_ref())?;
                if session_shared {
                    processes.ensure_spawned(&resolved)?;
                } else {
                    processes.spawn(&resolved)?;
                }
            }
            SkillStep::Kill(args) => {
                if session_shared {
                    // In session-scoped mode the shared boot stays alive
                    // across scenarios; scenario-level kill: of the boot id
                    // is a no-op so individual scenarios stay portable.
                    info!(id = %args.id, "kill: skipped (session-shared subprocess)");
                } else {
                    processes.kill_process(args).await?;
                }
            }
            SkillStep::WaitPort(args) => processes.wait_port(args).await?,
            SkillStep::AssertLog(args) => processes.assert_log(args).await?,
            SkillStep::AssertLogClean(args) => processes.assert_log_clean(args).await?,
            SkillStep::Http(args) => http.dispatch(args).await?,
            SkillStep::Judge(args) => {
                let captured;
                let effective = if let Some((tmp, _)) = &judge_capture {
                    captured = JudgeArgs {
                        response_file: Some(tmp.path().display().to_string()),
                        ..args.clone()
                    };
                    &captured
                } else {
                    args
                };
                dispatch_judge(effective).await?;
            }
            SkillStep::CrossSurface(args) => dispatch_cross_surface(args)?,
            // LIMITATION(registre#1): device-only step kinds (launch, home,
            // shake, reset_app, set_network, measure, condition) have no
            // replay dispatch arm and are skipped.
            _ => info!(
                idx,
                kind = step_kind(step),
                "no replay dispatch for this step kind; skipping"
            ),
        }
    }
    // End-of-scenario: flush any trailing web batch (no judge capture follows).
    flush_web_buffer(&mut web_buffer, &scenario.name, options, &[]).await?;

    info!(file = %path.display(), name = %scenario.name, "scenario run completed");
    Ok(())
}

/// Convenience: run a single scenario with no sample context. Used by
/// `mirroir-run --run-scenario <file>`.
///
/// # Errors
///
/// Same as [`run_scenario_with_context`].
pub async fn run_scenario(path: &Path, options: ReplayOptions) -> Result<()> {
    run_scenario_with_context(path, None, options, None).await
}

async fn flush_web_buffer(
    buffer: &mut Vec<SkillStep>,
    scenario_name: &str,
    options: ReplayOptions,
    captures: &[ResponseCapture],
) -> Result<()> {
    if buffer.is_empty() {
        return Ok(());
    }
    let count = buffer.len();
    if options.skip_playwright {
        info!(count, "web step batch skipped (--no-playwright)");
        buffer.clear();
        return Ok(());
    }
    let batch_scenario = Scenario {
        version: SCHEMA_VERSION,
        name: scenario_name.to_owned(),
        app: None,
        description: None,
        tags: Vec::new(),
        steps: mem::take(buffer),
    };
    let spec = compile_scenario_with_captures(&batch_scenario, captures)?;
    let runner = PlaywrightRunner::from_env()?;
    info!(count, browsers = ?spec.browsers, "dispatching web batch to Playwright");
    let verdict = runner.run(&spec).await?;
    info!(
        passed = verdict.passed,
        failed = verdict.failed,
        skipped = verdict.skipped,
        flaky = verdict.flaky,
        "playwright batch completed"
    );
    Ok(())
}

fn is_web_step(step: &SkillStep) -> bool {
    matches!(
        step,
        SkillStep::Target(_)
            | SkillStep::Tap(_)
            | SkillStep::Type(_)
            | SkillStep::PressKey(_)
            | SkillStep::Swipe(_)
            | SkillStep::WaitFor(_)
            | SkillStep::AssertVisible(_)
            | SkillStep::AssertNotVisible(_)
            | SkillStep::Screenshot(_)
            | SkillStep::OpenUrl(_)
            | SkillStep::ScrollTo(_)
            | SkillStep::LongPress(_)
            | SkillStep::Drag(_)
            | SkillStep::Remember(_)
    )
}

/// Short label for a [`SkillStep`] suitable for `tracing` fields.
fn step_kind(step: &SkillStep) -> &'static str {
    match step {
        SkillStep::Launch(_) => "launch",
        SkillStep::Tap(_) => "tap",
        SkillStep::Type(_) => "type",
        SkillStep::PressKey(_) => "press_key",
        SkillStep::Swipe(_) => "swipe",
        SkillStep::WaitFor(_) => "wait_for",
        SkillStep::AssertVisible(_) => "assert_visible",
        SkillStep::AssertNotVisible(_) => "assert_not_visible",
        SkillStep::Screenshot(_) => "screenshot",
        SkillStep::Home(_) => "home",
        SkillStep::OpenUrl(_) => "open_url",
        SkillStep::Shake(_) => "shake",
        SkillStep::ScrollTo(_) => "scroll_to",
        SkillStep::ResetApp(_) => "reset_app",
        SkillStep::SetNetwork(_) => "set_network",
        SkillStep::Measure(_) => "measure",
        SkillStep::LongPress(_) => "long_press",
        SkillStep::Drag(_) => "drag",
        SkillStep::Target(_) => "target",
        SkillStep::Remember(_) => "remember",
        SkillStep::Condition(_) => "condition",
        SkillStep::Spawn(_) => "spawn",
        SkillStep::WaitPort(_) => "wait_port",
        SkillStep::Kill(_) => "kill",
        SkillStep::AssertLog(_) => "assert_log",
        SkillStep::AssertLogClean(_) => "assert_log_clean",
        SkillStep::Judge(_) => "judge",
        SkillStep::Http(_) => "http",
        SkillStep::Report(_) => "report",
        SkillStep::CrossSurface(_) => "cross_surface",
    }
}

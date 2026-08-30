// ABOUTME: Pins the three paths on which a scenario used to exit 0 without evaluating anything.
// ABOUTME: Every case asserts a non-zero exit — a run the runner cannot substantiate is never a pass.

//! Silent-pass regression suite.
//!
//! Each test drives the built `mirroir-run` binary against a scenario that
//! used to exit 0 while evaluating nothing, and asserts the runner now refuses
//! to call it a pass.

mod common;

use common::Sandbox;

/// `- report: fail` is the scenario author saying "this run failed". Skipping
/// it turns a declared failure into a green run, so the runner must exit
/// non-zero — and `- report: pass` must still exit 0.
#[test]
fn report_fail_fails_the_scenario() -> Result<(), String> {
    let sandbox = Sandbox::new()?;

    let failing = sandbox.scenario(
        "report-fail.yaml",
        "version: 1\nname: declared failure\nsteps:\n  - report: fail\n",
    )?;
    let run = sandbox.run(&["--run-scenario", &failing])?;
    if !run.is_failure() {
        return Err(format!(
            "`- report: fail` exited {:?}; a declared failure must not be a pass.\n{}",
            run.code,
            run.output()
        ));
    }

    let passing = sandbox.scenario(
        "report-pass.yaml",
        "version: 1\nname: declared pass\nsteps:\n  - report: pass\n",
    )?;
    let run = sandbox.run(&["--run-scenario", &passing])?;
    if run.is_failure() {
        return Err(format!(
            "`- report: pass` exited {:?}; a declared pass must stay green.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

/// A web scenario whose `target:` points at a port nothing is listening on
/// must never be reported green. There must also be no flag that skips the
/// web block and calls the remainder a pass: `--no-playwright` was exactly
/// that escape hatch and is gone.
#[test]
fn web_target_on_dead_port_has_no_skip_escape_hatch() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let scenario = sandbox.scenario(
        "dead-port.yaml",
        concat!(
            "version: 1\n",
            "name: web target on a dead port\n",
            "steps:\n",
            "  - target:\n",
            "      kind: web\n",
            "      browsers: [chrome]\n",
            "      url: \"http://127.0.0.1:9/\"\n",
            "  - assert_visible: \"Dashboard\"\n",
        ),
    )?;

    let skipped = sandbox.run(&["--run-scenario", &scenario, "--no-playwright"])?;
    if !skipped.is_failure() {
        return Err(format!(
            "--no-playwright exited {:?}: the web block was skipped and the run still passed.\n{}",
            skipped.code,
            skipped.output()
        ));
    }

    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if !run.is_failure() {
        return Err(format!(
            "web scenario on a dead port exited {:?}; assertions that never ran are not a pass.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

/// A scenario whose only assertion sits inside a `condition:` evaluates
/// nothing at all: the runner has no live-surface evaluator for `if_visible`,
/// so the branch — and the `assert_visible` inside it — is skipped. Reporting
/// that as a pass is the same lie as skipping the web block.
#[test]
fn assertion_buried_in_a_condition_is_not_a_pass() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let scenario = sandbox.scenario(
        "condition-only.yaml",
        concat!(
            "version: 1\n",
            "name: assertion hidden inside a condition\n",
            "steps:\n",
            "  - condition:\n",
            "      if_visible: \"Cookie banner\"\n",
            "      then:\n",
            "        - tap: \"Accept all\"\n",
            "      else:\n",
            "        - assert_visible: \"Dashboard\"\n",
        ),
    )?;

    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if !run.is_failure() {
        return Err(format!(
            "condition-only scenario exited {:?}; nothing was evaluated, so it is not a pass.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

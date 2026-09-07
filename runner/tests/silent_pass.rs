// ABOUTME: Pins the three paths on which a scenario used to exit 0 without evaluating anything.
// ABOUTME: Every case asserts a non-zero exit — a run the runner cannot substantiate is never a pass.

//! Silent-pass regression suite.
//!
//! Each test drives the built `mirroir-run` binary against a scenario that
//! used to exit 0 while evaluating nothing, and asserts the runner now refuses
//! to call it a pass.

mod common;

use std::fs;

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

/// Plant a `.mirroir/` plan whose only entry lives under `plan.nice_to_pass`,
/// optionally with a `default_set:` line. The entry is a local sample whose
/// directory exists but carries no `SAMPLE.md`, so selecting it fails loudly
/// on the manifest rather than on composition.
fn plant_nice_to_pass_only_plan(
    sandbox: &Sandbox,
    default_set: Option<&str>,
) -> Result<String, String> {
    sandbox.write(".mirroir/samples/demo/scenarios/.keep", "")?;
    let default_line = default_set.map_or_else(String::new, |set| format!("default_set: {set}\n"));
    sandbox.write(
        ".mirroir/mirroir.yaml",
        &format!(
            concat!(
                "version: 1\n",
                "{}",
                "plan:\n",
                "  nice_to_pass:\n",
                "    - name: demo\n",
                "      local: samples/demo\n",
                "      boot:\n",
                "        command: \"true\"\n",
            ),
            default_line
        ),
    )
}

/// A plan that declares entries only under `nice_to_pass` and names no
/// `default_set:` used to select the empty `must_pass` tier, compose zero
/// samples, and exit 0 with `"samples": []` — a green run over a plan that
/// declares real work. The selection has to refuse instead, and say which
/// tier does hold the entries.
#[test]
fn plan_with_only_nice_to_pass_entries_is_not_a_pass() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let config = plant_nice_to_pass_only_plan(&sandbox, None)?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--config", &config], &[("HOME", &home)])?;
    if !run.is_failure() {
        return Err(format!(
            "a plan whose only entry sits in nice_to_pass exited {:?}; selecting nothing is not a pass.\n{}",
            run.code,
            run.output()
        ));
    }
    let output = run.output();
    if !output.contains("nice_to_pass") {
        return Err(format!(
            "the refusal never names the tier that holds the entries:\n{output}"
        ));
    }
    if !output.contains("default_set") || !output.contains("--scenarios") {
        return Err(format!(
            "the refusal never names the two ways to select the entries:\n{output}"
        ));
    }
    Ok(())
}

/// The companion to the test above: naming the set the entries live in makes
/// the very same plan select them. The run still fails — the local sample has
/// no `SAMPLE.md` — but on the manifest, not on the selection. A fix that
/// merely made every plan fail would pass the test above and fail this one.
#[test]
fn default_set_all_selects_the_entry_the_bare_run_filtered_out() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let config = plant_nice_to_pass_only_plan(&sandbox, Some("all"))?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--config", &config], &[("HOME", &home)])?;
    if !run.is_failure() {
        return Err(format!(
            "`default_set: all` over a sample with no SAMPLE.md exited {:?}.\n{}",
            run.code,
            run.output()
        ));
    }
    let output = run.output();
    if !output.contains("SAMPLE.md") {
        return Err(format!(
            "`default_set: all` did not reach the sample: nothing mentions SAMPLE.md.\n{output}"
        ));
    }
    if output.contains("selected 0 of") {
        return Err(format!(
            "`default_set: all` still filtered the entry out.\n{output}"
        ));
    }
    Ok(())
}

/// The other half of the same hole: when a set *does* select something, the
/// entries it filtered out used to vanish from the run summary entirely —
/// `"skipped": 0` while an entry of the plan sat unselected. The report has to
/// account for every entry the plan declares, or it is not a record of the plan.
#[test]
fn a_set_filtered_entry_is_reported_as_skipped_not_dropped() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    sandbox.write(".mirroir/samples/core/scenarios/.keep", "")?;
    sandbox.write(".mirroir/samples/extra/scenarios/.keep", "")?;
    let config = sandbox.write(
        ".mirroir/mirroir.yaml",
        concat!(
            "version: 1\n",
            "plan:\n",
            "  must_pass:\n",
            "    - name: core\n",
            "      local: samples/core\n",
            "      boot:\n",
            "        command: \"true\"\n",
            "  nice_to_pass:\n",
            "    - name: extra\n",
            "      local: samples/extra\n",
            "      boot:\n",
            "        command: \"true\"\n",
        ),
    )?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--config", &config], &[("HOME", &home)])?;
    if !run.is_failure() {
        return Err(format!(
            "the must_pass sample has no SAMPLE.md; the run exited {:?}.\n{}",
            run.code,
            run.output()
        ));
    }

    let report_path = sandbox.path().join("mirroir-run-report.json");
    let report = fs::read_to_string(&report_path).map_err(|e| format!("read run report: {e}"))?;
    if !report.contains("\"skipped\": 1") {
        return Err(format!(
            "`extra` was filtered out by the must_pass set and the totals never counted it:\n{report}"
        ));
    }
    if !report.contains("\"samples\": 2") {
        return Err(format!(
            "the summary accounts for fewer samples than the plan declares:\n{report}"
        ));
    }
    if !report.contains("\"name\": \"extra\"") {
        return Err(format!(
            "the filtered entry is missing from samples[] entirely:\n{report}"
        ));
    }
    Ok(())
}

/// Following the remedy the plan-level refusal prints must not land the user
/// in the same hole one layer down. A `SAMPLE.md` declares its own tiers,
/// independently of which plan tier the entry sits in, so `default_set:
/// nice_to_pass` over a sample whose scenarios sit under `must_pass:` selects
/// no scenario at all. The sample used to report `pass` for replaying nothing
/// — a worse silent green than the one the plan-level guard closed, because
/// the report positively claims a sample passed.
#[test]
fn a_set_that_selects_no_scenario_inside_the_sample_is_not_a_pass() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let config = plant_nice_to_pass_only_plan(&sandbox, Some("nice_to_pass"))?;
    sandbox.write(
        ".mirroir/samples/demo/scenarios/smoke.yaml",
        "version: 1\nname: declared pass\nsteps:\n  - report: pass\n",
    )?;
    sandbox.write(
        ".mirroir/samples/demo/SAMPLE.md",
        concat!(
            "# Demo\n\n",
            "```yaml\n",
            "version: 1\n",
            "session:\n",
            "  boot:\n",
            "    command: \"true\"\n",
            "  scenarios:\n",
            "    must_pass:\n",
            "      - scenarios/smoke.yaml\n",
            "```\n",
        ),
    )?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--config", &config], &[("HOME", &home)])?;
    if !run.is_failure() {
        return Err(format!(
            "`default_set: nice_to_pass` over a SAMPLE.md that declares only must_pass scenarios exited {:?}; zero scenarios ran, so it is not a pass.\n{}",
            run.code,
            run.output()
        ));
    }
    let output = run.output();
    if !output.contains("must_pass") || !output.contains("nice_to_pass") {
        return Err(format!(
            "the refusal names neither the set in effect nor the tier that holds the scenarios:\n{output}"
        ));
    }

    let report_path = sandbox.path().join("mirroir-run-report.json");
    let report = fs::read_to_string(&report_path).map_err(|e| format!("read run report: {e}"))?;
    if report.contains("\"passed\": 1") {
        return Err(format!(
            "the summary claims a sample passed while zero of its scenarios ran:\n{report}"
        ));
    }
    Ok(())
}

/// Plant a sample whose single `must_pass` scenario evaluates something and
/// passes, and return the sample directory's path. `baseline` names an extra
/// `baselines/` file to commit alongside it, if any.
fn plant_sample_with_baseline(sandbox: &Sandbox, baseline: Option<&str>) -> Result<String, String> {
    sandbox.write(
        "sample/scenarios/smoke.yaml",
        "version: 1\nname: declared pass\nsteps:\n  - report: pass\n",
    )?;
    if let Some(name) = baseline {
        sandbox.write(
            &format!("sample/baselines/{name}"),
            "Order total 42 dollars\nShip to Montreal\n",
        )?;
    }
    sandbox.write(
        "sample/SAMPLE.md",
        concat!(
            "# Demo\n\n",
            "```yaml\n",
            "version: 1\n",
            "session:\n",
            "  boot:\n",
            "    command: \"true\"\n",
            "  scenarios:\n",
            "    must_pass:\n",
            "      - scenarios/smoke.yaml\n",
            "```\n",
        ),
    )?;
    Ok(sandbox.path().join("sample").display().to_string())
}

/// An iOS baseline is captured on a surface this binary drives no executor
/// for, so the only thing that ever reads one is a `cross_surface:` step
/// naming it. Committed into a sample whose scenarios name it nowhere, it is
/// read by nothing and the sample reports green with the parity gate it was
/// captured for absent — the silent green a `.ios.txt` file exists to close.
#[test]
fn an_orphan_ios_baseline_is_not_a_pass() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let sample = plant_sample_with_baseline(&sandbox, Some("checkout.ios.txt"))?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--sample", &sample], &[("HOME", &home)])?;
    if !run.is_failure() {
        return Err(format!(
            "a sample carrying an unreferenced baselines/checkout.ios.txt exited {:?}; nothing compared it, so it is not a pass.\n{}",
            run.code,
            run.output()
        ));
    }
    let output = run.output();
    if !output.contains("checkout.ios.txt") {
        return Err(format!(
            "the refusal never names the orphan baseline:\n{output}"
        ));
    }
    Ok(())
}

/// The companion: the very same sample without that file is green. A guard
/// that merely made every sample fail would pass the test above and fail this
/// one.
#[test]
fn the_same_sample_without_the_orphan_baseline_stays_green() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let sample = plant_sample_with_baseline(&sandbox, None)?;
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(&["--sample", &sample], &[("HOME", &home)])?;
    if run.is_failure() {
        return Err(format!(
            "a sample with no baselines/ directory exited {:?}; the guard fired where there is nothing to account for.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

/// The gate's other half: a baseline the sample *does* compare, on a run whose
/// `--scenarios` set leaves that scenario out. The sample is well formed — its
/// `must_pass` parity scenario names the capture — and the informational tier
/// has to stay runnable, so this is the tier choice the invocation made, not an
/// orphan capture.
#[test]
fn a_baseline_named_by_an_unselected_tier_still_runs_the_other_tier() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    sandbox.write(
        "sample/scenarios/parity.yaml",
        concat!(
            "version: 1\nname: parity\nsteps:\n",
            "  - cross_surface:\n",
            "      response_files:\n",
            "        - \"${MIRROIR_SAMPLE_DIR}/baselines/parity.web.txt\"\n",
            "        - \"${MIRROIR_SAMPLE_DIR}/baselines/parity.ios.txt\"\n",
            "      min_similarity: 0.5\n",
        ),
    )?;
    sandbox.write(
        "sample/scenarios/smoke.yaml",
        "version: 1\nname: declared pass\nsteps:\n  - report: pass\n",
    )?;
    for half in ["parity.ios.txt", "parity.web.txt"] {
        sandbox.write(
            &format!("sample/baselines/{half}"),
            "Order total 42 dollars\nShip to Montreal\n",
        )?;
    }
    sandbox.write(
        "sample/SAMPLE.md",
        concat!(
            "# Demo\n\n",
            "```yaml\n",
            "version: 1\n",
            "session:\n",
            "  boot:\n",
            "    command: \"true\"\n",
            "  scenarios:\n",
            "    must_pass:\n",
            "      - scenarios/parity.yaml\n",
            "    nice_to_pass:\n",
            "      - scenarios/smoke.yaml\n",
            "```\n",
        ),
    )?;
    let sample = sandbox.path().join("sample").display().to_string();
    let home = sandbox.path().display().to_string();

    let run = sandbox.run_with_env(
        &["--sample", &sample, "--scenarios", "nice-to-pass"],
        &[("HOME", &home)],
    )?;
    if run.is_failure() {
        return Err(format!(
            "`--scenarios nice-to-pass` exited {:?} on a sample whose must_pass scenario compares baselines/parity.ios.txt; the informational tier must stay runnable.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

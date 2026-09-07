// ABOUTME: Pins that `--validate` resolves an executor for the plan it builds, not just the plan's shape.
// ABOUTME: A scenario nothing here can run is refused by its real reason — the target kind, or the missing browser.

//! Executor-resolution suite for `--validate`.
//!
//! `--validate` builds the execution plan a run would execute. A plan no
//! executor can take is not a valid scenario, so both shapes below are refused
//! at validate time, with the same verdict the run path reaches — the two must
//! never disagree about one file.

mod common;

use common::Sandbox;

/// A scenario whose `target:` names an iOS app declares a surface this binary
/// has no executor for: `ios` and `macos` are mirroir-mcp's, driven from
/// Swift. Validate must say so by name — diagnosing it as a web-block
/// contiguity problem points the author at a shape that is not the issue.
#[test]
fn validate_rejects_a_target_kind_with_no_executor() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let scenario = sandbox.scenario(
        "ios-target.yaml",
        concat!(
            "version: 1\n",
            "name: acme on ios\n",
            "steps:\n",
            "  - target:\n",
            "      kind: ios\n",
            "      app: \"Acme\"\n",
            "  - launch: \"Acme\"\n",
            "  - tap: \"Sign in\"\n",
            "  - assert_visible: \"Welcome\"\n",
        ),
    )?;

    let validated = sandbox.run(&["--validate", &scenario])?;
    if !validated.is_failure() {
        return Err(format!(
            "validate accepted an ios target (exit {:?}); nothing in this binary executes one.\n{}",
            validated.code,
            validated.output()
        ));
    }
    let output = validated.output();
    for fragment in ["kind: ios", "mirroir-mcp"] {
        if !output.contains(fragment) {
            return Err(format!(
                "the validate failure did not name `{fragment}`\n{output}"
            ));
        }
    }
    if output.contains("splits its web steps") {
        return Err(format!(
            "the failure blamed web-block contiguity; the file declares an unrunnable target kind\n{output}"
        ));
    }

    // The run path refuses the same file — validate and run agree on it.
    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if !run.is_failure() {
        return Err(format!(
            "the ios target exited {:?} on --run-scenario.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

/// Web steps compile to a Playwright invocation, which needs a browser to open.
/// A scenario that declares no `target:` at all still plans a web block, and
/// validating it as if it could run is the same lie as accepting a target kind
/// nothing executes.
#[test]
fn validate_rejects_a_web_block_with_no_web_target() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let scenario = sandbox.scenario(
        "no-target.yaml",
        concat!(
            "version: 1\n",
            "name: acme with no declared surface\n",
            "steps:\n",
            "  - tap: \"Sign in\"\n",
            "  - assert_visible: \"Welcome\"\n",
        ),
    )?;

    let validated = sandbox.run(&["--validate", &scenario])?;
    if !validated.is_failure() {
        return Err(format!(
            "validate accepted a web block with no browser (exit {:?}).\n{}",
            validated.code,
            validated.output()
        ));
    }
    let output = validated.output();
    for fragment in ["target: { kind: web", "tap"] {
        if !output.contains(fragment) {
            return Err(format!(
                "the validate failure did not name `{fragment}`\n{output}"
            ));
        }
    }

    // The run path refuses the same file — validate and run agree on it.
    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if !run.is_failure() {
        return Err(format!(
            "the browserless web block exited {:?} on --run-scenario.\n{}",
            run.code,
            run.output()
        ));
    }
    Ok(())
}

/// A `target:` lower down the file declares a surface just as loudly as the
/// first one does. A scenario that opens on the browser and then names the
/// phone is refused at that second declaration — accepting it compiles the
/// phone's taps into the browser run, because the compiler emits nothing for a
/// target step and Playwright happily clicks whatever label it is handed.
#[test]
fn validate_rejects_an_ios_target_declared_after_a_web_one() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    let scenario = sandbox.scenario(
        "web-then-ios.yaml",
        concat!(
            "version: 1\n",
            "name: web then ios\n",
            "steps:\n",
            "  - target:\n",
            "      kind: web\n",
            "      url: \"http://127.0.0.1:9/\"\n",
            "  - assert_visible: \"Dashboard\"\n",
            "  - target:\n",
            "      kind: ios\n",
            "      app: \"Acme\"\n",
            "  - tap: \"Sign in\"\n",
        ),
    )?;

    let validated = sandbox.run(&["--validate", &scenario])?;
    if !validated.is_failure() {
        return Err(format!(
            "validate accepted an ios target declared at step 2 (exit {:?}); nothing here executes one.\n{}",
            validated.code,
            validated.output()
        ));
    }
    let output = validated.output();
    for fragment in ["step 2", "kind: ios", "mirroir-mcp"] {
        if !output.contains(fragment) {
            return Err(format!(
                "the validate failure did not name `{fragment}`\n{output}"
            ));
        }
    }

    // Emitting must refuse it too: the failure mode this closes is the phone's
    // tap landing in the browser's spec, which only the compiler can produce.
    let emitted = sandbox.run(&["--emit", "playwright", &scenario])?;
    if !emitted.is_failure() {
        return Err(format!(
            "`--emit playwright` accepted the ios target (exit {:?}).\n{}",
            emitted.code,
            emitted.output()
        ));
    }
    if let Ok(spec) = sandbox.emitted_spec("web-then-ios")
        && spec.contains("Sign in")
    {
        return Err(format!(
            "the phone's tap compiled into the browser spec\n{spec}"
        ));
    }
    Ok(())
}

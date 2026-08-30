// ABOUTME: End-to-end proof of the capture channel — spec attachment → report.json → Rust post-hook.
// ABOUTME: A stub npx supplies the report and a loopback stub answers the judge; no Node, no browser, no network.

//! Capture-channel suite.
//!
//! The compiled spec closes each test with
//! `test.info().attach('mirroir-captures', …)`. These tests drive the whole
//! path that attachment travels: the runner ingests the JSON reporter, and the
//! `judge:` and `cross_surface:` post-hooks read their values back out of it.
//! Nothing here writes a scraped value to a side-channel file, because that
//! mechanism no longer exists.

mod common;

use std::fs;

use common::Sandbox;
use common::oracle_stub::stub_oracle;

/// The canonical prompt-template hash every `judge:` step pins.
const TEMPLATE_HASH: &str =
    "sha256:2fd94adeba57835b2267269c672245aeb82c450908f866bd4c887da010602834";

/// A Playwright report whose single passing test attached
/// `{"judge": {"2": "WebSocket and SSE are both supported."}}`.
const JUDGE_REPORT: &str = r#"{
  "suites": [
    {
      "title": "scenario.spec.ts",
      "specs": [
        {
          "title": "judge reads its response from the attachment",
          "tests": [
            {
              "projectName": "chromium",
              "results": [
                {
                  "status": "passed",
                  "attachments": [
                    {
                      "name": "mirroir-captures",
                      "contentType": "application/json",
                      "body": "eyJtZXRyaWNzIjp7fSwianVkZ2UiOnsiMiI6IldlYlNvY2tldCBhbmQgU1NFIGFyZSBib3RoIHN1cHBvcnRlZC4ifSwiY3Jvc3Nfc3VyZmFjZSI6e319"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ],
      "suites": []
    }
  ]
}"#;

/// The same shape, attaching `{"cross_surface": {"2": "the shared answer text"}}`.
const CROSS_SURFACE_REPORT: &str = r#"{
  "suites": [
    {
      "title": "scenario.spec.ts",
      "specs": [
        {
          "title": "cross_surface reads its baseline from the attachment",
          "tests": [
            {
              "projectName": "chromium",
              "results": [
                {
                  "status": "passed",
                  "attachments": [
                    {
                      "name": "mirroir-captures",
                      "contentType": "application/json",
                      "body": "eyJtZXRyaWNzIjp7fSwianVkZ2UiOnt9LCJjcm9zc19zdXJmYWNlIjp7IjIiOiJ0aGUgc2hhcmVkIGFuc3dlciB0ZXh0In19"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ],
      "suites": []
    }
  ]
}"#;

/// A `judge:` step names a `response_selector` and nothing else. The only way
/// its text can reach the oracle is the `mirroir-captures` attachment — there
/// is no file for it to read. The stub oracle hands back the prompt it was
/// sent, so the assertion is on the scraped text itself, not on an exit code.
#[test]
fn judge_response_arrives_through_the_playwright_attachment() -> Result<(), String> {
    let oracle = stub_oracle("0.95")?;
    let sandbox = Sandbox::new()?;
    sandbox.stub_npx(JUDGE_REPORT)?;
    // Only the trusted home overlay may name an endpoint, so the stub profile
    // is declared where a user's own machine config lives.
    sandbox.write(
        ".mirroir/oracles/profiles.yaml",
        &format!(
            concat!(
                "profiles:\n",
                "  - name: stub-oracle\n",
                "    base_url: \"http://127.0.0.1:{port}/v1/chat/completions\"\n",
                "    model: stub\n",
                "    timeout_s: 10\n"
            ),
            port = oracle.port
        ),
    )?;
    let scenario = sandbox.scenario(
        "judged.yaml",
        &format!(
            concat!(
                "version: 1\n",
                "name: judge reads its response from the attachment\n",
                "steps:\n",
                "  - target:\n",
                "      kind: web\n",
                "      browsers: [chrome]\n",
                "      url: \"http://127.0.0.1:9/\"\n",
                "  - assert_visible: \"reply\"\n",
                "  - judge:\n",
                "      profile: stub-oracle\n",
                "      user_prompt_template_hash: \"{TEMPLATE_HASH}\"\n",
                "      response_selector: \"[data-test=reply]\"\n",
                "      pass_threshold: 0.9\n",
                "      expected_signal: \"names both transports\"\n"
            ),
            TEMPLATE_HASH = TEMPLATE_HASH
        ),
    )?;

    let home = sandbox.path().display().to_string();
    let run = sandbox.run_with_env(&["--run-scenario", &scenario], &[("HOME", &home)])?;
    if run.is_failure() {
        return Err(format!(
            "the judged scenario exited {:?}; the attachment should have supplied its response.\n{}",
            run.code,
            run.output()
        ));
    }

    let prompt = oracle
        .request
        .recv()
        .map_err(|e| format!("stub oracle never received a request: {e}"))?;
    if !prompt.contains("WebSocket and SSE are both supported.") {
        return Err(format!(
            "the judge was not sent the attached response text; it received:\n{prompt}"
        ));
    }
    Ok(())
}

/// A `cross_surface:` step with a `capture` has no file to compare until the
/// invocation produces one: the attachment carries the web baseline, the
/// post-hook writes it to the capture's `to` path, and the equivalence check
/// runs against it.
#[test]
fn cross_surface_baseline_arrives_through_the_playwright_attachment() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    sandbox.stub_npx(CROSS_SURFACE_REPORT)?;
    let ios = sandbox.write("surface-ios.txt", "the shared answer text")?;
    let web = sandbox.path().join("surface-web.txt");
    let web_path = web.display().to_string();
    let scenario = sandbox.scenario(
        "cross.yaml",
        &format!(
            concat!(
                "version: 1\n",
                "name: cross_surface reads its baseline from the attachment\n",
                "steps:\n",
                "  - target:\n",
                "      kind: web\n",
                "      browsers: [chrome]\n",
                "      url: \"http://127.0.0.1:9/\"\n",
                "  - assert_visible: \"answer\"\n",
                "  - cross_surface:\n",
                "      response_files:\n",
                "        - \"{ios}\"\n",
                "        - \"{web}\"\n",
                "      min_similarity: 0.9\n",
                "      capture:\n",
                "        selector: \"[data-test=answer]\"\n",
                "        to: \"{web}\"\n"
            ),
            ios = ios,
            web = web_path
        ),
    )?;

    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if run.is_failure() {
        return Err(format!(
            "the cross_surface scenario exited {:?}; the attachment should have produced its baseline.\n{}",
            run.code,
            run.output()
        ));
    }
    let written = fs::read_to_string(&web)
        .map_err(|e| format!("the capture was never written to {web_path}: {e}"))?;
    if written != "the shared answer text" {
        return Err(format!("capture text is wrong: {written}"));
    }
    Ok(())
}

/// The capture is load-bearing, not decorative: with the attachment empty the
/// `cross_surface` step must refuse rather than compare a stale or missing file.
#[test]
fn a_declared_capture_missing_from_the_attachment_fails_the_run() -> Result<(), String> {
    let sandbox = Sandbox::new()?;
    sandbox.stub_npx(
        r#"{"suites":[{"title":"s","specs":[{"title":"t","tests":[{"results":[{"status":"passed"}]}]}],"suites":[]}]}"#,
    )?;
    let ios = sandbox.write("surface-ios.txt", "the shared answer text")?;
    let web = sandbox.write("surface-web.txt", "a stale baseline nobody refreshed")?;
    let scenario = sandbox.scenario(
        "cross-missing.yaml",
        &format!(
            concat!(
                "version: 1\n",
                "name: cross_surface with no capture in the attachment\n",
                "steps:\n",
                "  - target:\n",
                "      kind: web\n",
                "      browsers: [chrome]\n",
                "      url: \"http://127.0.0.1:9/\"\n",
                "  - assert_visible: \"answer\"\n",
                "  - cross_surface:\n",
                "      response_files:\n",
                "        - \"{ios}\"\n",
                "        - \"{web}\"\n",
                "      min_similarity: 0.9\n",
                "      capture:\n",
                "        selector: \"[data-test=answer]\"\n",
                "        to: \"{web}\"\n"
            ),
            ios = ios,
            web = web
        ),
    )?;

    let run = sandbox.run(&["--run-scenario", &scenario])?;
    if !run.is_failure() {
        return Err(format!(
            "the run exited {:?}; a missing capture compared a stale file and passed.\n{}",
            run.code,
            run.output()
        ));
    }
    if !run.output().contains("carried no text for it") {
        return Err(format!(
            "the failure did not name the missing capture.\n{}",
            run.output()
        ));
    }
    Ok(())
}

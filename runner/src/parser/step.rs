// ABOUTME: SkillStep enum + step argument types — port of mirroir's SwiftParser grammar.
// ABOUTME: Externally tagged so YAML `- launch: "App"` deserializes via the key name as the discriminator.

use std::result::Result as StdResult;

use serde::Deserialize;

pub use crate::parser::step_args::{
    CrossSurfaceArgs, HttpArgs, HttpMethod, JudgeArgs, ReportArgs, ResponseDriftConfig,
};
pub use crate::parser::step_process_args::{
    AssertLogArgs, AssertLogCleanArgs, KillArgs, PortState, SpawnArgs, WaitPortArgs,
};
pub use crate::parser::step_web_args::{AssertArgs, TapArgs, TypeArgs, WaitForArgs};

/// The grammar mirroir emits and mirroir-run replays.
///
/// Externally tagged: each step's YAML representation is a single-key map where
/// the key names the variant (`launch`, `tap`, `spawn`, `judge`, …). Forward
/// compatibility through the [`Self::Skipped`] variant is reserved for future
/// extension when the runner encounters an unknown step type at parse time.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SkillStep {
    // ── mirroir SkillStep variants (Sources/mirroir-mcp/SkillParser.swift) ──
    /// `- launch: "Expo Go"` — launch an app by name.
    Launch(String),
    /// `- tap: "Email"` or `- tap: { label, last?, timeout_s? }`.
    Tap(TapArgs),
    /// `- type: "user@example.com"` or `- type: { text, into?, last?, timeout_s? }`.
    Type(TypeArgs),
    /// `- press_key: "return"` or `- press_key: { key, modifiers }`.
    PressKey(PressKeyArgs),
    /// `- swipe: "up"` — perform a directional swipe.
    Swipe(String),
    /// `- wait_for: "Connected"` or `- wait_for: { label, timeout_s?, last? }`.
    WaitFor(WaitForArgs),
    /// `- assert_visible: "Welcome"` or `- assert_visible: { label, contains?, last?, timeout_s? }`.
    AssertVisible(AssertArgs),
    /// `- assert_not_visible: "Error toast"` — same arguments, inverted.
    AssertNotVisible(AssertArgs),
    /// `- screenshot: "name"`.
    Screenshot(String),
    /// `- home: null` — return to home screen (iOS).
    Home(NullValue),
    /// `- open_url: "https://…"`.
    OpenUrl(String),
    /// `- shake: null` — trigger device shake (iOS).
    Shake(NullValue),
    /// `- scroll_to: "Label"` or `- scroll_to: { label, direction, max_scrolls }`.
    ScrollTo(ScrollToArgs),
    /// `- reset_app: "appName"`.
    ResetApp(String),
    /// `- set_network: "airplane"`.
    SetNetwork(String),
    /// `- measure: { name, action, until, max_seconds }`.
    Measure(MeasureArgs),
    /// `- long_press: "Label"` or `- long_press: { label, duration_ms }`.
    LongPress(LongPressArgs),
    /// `- drag: { from, to }`.
    Drag(DragArgs),
    /// `- target: { kind, browsers?, url?, app? }`.
    Target(TargetArgs),
    /// `- remember: "AI observation text"`.
    Remember(String),

    // ── condition: if_visible / then / else (mirroir-skills legacy YAML) ──
    /// `- condition: { if_visible, then, else? }`.
    Condition(ConditionArgs),

    // ── runner extensions (forward-compat — mirroir parses as .skipped) ──
    /// `- spawn: { id, from?: SAMPLE.md, command?, ... }` — process target.
    Spawn(SpawnArgs),
    /// `- wait_port: { port, timeout_s, expect? }` — process target.
    WaitPort(WaitPortArgs),
    /// `- kill: { id, grace_s?, cleanup? }` — process target.
    Kill(KillArgs),
    /// `- assert_log: { id, pattern, flags? }` — regex grep against captured logs.
    AssertLog(AssertLogArgs),
    /// `- assert_log_clean: { id, deny, allow }` — fail if any deny matches and no allow matches.
    AssertLogClean(AssertLogCleanArgs),
    /// `- judge: { profile, ..., pass_threshold, response_drift }` — LLM oracle (Rust post-hook).
    Judge(JudgeArgs),
    /// `- http: { method, url, expect_status?, expect_body_contains? }`.
    Http(HttpArgs),
    /// `- report: pass | fail | drift` or `{ verdict }`.
    Report(ReportArgs),
    /// `- cross_surface: { response_files: [a, b, ...], min_similarity }` —
    /// compare captured responses from multiple surfaces (web/iOS/http) and
    /// fail when pairwise Jaccard fingerprint similarity drops below
    /// `min_similarity` (default 0.7).
    CrossSurface(CrossSurfaceArgs),
}

/// Marker type for step verbs whose YAML form carries no arguments.
///
/// Accepts either `null` (the mirroir convention — `home: null`, `shake: null`)
/// or an empty mapping `{}`. Any other shape is rejected at parse time.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct NullValue {}

impl<'de> Deserialize<'de> for NullValue {
    fn deserialize<D>(deserializer: D) -> StdResult<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged, deny_unknown_fields)]
        enum Repr {
            Null,
            Empty {},
        }
        let _ = Repr::deserialize(deserializer)?;
        Ok(Self {})
    }
}

/// Arguments for `press_key`. Accepts string shorthand or full record form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PressKeyArgs {
    /// The key name (e.g. `"return"`, `"escape"`, `"tab"`).
    pub key: String,
    /// Modifier names (e.g. `["command", "shift"]`). Empty when the shorthand form is used.
    pub modifiers: Vec<String>,
}

impl<'de> Deserialize<'de> for PressKeyArgs {
    fn deserialize<D>(deserializer: D) -> StdResult<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Repr {
            Shorthand(String),
            Full {
                key: String,
                #[serde(default)]
                modifiers: Vec<String>,
            },
        }
        Ok(match Repr::deserialize(deserializer)? {
            Repr::Shorthand(key) => Self {
                key,
                modifiers: Vec::new(),
            },
            Repr::Full { key, modifiers } => Self { key, modifiers },
        })
    }
}

/// Arguments for `scroll_to`. Accepts string shorthand (label only) or full record form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScrollToArgs {
    /// The text label to scroll to.
    pub label: String,
    /// Scroll direction — defaults to `"up"` per mirroir's convention.
    pub direction: String,
    /// Maximum number of scroll attempts before failing — defaults to `10`.
    pub max_scrolls: u32,
}

impl<'de> Deserialize<'de> for ScrollToArgs {
    fn deserialize<D>(deserializer: D) -> StdResult<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Repr {
            Shorthand(String),
            Full {
                label: String,
                #[serde(default = "default_scroll_direction")]
                direction: String,
                #[serde(default = "default_max_scrolls")]
                max_scrolls: u32,
            },
        }
        Ok(match Repr::deserialize(deserializer)? {
            Repr::Shorthand(label) => Self {
                label,
                direction: default_scroll_direction(),
                max_scrolls: default_max_scrolls(),
            },
            Repr::Full {
                label,
                direction,
                max_scrolls,
            } => Self {
                label,
                direction,
                max_scrolls,
            },
        })
    }
}

fn default_scroll_direction() -> String {
    "up".to_owned()
}

fn default_max_scrolls() -> u32 {
    10
}

/// Arguments for `measure`. `action` is a `type:value` string per mirroir's
/// `docs/tools.md` (e.g. `"tap:Label"`, `"press_key:return"`,
/// `"wait_visible:streaming-caret"`).
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct MeasureArgs {
    /// Friendly name reported in the run artifact (e.g. `"first_token_latency"`).
    pub name: String,
    /// Action to perform before timing starts, in `type:value` shorthand.
    pub action: String,
    /// Label / text to wait for after the action; stops the clock. Optional when
    /// `action` is itself a waiting verb (`wait_for` / `wait_visible`), which is
    /// self-terminating — then the action's own label stops the clock.
    #[serde(default)]
    pub until: Option<String>,
    /// Optional ceiling — fails the step if `until` doesn't appear within this many seconds.
    #[serde(default)]
    pub max_seconds: Option<f64>,
}

/// Arguments for `long_press`. Accepts string shorthand (label only) or full record form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LongPressArgs {
    /// The label of the element to long-press.
    pub label: String,
    /// Optional press duration override, in milliseconds. `None` accepts the runner's default.
    pub duration_ms: Option<u32>,
}

impl<'de> Deserialize<'de> for LongPressArgs {
    fn deserialize<D>(deserializer: D) -> StdResult<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Repr {
            Shorthand(String),
            Full {
                label: String,
                #[serde(default)]
                duration_ms: Option<u32>,
            },
        }
        Ok(match Repr::deserialize(deserializer)? {
            Repr::Shorthand(label) => Self {
                label,
                duration_ms: None,
            },
            Repr::Full { label, duration_ms } => Self { label, duration_ms },
        })
    }
}

/// Arguments for `drag`.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct DragArgs {
    /// Label of the element to start dragging from.
    pub from: String,
    /// Label of the element to release on.
    pub to: String,
}

/// Arguments for `target` — declares the execution surface for subsequent steps.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct TargetArgs {
    /// Kind of surface — `web` (Playwright), `process` (tokio), `http` (reqwest), `ios` (mirroir-mcp).
    pub kind: TargetKind,
    /// For `kind: web`, the list of browsers to materialize as Playwright projects.
    /// Empty list defaults to `[chromium]` at compile time.
    #[serde(default)]
    pub browsers: Vec<Browser>,
    /// For `kind: web`, the starting URL.
    #[serde(default)]
    pub url: Option<String>,
    /// For `kind: ios`, the application identifier (mirroir-mcp delegates).
    #[serde(default)]
    pub app: Option<String>,
}

/// Target kinds supported by the runner.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum TargetKind {
    /// Web surface driven via Playwright.
    Web,
    /// Subprocess target (spawn / kill / log capture).
    Process,
    /// HTTP target (REST probes).
    Http,
    /// iOS surface delegated to mirroir-mcp.
    Ios,
    /// macOS app surface (mirroir-mcp existing target).
    Macos,
}

/// Browsers materialized as Playwright projects in the emitted `playwright.config.ts`.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum Browser {
    /// Chromium / Chrome / Edge.
    Chrome,
    /// Mozilla Firefox.
    Firefox,
    /// Safari / `WebKit`.
    Webkit,
}

/// Arguments for `condition` — branches based on element visibility.
#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ConditionArgs {
    /// Label / selector to check for visibility.
    pub if_visible: String,
    /// Steps to execute when the label is visible.
    pub then: Vec<SkillStep>,
    /// Optional steps to execute when the label is not visible.
    #[serde(default, rename = "else")]
    pub else_steps: Option<Vec<SkillStep>>,
}

#[cfg(test)]
mod tests {
    use std::error::Error as StdError;

    use serde_yaml::Deserializer;
    use serde_yaml::with::singleton_map_recursive;

    use super::*;

    type TestResult = StdResult<(), Box<dyn StdError>>;

    fn parse(yaml: &str) -> StdResult<SkillStep, serde_yaml::Error> {
        singleton_map_recursive::deserialize(Deserializer::from_str(yaml))
    }

    fn fail<T>(reason: String) -> StdResult<T, Box<dyn StdError>> {
        Err(reason.into())
    }

    #[test]
    fn launch_string() -> TestResult {
        assert_eq!(
            parse("launch: \"Expo Go\"")?,
            SkillStep::Launch("Expo Go".to_owned())
        );
        Ok(())
    }

    #[test]
    fn tap_string() -> TestResult {
        assert_eq!(
            parse("tap: \"Email\"")?,
            SkillStep::Tap(TapArgs::new("Email".to_owned()))
        );
        Ok(())
    }

    #[test]
    fn wait_for_shorthand_and_full() -> TestResult {
        let short = parse("wait_for: \"Welcome\"")?;
        let full = parse("wait_for: { label: \"Welcome\", timeout_s: 30 }")?;
        let SkillStep::WaitFor(short_args) = short else {
            return fail("expected WaitFor, got other variant".to_owned());
        };
        let SkillStep::WaitFor(full_args) = full else {
            return fail("expected WaitFor, got other variant".to_owned());
        };
        assert_eq!(short_args.label, "Welcome");
        assert!(short_args.timeout_s.is_none());
        assert_eq!(full_args.label, "Welcome");
        assert_eq!(full_args.timeout_s, Some(30));
        Ok(())
    }

    #[test]
    fn home_unit_variant_with_null() -> TestResult {
        assert!(matches!(parse("home: null")?, SkillStep::Home(_)));
        Ok(())
    }

    #[test]
    fn condition_with_then_and_else() -> TestResult {
        let yaml = r#"
condition:
  if_visible: "Invalid"
  then:
    - tap: "Sign Up"
  else:
    - wait_for: "Welcome"
"#;
        let SkillStep::Condition(c) = parse(yaml)? else {
            return fail("expected Condition variant".to_owned());
        };
        assert_eq!(c.if_visible, "Invalid");
        assert_eq!(c.then.len(), 1);
        let Some(else_steps) = c.else_steps else {
            return fail("expected else_steps to be Some".to_owned());
        };
        assert_eq!(else_steps.len(), 1);
        Ok(())
    }

    #[test]
    fn target_web_with_browsers() -> TestResult {
        let yaml = r#"
target:
  kind: web
  browsers: [chrome, firefox, webkit]
  url: "http://localhost:8081/"
"#;
        let SkillStep::Target(args) = parse(yaml)? else {
            return fail("expected Target variant".to_owned());
        };
        assert_eq!(args.kind, TargetKind::Web);
        assert_eq!(
            args.browsers,
            vec![Browser::Chrome, Browser::Firefox, Browser::Webkit]
        );
        assert_eq!(args.url.as_deref(), Some("http://localhost:8081/"));
        Ok(())
    }
}

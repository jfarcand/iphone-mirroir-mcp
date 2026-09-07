// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Formats a linear iOS exploration capture into a mirroir-run SkillStep scenario (YAML).
// ABOUTME: Pure transformation — emits target/launch/tap/... steps + a cross-surface baseline; no side effects.

import HelperLib

/// Renders a linear exploration capture into a `mirroir-run` SkillStep scenario
/// on the iOS surface, plus the cross-surface baseline text for that flow.
///
/// The emitted YAML is written in the shared step grammar, but it declares
/// `target: { kind: ios }` — a surface mirroir-run has no executor for, so the
/// runner refuses it by name rather than planning it. It is a faithful record of
/// the captured walk; the baseline beside it is the anchor the web leg's own
/// `cross_surface:` step compares its live scrape against.
enum ScenarioStepFormatter {

    /// Build the full `<flow>.ios.yaml` scenario document for `screens`.
    /// The first screen is the launch; each subsequent screen contributes the
    /// action that reached it. A destination landmark assertion is appended.
    static func scenarioYAML(name: String, appName: String, screens: [ExploredScreen]) -> String {
        var steps: [String] = [
            "  - target: { kind: ios, app: \(yamlScalar(appName)) }",
            "  - launch: \(yamlScalar(appName))",
        ]
        for screen in screens.dropFirst() {
            if let line = stepLine(screen: screen) {
                steps.append(line)
            }
        }
        if let landmark = landmark(in: screens.last?.elements ?? []) {
            steps.append("  - assert_visible: \(yamlScalar(landmark))")
        }
        return "version: 1\nname: \(yamlScalar(name))\nsteps:\n" + steps.joined(separator: "\n") + "\n"
    }

    /// The cross-surface oracle: whitespace-joined OCR text of the destination
    /// screen — the equivalence landmark a paired web capture is diffed against.
    static func baseline(screens: [ExploredScreen]) -> String {
        let tokens = (screens.last?.elements ?? [])
            .map(\.text)
            .filter { !$0.isEmpty }
        return tokens.joined(separator: " ") + "\n"
    }

    // MARK: - Private

    /// Map one explored screen's action into a single SkillStep YAML node.
    /// Returns nil when the label is empty or excluded (skipped, not invented).
    private static func stepLine(screen: ExploredScreen) -> String? {
        guard let rawLabel = screen.displayLabel ?? screen.arrivedVia, !rawLabel.isEmpty else {
            return screen.actionType == "press_home" ? "  - home:" : nil
        }
        let clean = ActionStepFormatter.cleanLabel(rawLabel)
        guard !clean.isEmpty, !ActionStepFormatter.isExcludedLabel(clean) else { return nil }
        let value = yamlScalar(ActionStepFormatter.resolveLabel(arrivedVia: clean, elements: screen.elements))
        switch screen.actionType {
        case "tap", nil: return "  - tap: \(value)"
        case "type": return "  - type: \(value)"
        case "press_key": return "  - press_key: \(value)"
        case "scroll_to": return "  - scroll_to: \(value)"
        case "swipe": return "  - swipe: \(value)"
        case "long_press": return "  - long_press: \(value)"
        case "open_url": return "  - open_url: \(value)"
        case "remember": return "  - remember: \(value)"
        case "screenshot": return "  - screenshot: \(value)"
        case "press_home": return "  - home:"
        default: return "  - tap: \(value)"
        }
    }

    /// Pick the destination landmark to assert: the longest non-excluded label
    /// on the final screen (prominence-by-length, mirroring `LandmarkPicker`).
    private static func landmark(in elements: [TapPoint]) -> String? {
        elements
            .map { ActionStepFormatter.cleanLabel($0.text) }
            .filter { $0.count >= 3 && !ActionStepFormatter.isExcludedLabel($0) }
            .max(by: { $0.count < $1.count })
    }

    /// Quote a value as a double-quoted YAML scalar, escaping `"`, `\`, and newlines.
    private static func yamlScalar(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default: out.append(c)
            }
        }
        return out + "\""
    }
}

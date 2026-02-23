// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Maps action type and arrivedVia pairs to markdown step text for SKILL.md.
// ABOUTME: Pure formatting function with no side effects.

/// Formats an exploration action into a markdown step string.
/// Maps action types (tap, swipe, type, etc.) to their display format.
enum ActionStepFormatter {

    /// Format an action step from actionType and arrivedVia.
    /// Returns nil if no action should be emitted (e.g. first screen with no arrivedVia).
    ///
    /// Most actions require `arrivedVia` to specify the target element or value.
    /// Self-sufficient actions like `press_home` emit a step without arrivedVia.
    static func format(actionType: String?, arrivedVia: String?) -> String? {
        guard let actionType = actionType, !actionType.isEmpty else {
            // No action type: only emit if arrivedVia is present (default to tap)
            guard let via = arrivedVia, !via.isEmpty else { return nil }
            return "Tap \"\(via)\""
        }

        // Self-sufficient actions that produce a step without arrivedVia
        switch actionType {
        case "press_home":
            return "Press Home"
        default:
            break
        }

        // All remaining actions require arrivedVia
        guard let arrivedVia = arrivedVia, !arrivedVia.isEmpty else { return nil }

        switch actionType {
        case "tap":
            return "Tap \"\(arrivedVia)\""
        case "swipe":
            return "swipe: \"\(arrivedVia)\""
        case "type":
            return "Type \"\(arrivedVia)\""
        case "press_key":
            return "Press **\(arrivedVia)**"
        case "scroll_to":
            return "Scroll until \"\(arrivedVia)\" is visible"
        case "long_press":
            return "long_press: \"\(arrivedVia)\""
        case "remember":
            return "Remember: \(arrivedVia)"
        case "screenshot":
            return "Screenshot: \"\(arrivedVia)\""
        case "assert_visible":
            return "Verify \"\(arrivedVia)\" is visible"
        case "assert_not_visible":
            return "Verify \"\(arrivedVia)\" is not visible"
        case "open_url":
            return "Open URL: \(arrivedVia)"
        default:
            return "Tap \"\(arrivedVia)\""
        }
    }
}

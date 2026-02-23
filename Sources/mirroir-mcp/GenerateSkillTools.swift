// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Registers the generate_skill MCP tool for AI-driven app exploration.
// ABOUTME: Session-based workflow: start (launch + OCR) -> capture (OCR + guidance) -> finish (emit SKILL.md).

import Foundation
import HelperLib

extension MirroirMCP {
    static func registerGenerateSkillTools(
        server: MCPServer,
        registry: TargetRegistry
    ) {
        let session = ExplorationSession()

        server.registerTool(MCPToolDefinition(
            name: "generate_skill",
            description: """
                Generate a SKILL.md by exploring an app. Session-based workflow: \
                (1) action="start" \u{2014} launch app, OCR first screen, begin session. \
                (2) Use tap/swipe/type_text to navigate, then action="capture" to OCR each screen. \
                (3) action="finish" \u{2014} assemble captured screens into a SKILL.md and return it.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Session action: \"start\" to launch app and begin, " +
                            "\"capture\" to OCR current screen and append, " +
                            "\"finish\" to generate SKILL.md from all captures."),
                        "enum": .array([
                            .string("start"),
                            .string("capture"),
                            .string("finish"),
                        ]),
                    ]),
                    "app_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "App to explore (required for start action)."),
                    ]),
                    "goal": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional flow description, e.g. \"check software version\" (for start action). " +
                            "Omit for discovery mode."),
                    ]),
                    "goals": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Optional array of goals for manifest mode. " +
                            "Each goal is explored in sequence, producing one SKILL.md per goal."),
                    ]),
                    "arrived_via": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Element tapped to reach current screen, e.g. \"General\" (for capture action)."),
                    ]),
                    "action_type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Action performed to reach current screen: " +
                            "\"tap\", \"swipe\", \"type\", \"press_key\", \"scroll_to\", " +
                            "\"long_press\", \"remember\", \"screenshot\", \"press_home\", " +
                            "\"open_url\" (for capture action)."),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ],
            handler: { args in
                guard let action = args["action"]?.asString() else {
                    return .error("Missing required parameter: action")
                }

                switch action {
                case "start":
                    return handleStart(args: args, session: session, registry: registry)
                case "capture":
                    return handleCapture(args: args, session: session, registry: registry)
                case "finish":
                    return handleFinish(session: session)
                default:
                    return .error("Unknown action '\(action)'. Use: start, capture, finish.")
                }
            }
        ))
    }

    // MARK: - Action Handlers

    private static func handleStart(
        args: [String: JSONValue],
        session: ExplorationSession,
        registry: TargetRegistry
    ) -> MCPToolResult {
        guard let appName = args["app_name"]?.asString(), !appName.isEmpty else {
            return .error("Missing required parameter: app_name (for start action)")
        }

        if session.active {
            return .error(
                "An exploration session is already active for '\(session.currentAppName)'. " +
                "Call finish first or start a new session.")
        }

        let (ctx, err) = registry.resolveForTool(args)
        guard let ctx else { return err! }

        // Launch the app
        if let launchError = ctx.input.launchApp(name: appName) {
            return .error("Failed to launch '\(appName)': \(launchError)")
        }

        // Wait for app to settle
        usleep(EnvConfig.stepSettlingDelayMs * 1000)

        // Parse goal(s) and start session
        let goal = args["goal"]?.asString() ?? ""
        let goals = args["goals"]?.asStringArray() ?? []
        session.start(appName: appName, goal: goal, goals: goals)

        // OCR first screen
        guard let result = ctx.describer.describe(skipOCR: false) else {
            return .error(
                "Failed to capture/analyze screen after launching '\(appName)'. " +
                "Is the target window visible?")
        }

        // Capture first screen (no action since this is the initial screen)
        session.capture(
            elements: result.elements,
            hints: result.hints,
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: result.screenshotBase64
        )

        // Generate mode-specific preamble
        let modeName = session.currentMode == .discovery ? "Discovery" : "Goal-driven"
        var preamble = "Exploration started for '\(appName)' (\(modeName) mode). Screen 1 captured."
        if !goals.isEmpty {
            preamble += " Manifest: \(goals.count) goals queued."
        }

        let description = formatScreenDescription(
            elements: result.elements,
            hints: result.hints,
            preamble: preamble
        )

        // Generate initial guidance
        let guidance = ExplorationGuide.analyze(
            mode: session.currentMode,
            goal: session.currentGoal,
            elements: result.elements,
            hints: result.hints,
            startElements: nil,
            actionLog: [],
            screenCount: 1
        )

        let guidanceText = ExplorationGuide.formatGuidance(guidance)

        return MCPToolResult(
            content: [
                .text(description + guidanceText),
                .image(result.screenshotBase64, mimeType: "image/png"),
            ],
            isError: false
        )
    }

    private static func handleCapture(
        args: [String: JSONValue],
        session: ExplorationSession,
        registry: TargetRegistry
    ) -> MCPToolResult {
        guard session.active else {
            return .error("No active exploration session. Call generate_skill with action=\"start\" first.")
        }

        let (ctx, err) = registry.resolveForTool(args)
        guard let ctx else { return err! }

        // OCR current screen
        guard let result = ctx.describer.describe(skipOCR: false) else {
            return .error("Failed to capture/analyze screen. Is the target window visible?")
        }

        let arrivedVia = args["arrived_via"]?.asString()
        let actionType = args["action_type"]?.asString()

        let accepted = session.capture(
            elements: result.elements,
            hints: result.hints,
            actionType: actionType,
            arrivedVia: arrivedVia,
            screenshotBase64: result.screenshotBase64
        )

        if !accepted {
            // Still provide guidance even on duplicate rejection
            let guidance = ExplorationGuide.analyze(
                mode: session.currentMode,
                goal: session.currentGoal,
                elements: result.elements,
                hints: result.hints,
                startElements: session.startScreenElements,
                actionLog: session.actions,
                screenCount: session.screenCount
            )
            let guidanceText = ExplorationGuide.formatGuidance(guidance)

            return .text(
                "Screen unchanged \u{2014} capture skipped (duplicate of previous screen). " +
                "Try a different action before capturing again." + guidanceText)
        }

        let screenNum = session.screenCount
        let preamble = "Screen \(screenNum) captured" +
            (arrivedVia.map { " (arrived via \"\($0)\")" } ?? "") + "."

        let description = formatScreenDescription(
            elements: result.elements,
            hints: result.hints,
            preamble: preamble
        )

        // Generate guidance for the agent
        let guidance = ExplorationGuide.analyze(
            mode: session.currentMode,
            goal: session.currentGoal,
            elements: result.elements,
            hints: result.hints,
            startElements: session.startScreenElements,
            actionLog: session.actions,
            screenCount: screenNum
        )

        let guidanceText = ExplorationGuide.formatGuidance(guidance)

        return MCPToolResult(
            content: [
                .text(description + guidanceText),
                .image(result.screenshotBase64, mimeType: "image/png"),
            ],
            isError: false
        )
    }

    private static func handleFinish(session: ExplorationSession) -> MCPToolResult {
        guard session.active else {
            return .error("No active exploration session. Call generate_skill with action=\"start\" first.")
        }

        guard session.screenCount > 0 else {
            return .error("No screens captured. Use capture action before finishing.")
        }

        // Check for remaining goals before finalize (which advances the queue)
        let remaining = session.remainingGoals
        let goalNum = session.currentGoalIndex + 1
        let totalGoals = session.totalGoals

        guard let data = session.finalize() else {
            return .error("Failed to finalize exploration session.")
        }

        let skillMd = SkillMdGenerator.generate(
            appName: data.appName,
            goal: data.goal,
            screens: data.screens
        )

        // Build response with manifest progress if applicable
        var responseText = skillMd
        if !remaining.isEmpty {
            responseText += "\n\n---\n"
            responseText += "Goal \(goalNum)/\(totalGoals) complete. "
            responseText += "Next goal: \"\(remaining[0])\". "
            responseText += "Session auto-advanced \u{2014} call capture to continue, "
            responseText += "or finish again when done."
            if remaining.count > 1 {
                let queued = remaining.dropFirst().map { "\"\($0)\"" }.joined(separator: ", ")
                responseText += "\nRemaining after next: \(queued)"
            }
        }

        return .text(responseText)
    }

    // MARK: - Formatting

    /// Format OCR elements and hints into a text description.
    /// Same pattern as describe_screen in ScreenTools.swift.
    private static func formatScreenDescription(
        elements: [TapPoint],
        hints: [String],
        preamble: String
    ) -> String {
        var lines = [preamble, "", "Screen elements (tap coordinates in points):"]
        for el in elements.sorted(by: { $0.tapY < $1.tapY }) {
            lines.append("- \"\(el.text)\" at (\(Int(el.tapX)), \(Int(el.tapY)))")
        }
        if elements.isEmpty {
            lines.append("(no text detected)")
        }
        if !hints.isEmpty {
            lines.append("")
            lines.append("Hints:")
            for hint in hints {
                lines.append("- \(hint)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

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
                (3) action="finish" \u{2014} assemble captured screens into a SKILL.md and return it. \
                Alternatively, use action="explore" for autonomous DFS exploration.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Session action: \"start\" to launch app and begin, " +
                            "\"capture\" to OCR current screen and append, " +
                            "\"finish\" to generate SKILL.md from all captures, " +
                            "\"explore\" for autonomous DFS exploration."),
                        "enum": .array([
                            .string("start"),
                            .string("capture"),
                            .string("finish"),
                            .string("explore"),
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
                    "max_depth": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum DFS depth for explore action (default: 6)."),
                    ]),
                    "max_screens": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum screens to visit for explore action (default: 30)."),
                    ]),
                    "max_time": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum seconds for explore action (default: 300)."),
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
                case "explore":
                    return handleExplore(args: args, session: session, registry: registry)
                default:
                    return .error("Unknown action '\(action)'. Use: start, capture, finish, explore.")
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
            icons: result.icons,
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
            icons: result.icons,
            actionType: actionType,
            arrivedVia: arrivedVia,
            screenshotBase64: result.screenshotBase64
        )

        if !accepted {
            // Still provide guidance even on duplicate rejection — use strategy if graph available
            let guidance = generateGuidance(
                session: session, elements: result.elements,
                icons: result.icons, hints: result.hints
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

        // Generate guidance for the agent — prefer strategy-based when graph available
        let guidance = generateGuidance(
            session: session, elements: result.elements,
            icons: result.icons, hints: result.hints
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

        // Use SkillBundleGenerator for multi-path graphs, single skill otherwise
        let bundle = SkillBundleGenerator.generate(
            appName: data.appName,
            goal: data.goal,
            snapshot: data.graphSnapshot,
            allScreens: data.screens
        )

        var responseText: String
        if bundle.skills.count > 1 {
            responseText = "Generated \(bundle.skills.count) skills from exploration:\n\n"
            for (i, skill) in bundle.skills.enumerated() {
                responseText += "--- Skill \(i + 1): \(skill.name) ---\n\n"
                responseText += skill.content
                if i < bundle.skills.count - 1 {
                    responseText += "\n\n"
                }
            }
        } else {
            responseText = bundle.skills.first?.content ?? ""
        }
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

    // MARK: - Explore Handler

    private static func handleExplore(
        args: [String: JSONValue],
        session: ExplorationSession,
        registry: TargetRegistry
    ) -> MCPToolResult {
        guard let appName = args["app_name"]?.asString(), !appName.isEmpty else {
            return .error("Missing required parameter: app_name (for explore action)")
        }

        if session.active {
            return .error(
                "An exploration session is already active for '\(session.currentAppName)'. " +
                "Call finish first.")
        }

        let (ctx, err) = registry.resolveForTool(args)
        guard let ctx else { return err! }

        // Launch the app
        if let launchError = ctx.input.launchApp(name: appName) {
            return .error("Failed to launch '\(appName)': \(launchError)")
        }
        usleep(EnvConfig.stepSettlingDelayMs * 1000)

        // Parse budget overrides
        let maxDepth = args["max_depth"]?.asInt() ?? ExplorationBudget.default.maxDepth
        let maxScreens = args["max_screens"]?.asInt() ?? ExplorationBudget.default.maxScreens
        let maxTime = args["max_time"]?.asInt() ?? ExplorationBudget.default.maxTimeSeconds
        let budget = ExplorationBudget(
            maxDepth: maxDepth,
            maxScreens: maxScreens,
            maxTimeSeconds: maxTime,
            maxActionsPerScreen: ExplorationBudget.default.maxActionsPerScreen,
            scrollLimit: ExplorationBudget.default.scrollLimit,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let goal = args["goal"]?.asString() ?? ""
        session.start(appName: appName, goal: goal)

        // OCR first screen
        guard let firstResult = ctx.describer.describe(skipOCR: false) else {
            return .error("Failed to capture initial screen for '\(appName)'.")
        }

        // Capture first screen
        session.capture(
            elements: firstResult.elements, hints: firstResult.hints,
            icons: firstResult.icons, actionType: nil, arrivedVia: nil,
            screenshotBase64: firstResult.screenshotBase64
        )

        // Create DFS explorer and run exploration loop
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        var stepResults: [String] = [
            "Autonomous exploration started for '\(appName)'.",
            "Budget: depth=\(maxDepth), screens=\(maxScreens), time=\(maxTime)s",
        ]

        // Run DFS loop
        while !explorer.completed {
            let result = explorer.step(
                describer: ctx.describer,
                input: ctx.input,
                strategy: MobileAppStrategy.self
            )

            switch result {
            case .continue(let desc):
                stepResults.append(desc)
            case .backtracked(_, _):
                stepResults.append("Backtracked to parent screen.")
            case .paused(let reason):
                stepResults.append("Paused: \(reason)")
                // Return intermediate results so AI can handle the situation
                let stats = explorer.stats
                let summary = stepResults.joined(separator: "\n")
                return .text(
                    "\(summary)\n\nExploration paused after \(stats.actionCount) actions, " +
                    "\(stats.nodeCount) screens in \(stats.elapsedSeconds)s.")
            case .finished(let bundle):
                let stats = explorer.stats
                var responseText: String
                if bundle.skills.count > 1 {
                    responseText = "Exploration complete! Generated \(bundle.skills.count) skills "
                    responseText += "(\(stats.nodeCount) screens, \(stats.actionCount) actions, "
                    responseText += "\(stats.elapsedSeconds)s):\n\n"
                    for (i, skill) in bundle.skills.enumerated() {
                        responseText += "--- Skill \(i + 1): \(skill.name) ---\n\n"
                        responseText += skill.content
                        if i < bundle.skills.count - 1 {
                            responseText += "\n\n"
                        }
                    }
                } else if let skill = bundle.skills.first {
                    responseText = "Exploration complete "
                    responseText += "(\(stats.nodeCount) screens, \(stats.actionCount) actions, "
                    responseText += "\(stats.elapsedSeconds)s):\n\n"
                    responseText += skill.content
                } else {
                    responseText = "Exploration finished but no skills were generated."
                }
                return .text(responseText)
            }
        }

        // Should not reach here, but just in case
        return .text(stepResults.joined(separator: "\n"))
    }

    // MARK: - Guidance

    /// Generate exploration guidance, preferring strategy-based analysis when the graph is populated.
    /// Falls back to the keyword-based ExplorationGuide.analyze() for backward compatibility.
    private static func generateGuidance(
        session: ExplorationSession,
        elements: [TapPoint],
        icons: [IconDetector.DetectedIcon],
        hints: [String]
    ) -> ExplorationGuide.Guidance {
        let graph = session.currentGraph
        if graph.started {
            return ExplorationGuide.analyzeWithStrategy(
                strategy: MobileAppStrategy.self,
                graph: graph,
                elements: elements,
                icons: icons,
                hints: hints,
                budget: .default,
                goal: session.currentGoal
            )
        }
        return ExplorationGuide.analyze(
            mode: session.currentMode,
            goal: session.currentGoal,
            elements: elements,
            hints: hints,
            startElements: session.startScreenElements,
            actionLog: session.actions,
            screenCount: session.screenCount
        )
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

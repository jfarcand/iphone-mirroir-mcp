// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Classifier implementations bridging heuristic and LLM-based component detection.
// ABOUTME: SamplingClassifier uses MCP sampling to ask the client LLM for component classification.

import Foundation
import HelperLib

/// Supported component detection modes, controlled by MIRROIR_COMPONENT_DETECTION.
enum ComponentDetectionMode: String, Sendable {
    case heuristic
    case llmFirstScreen = "llm_first_screen"
    case llmEveryScreen = "llm_every_screen"
    case llmFallback = "llm_fallback"

    /// Build the appropriate component classifier for this detection mode.
    func buildClassifier(server: MCPServer) -> any ComponentClassifying {
        let heuristic = HeuristicClassifier()
        let sampling = { SamplingClassifier(server: server) }
        switch self {
        case .heuristic:
            return heuristic
        case .llmFirstScreen:
            return CompositeClassifier(
                primary: sampling(), fallback: heuristic, primaryOnlyForFirstScreen: true)
        case .llmEveryScreen:
            return CompositeClassifier(
                primary: sampling(), fallback: heuristic, primaryOnlyForFirstScreen: false)
        case .llmFallback:
            return CompositeClassifier(
                primary: heuristic, fallback: sampling(), primaryOnlyForFirstScreen: false)
        }
    }
}

/// Wraps ComponentDetector.detect() as a ComponentClassifying implementation.
/// Used when only heuristic matching is needed (no LLM calls).
final class HeuristicClassifier: ComponentClassifying, @unchecked Sendable {
    init() {}

    func classify(
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition],
        screenHeight: Double
    ) -> [ScreenComponent]? {
        ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )
    }
}

/// Uses MCP sampling to ask the client LLM to classify screen components.
/// Sends a screenshot + OCR elements + component catalog to the client,
/// parses the structured JSON response back into ScreenComponents.
final class SamplingClassifier: ComponentClassifying, @unchecked Sendable {
    private let server: MCPServer

    init(server: MCPServer) {
        self.server = server
    }

    func classify(
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition],
        screenHeight: Double
    ) -> [ScreenComponent]? {
        let prompt = buildPrompt(classified: classified, definitions: definitions)

        let params = SamplingParams(
            messages: [SamplingMessage(role: "user", content: .text(prompt))],
            maxTokens: 2000,
            systemPrompt: "You analyze iOS app screens and classify OCR elements into UI components. " +
                "Respond ONLY with valid JSON, no markdown formatting."
        )

        guard let responseText = server.sendSamplingRequest(params) else {
            DebugLog.log("sampling", "Sampling request failed, falling back to heuristics")
            return nil
        }

        return parseSamplingResponse(
            responseText,
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )
    }

    /// Build the prompt for the client LLM describing available components and current elements.
    private func buildPrompt(
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition]
    ) -> String {
        var prompt = "Analyze the following OCR elements from an iOS app screen.\n"
        prompt += "Group them into UI components from the catalog below.\n\n"

        prompt += "## Component Catalog\n\n"
        for def in definitions {
            prompt += "- **\(def.name)**: \(def.description)"
            if def.interaction.clickable {
                prompt += " [clickable]"
            }
            prompt += "\n"
        }

        prompt += "\n## OCR Elements\n\n"
        for element in classified {
            prompt += "- \"\(element.point.text)\" at (\(Int(element.point.tapX)), "
            prompt += "\(Int(element.point.tapY))) role=\(element.role.rawValue)"
            if element.hasChevronContext {
                prompt += " [chevron]"
            }
            prompt += "\n"
        }

        prompt += "\n## Instructions\n\n"
        prompt += "Group the elements into components. For each group, specify:\n"
        prompt += "1. The component type from the catalog\n"
        prompt += "2. Which element texts belong to this component\n"
        prompt += "3. Which element to tap (if clickable)\n\n"
        prompt += "Respond with a JSON array:\n"
        prompt += """
            [
              {"component": "table-row-disclosure", "elements": ["General", ">"], "tap_target": "General"},
              {"component": "explanation-text", "elements": ["Some help text"], "tap_target": null}
            ]
            """

        return prompt
    }

    /// Parse the LLM's JSON response into ScreenComponents.
    /// Falls back to nil if the response is not valid JSON.
    private func parseSamplingResponse(
        _ responseText: String,
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition],
        screenHeight: Double
    ) -> [ScreenComponent]? {
        // Strip markdown code fences if present
        var text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = text.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            DebugLog.log("sampling", "Failed to parse sampling response as JSON array")
            return nil
        }

        let defsByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        let classifiedByText = Dictionary(
            classified.map { ($0.point.text, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var components: [ScreenComponent] = []
        for entry in jsonArray {
            guard let componentName = entry["component"] as? String,
                  let elementTexts = entry["elements"] as? [String],
                  let definition = defsByName[componentName] else {
                continue
            }

            let matchedElements = elementTexts.compactMap { classifiedByText[$0] }
            guard !matchedElements.isEmpty else { continue }

            let tapTargetText = entry["tap_target"] as? String
            let tapTarget = tapTargetText.flatMap { text in
                matchedElements.first { $0.point.text == text }?.point
            }

            let ys = matchedElements.map { $0.point.tapY }
            let hasChevron = matchedElements.contains { element in
                ElementClassifier.chevronCharacters.contains(
                    element.point.text.trimmingCharacters(in: .whitespaces)
                )
            }

            components.append(ScreenComponent(
                kind: componentName,
                definition: definition,
                elements: matchedElements,
                tapTarget: tapTarget,
                hasChevron: hasChevron,
                topY: ys.min() ?? 0,
                bottomY: ys.max() ?? 0
            ))
        }

        return components.isEmpty ? nil : components
    }
}

/// Combines a primary and fallback classifier with configurable strategy.
/// When `primaryOnlyForFirstScreen` is true, the primary classifier is used only for
/// the first screen, and the fallback handles all subsequent screens.
final class CompositeClassifier: ComponentClassifying, @unchecked Sendable {
    private let primary: ComponentClassifying
    private let fallback: ComponentClassifying
    private let primaryOnlyForFirstScreen: Bool
    private var screensSeen: Int = 0
    private let lock = NSLock()

    init(
        primary: ComponentClassifying,
        fallback: ComponentClassifying,
        primaryOnlyForFirstScreen: Bool
    ) {
        self.primary = primary
        self.fallback = fallback
        self.primaryOnlyForFirstScreen = primaryOnlyForFirstScreen
    }

    func classify(
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition],
        screenHeight: Double
    ) -> [ScreenComponent]? {
        lock.lock()
        let currentScreen = screensSeen
        screensSeen += 1
        lock.unlock()

        let usePrimary = !primaryOnlyForFirstScreen || currentScreen == 0

        if usePrimary {
            if let result = primary.classify(
                classified: classified, definitions: definitions,
                screenHeight: screenHeight
            ) {
                return result
            }
        }

        return fallback.classify(
            classified: classified, definitions: definitions,
            screenHeight: screenHeight
        )
    }
}

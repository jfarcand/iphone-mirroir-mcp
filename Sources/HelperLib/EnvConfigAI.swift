// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: AI-facing EnvConfig properties (provider timeouts, component detection, agent transport, vision describer).
// ABOUTME: Split from EnvConfigFeatures.swift to stay under the 500-line limit.

import Foundation

extension EnvConfig {

    // MARK: - AI Provider

    public static var openAITimeoutSeconds: Int {
        readInt("openAITimeoutSeconds", default: TimingConstants.openAITimeoutSeconds)
    }

    public static var ollamaTimeoutSeconds: Int {
        readInt("ollamaTimeoutSeconds", default: TimingConstants.ollamaTimeoutSeconds)
    }

    public static var anthropicTimeoutSeconds: Int {
        readInt("anthropicTimeoutSeconds", default: TimingConstants.anthropicTimeoutSeconds)
    }

    public static var embacleTimeoutSeconds: Int {
        readInt("embacleTimeoutSeconds", default: TimingConstants.embacleTimeoutSeconds)
    }

    public static var commandTimeoutSeconds: Int {
        readInt("commandTimeoutSeconds", default: TimingConstants.commandTimeoutSeconds)
    }

    public static var defaultAIMaxTokens: Int {
        readInt("defaultAIMaxTokens", default: TimingConstants.defaultAIMaxTokens)
    }

    public static var visionMaxTokens: Int {
        readInt("visionMaxTokens", default: TimingConstants.visionMaxTokens)
    }

    // MARK: - Component Detection

    /// Component detection mode for BFS exploration.
    /// Controls how OCR elements are grouped into UI components.
    ///
    /// Values:
    /// - `heuristic`: Phase 1 only — component.md match rules, no LLM calls.
    /// - `llm_first_screen`: (DEFAULT) LLM classifies first screen, heuristics for rest.
    /// - `llm_every_screen`: LLM classifies every new screen.
    /// - `llm_fallback`: Heuristics first, LLM when no confident match.
    public static var componentDetection: String {
        readString("componentDetection", envVar: "MIRROIR_COMPONENT_DETECTION",
                   default: "llm_first_screen")
    }

    // MARK: - Agent Transport

    /// Agent transport mode: "auto" (default) or "http".
    /// When "auto", uses embedded Rust FFI if linked, otherwise falls back to HTTP.
    /// Set to "http" to force HTTP even when the embedded runtime is available.
    public static var agentTransport: String {
        readString("agentTransport", envVar: "MIRROIR_AGENT_TRANSPORT", default: "auto")
    }

    // MARK: - Screen Describer

    /// Screen describer mode: "auto" (default), "ocr", or "vision".
    /// "auto" resolves to "vision" when the embacle FFI is linked, "ocr" otherwise.
    /// "vision" uses an AI vision model (via configured agent) to describe screens
    /// instead of local OCR + YOLO. Requires a configured agent (e.g. embacle).
    /// "ocr" forces local Vision OCR + YOLO regardless of embacle availability.
    public static var screenDescriberMode: String {
        readString("screenDescriberMode", envVar: "MIRROIR_SCREEN_DESCRIBER_MODE",
                   default: "auto")
    }

    /// Override the model name sent in vision chat completion requests.
    /// Empty string means use the provider default (e.g. "copilot_headless" for embacle).
    public static var visionModel: String {
        readString("visionModel", envVar: "MIRROIR_VISION_MODEL",
                   default: TimingConstants.visionModel)
    }

    /// Target image width (in pixels) for vision API calls. Screenshots are resized
    /// to this width before sending to the vision model to stay within payload limits.
    public static var visionImageWidth: Int {
        readInt("visionImageWidth", default: 500)
    }

    /// AI agent name for vision screen description and diagnosis.
    /// Resolved via AIAgentRegistry. Empty string means no agent configured.
    public static var agent: String {
        readString("agent", envVar: "MIRROIR_AGENT", default: "")
    }
}

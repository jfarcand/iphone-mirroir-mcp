// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Auto-detects the appropriate exploration strategy based on target type, bundle ID, and app name.
// ABOUTME: Returns a StrategyChoice enum value used by GenerateSkillTools and ExplorationSession.

import Foundation

/// The detected exploration strategy for an app.
enum StrategyChoice: String, Sendable {
    case mobile
    case social
    case desktop
}

/// Detects the appropriate exploration strategy for a target/app combination.
/// Detection order: explicit override → target type → bundle ID → app name → mobile default.
enum StrategyDetector {

    /// Known social media app bundle ID prefixes.
    static let socialBundlePrefixes: [String] = [
        "com.reddit.",
        "com.facebook.",
        "com.instagram.",
        "com.atebits.Tweetie2",
        "com.zhiliaoapp.musically",
        "com.toyopagroup.picaboo",
    ]

    /// Known social media app names (case-insensitive matching).
    static let socialAppNames: Set<String> = [
        "reddit", "instagram", "facebook", "twitter", "x", "tiktok", "snapchat",
    ]

    /// Detect the exploration strategy based on available context.
    ///
    /// - Parameters:
    ///   - targetType: The target type string (e.g. "iphone-mirroring", "generic-window").
    ///   - bundleID: Optional iOS bundle identifier of the app.
    ///   - appName: The display name of the app being explored.
    ///   - explicitStrategy: Optional explicit override from the user.
    /// - Returns: The detected strategy choice.
    static func detect(
        targetType: String,
        bundleID: String?,
        appName: String,
        explicitStrategy: String? = nil
    ) -> StrategyChoice {
        // Explicit override takes priority
        if let explicit = explicitStrategy {
            if let choice = StrategyChoice(rawValue: explicit) {
                return choice
            }
        }

        // Target type: generic windows → desktop strategy
        if targetType == "generic-window" {
            return .desktop
        }

        // Bundle ID matching for social apps
        if let bundleID = bundleID {
            let lowered = bundleID.lowercased()
            for prefix in socialBundlePrefixes {
                if lowered.hasPrefix(prefix.lowercased()) {
                    return .social
                }
            }
        }

        // App name fallback for social apps
        if socialAppNames.contains(appName.lowercased()) {
            return .social
        }

        // Default: mobile
        return .mobile
    }
}
